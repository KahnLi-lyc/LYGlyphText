import CoreText
import UIKit

/// 最终排版的一次性绘制计划；按动作 ordinal 保存稀疏引用，不持有文档或建立新 CTLine。
struct PressedTextDrawing {
    struct Run {
        let run: CTRun
        let baseline: CGPoint
        let color: CGColor
        let isColorGlyph: Bool
        let glyphCount: Int
        let shadow: ResolvedShadow?
        /// 属于截断 token 的 run；token 使用独立标记属性，不与原文合并为同一 run。
        let isTruncationToken: Bool
    }

    enum Operation {
        case ordinary(CFRange)
        case selected(Int, Selection)
    }

    struct Glyph {
        let run: CTRun
        let range: CFRange
        let baseline: CGPoint
        let color: CGColor
        let inkBounds: CGRect
        let layerBounds: CGRect
    }

    struct Background {
        let color: CGColor?
        let members: [VisibleTextFragment.RunPiece]
        let ordinary: DrawingPathTree
    }

    struct BackgroundPatch {
        let consumed: Int
        let plan: SourcePaintPlan
    }

    struct Selection {
        let color: CGColor
        let clip: DrawingClip
    }

    struct Action {
        var runs: [Int: [Operation]] = [:]
        var backgrounds: [Int: BackgroundPatch] = [:]
        var strokes: [Int: SourcePaintPlan] = [:]
    }

    let runs: [Run]
    let glyphs: [Glyph]
    let backgrounds: [Background]
    let strokes: [TextDecorations.StrokeGroup]
    let actions: [Action]

    init(
        lines: [LYGlyphTextLayout.Line], geometry: SourceGeometry?,
        actions sourceActions: [LYGlyphTextLayout.ActionSourceEntry],
        decorations: TextDecorations?, prepared: TextDecorations.Prepared?, traits: UITraitCollection,
        observe: (TextDecorations.PreparationEvent) -> Void
    ) {
        observe(.drawingPlan)
        // 普通绘制保持 run 粒度；只有动作真正涉及的字形才需要局部着色记录。
        var runs: [Run] = []
        var runLookup: [[Int]] = []
        for line in lines {
            var indices: [Int] = []
            for run in CTLineGetGlyphRuns(line.text) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let color = attributes[kCTForegroundColorAttributeName].map { $0 as! CGColor } ?? UIColor.label
                    .resolvedColor(with: traits).cgColor
                let font = attributes[kCTFontAttributeName].map { $0 as! CTFont }
                let isColorGlyph = font.map { CTFontGetSymbolicTraits($0).contains(.traitColorGlyphs) } ?? false
                indices.append(runs.count)
                runs.append(.init(
                    run: run,
                    baseline: line.baseline,
                    color: color,
                    isColorGlyph: isColorGlyph,
                    glyphCount: CTRunGetGlyphCount(run),
                    shadow: attributes[ResolvedShadow.key] as? ResolvedShadow,
                    isTruncationToken: attributes[TailTruncation.tokenKey] != nil
                ))
            }
            runLookup.append(indices)
        }
        self.runs = runs
        strokes = prepared?.allGroups ?? []
        let styles = decorations?.styles ?? []
        var members: [Int: [VisibleTextFragment.RunPiece]] = [:]
        for cell in geometry?.cells ?? [] {
            for piece in cell.pieces {
                var low = 0, high = styles.count
                while low < high {
                    let middle = (low + high) / 2
                    if NSMaxRange(styles[middle].range) <= piece.sourceRange.location { low = middle + 1 }
                    else { high = middle }
                }
                while low < styles.count, styles[low].range.location < NSMaxRange(piece.sourceRange) {
                    members[low, default: []].append(piece)
                    low += 1
                }
            }
        }
        // nil 背景也保存源成员；按下时才能在原本没有填充的字符上建立背景。
        // nil 成员不切断同色批次，与原装饰合批政策相同。
        var backgroundMembers: [[(VisibleTextFragment.RunPiece, CGColor?)]] = []
        var backgroundColors: [CGColor?] = []
        for index in members.keys.sorted() {
            let color = styles[index].background
            if backgroundMembers.isEmpty || (color != nil && backgroundColors.last.flatMap(\.self) != color) {
                backgroundMembers.append([])
                backgroundColors.append(color)
            }
            for piece in members[index] ?? [] {
                backgroundMembers[backgroundMembers.count - 1].append((piece, color))
            }
        }
        if backgroundMembers.isEmpty, let geometry {
            backgroundMembers = [geometry.cells.flatMap(\.pieces).map { ($0, nil) }]
            backgroundColors = [nil]
        }
        let backgrounds = backgroundMembers.enumerated().map { index, entries in
            Background(
                color: backgroundColors[index], members: entries.map(\.0),
                ordinary: DrawingPathTree(entries.map { $0.1 == nil ? [] : [$0.0.rect] })
            )
        }
        self.backgrounds = backgrounds
        let backgroundPaintMembers = backgroundMembers.enumerated().flatMap { index, entries in
            entries.map { SourcePaintPlan.Member(color: $0.1, group: index, rects: [$0.0.rect]) }
        }
        let backgroundTree = DrawingPathTree(
            backgroundPaintMembers.map(\.rects),
            colors: backgroundPaintMembers.map(\.color)
        )
        var actionPlans = [Action](repeating: Action(), count: sourceActions.count)
        guard let geometry, !sourceActions.isEmpty else { actions = actionPlans
            glyphs = []
            return
        }
        let ordered = sourceActions.sorted { $0.action.range.location < $1.action.range.location }
        /// 源动作不重叠；一次源 cell 遍历通过二分定位 ordinal，避免每动作扫描全文。
        func owner(_ range: NSRange) -> Int? {
            var low = 0, high = ordered.count
            while low < high {
                let middle = (low + high) / 2
                if NSMaxRange(ordered[middle].action.range) <= range.location { low = middle + 1 }
                else { high = middle }
            }
            guard low < ordered.count,
                  NSIntersectionRange(ordered[low].action.range, range).length > 0 else { return nil }
            return ordered[low].actionIndex
        }
        let foreground = sourceActions
            .map { $0.action.pressedStyle.foregroundColor?.resolvedColor(with: traits).cgColor }
        // 圆角背景由 Layout 按合并后的片段单独绘制，这里不再生成直角补丁。
        let background = sourceActions.map { entry -> CGColor? in
            guard entry.action.pressedStyle.cornerRadius == 0 else { return nil }
            return entry.action.pressedStyle.backgroundColor?.resolvedColor(with: traits).cgColor
        }
        var selectedCells: [Int: [VisibleTextFragment.RunPiece]] = [:]
        let visibleRects = sourceActions.map { Set($0.rects.map(RectKey.init)) }
        for cell in geometry.cells {
            guard let ordinal = owner(cell.range) else { continue }
            let pieces = cell.pieces.filter { visibleRects[ordinal].contains(RectKey($0.rect)) && $0.rect.width > 0 }
            selectedCells[ordinal, default: []].append(contentsOf: pieces)
        }
        var glyphRects: [Int: [Int: [Int: [CGRect]]]] = [:]
        for (ordinal, pieces) in selectedCells where foreground[ordinal] != nil {
            for piece in pieces {
                let runIndex = runLookup[piece.lineIndex][piece.runIndex]
                guard !runs[runIndex].isColorGlyph else { continue }
                for index in piece.glyphIndices {
                    glyphRects[ordinal, default: [:]][runIndex, default: [:]][index, default: []].append(piece.rect)
                }
            }
        }
        var glyphs: [Glyph] = []
        var glyphLookup: [Int: [Int: Int]] = [:]
        for (ordinal, selectedRuns) in glyphRects {
            guard let color = foreground[ordinal] else { continue }
            for (runIndex, selectedGlyphs) in selectedRuns {
                let run = runs[runIndex]
                var operations: [Operation] = []
                var cursor = 0
                for index in selectedGlyphs.keys.sorted() {
                    guard let rects = selectedGlyphs[index] else { continue }
                    if cursor < index {
                        operations.append(.ordinary(CFRange(location: cursor, length: index - cursor)))
                    }
                    let glyphIndex: Int
                    if let existing = glyphLookup[runIndex]?[index] {
                        glyphIndex = existing
                    } else {
                        glyphIndex = glyphs.count
                        let range = CFRange(location: index, length: 1)
                        observe(.glyphImageBoundsQuery)
                        let bounds = CTRunGetImageBounds(run.run, nil, range)
                        let inkBounds = CGRect(
                            x: run.baseline.x + bounds.minX, y: run.baseline.y - bounds.maxY,
                            width: bounds.width, height: bounds.height
                        )
                        observe(.glyphPaintRecord)
                        glyphs.append(.init(
                            run: run.run,
                            range: range,
                            baseline: run.baseline,
                            color: run.color,
                            inkBounds: inkBounds,
                            layerBounds: inkBounds.insetBy(dx: -1, dy: -1)
                        ))
                        glyphLookup[runIndex, default: [:]][index] = glyphIndex
                    }
                    observe(.selectionPreparation)
                    operations.append(.selected(glyphIndex, .init(
                        color: color, clip: DrawingClip(rects, covering: glyphs[glyphIndex].inkBounds)
                    )))
                    cursor = index + 1
                }
                if cursor < run.glyphCount {
                    operations.append(.ordinary(CFRange(location: cursor, length: run.glyphCount - cursor)))
                }
                actionPlans[ordinal].runs[runIndex] = operations
            }
        }
        self.glyphs = glyphs
        var backgroundSelections: [Int: [Int: [Int]]] = [:]
        var backgroundOffset = 0
        for (index, layer) in backgrounds.enumerated() {
            for (memberIndex, member) in layer.members.enumerated() {
                guard let ordinal = owner(member.sourceRange), background[ordinal] != nil,
                      visibleRects[ordinal].contains(RectKey(member.rect)) else { continue }
                backgroundSelections[ordinal, default: [:]][index, default: []].append(backgroundOffset + memberIndex)
            }
            backgroundOffset += layer.members.count
        }
        for (ordinal, selections) in backgroundSelections {
            guard let color = background[ordinal], let first = selections.keys.min(),
                  let last = selections.keys.max() else { continue }
            observe(.selectionPreparation)
            actionPlans[ordinal].backgrounds[first] = .init(consumed: last - first + 1, plan: SourcePaintPlan(
                members: backgroundPaintMembers, tree: backgroundTree,
                selected: selections.values.flatMap(\.self), color: color, groups: first ... last, observe: observe
            ))
        }
        for (index, group) in strokes.enumerated() {
            var selections: [Int: [Int]] = [:]
            for (memberIndex, member) in group.members.enumerated() where member.colorIsInherited {
                guard let ordinal = owner(member.member.piece.sourceRange), foreground[ordinal] != nil,
                      visibleRects[ordinal].contains(RectKey(member.member.piece.rect)) else { continue }
                selections[ordinal, default: []].append(memberIndex)
            }
            guard !selections.isEmpty else { continue }
            let starts = Set(group.mergedIntervals.map(\.lowerBound))
            let ends = Set(group.mergedIntervals.map(\.upperBound))
            let paintMembers = group.members.map { member in
                let left = member.interval.lowerBound - (starts.contains(member.interval.lowerBound) ? 1 : 0)
                let right = member.interval.upperBound + (ends.contains(member.interval.upperBound) ? 1 : 0)
                return SourcePaintPlan.Member(
                    color: member.color,
                    group: 0,
                    rects:
                    member.verticalIntervals(scale: decorations?.scale ?? 1).map { band in
                        CGRect(
                            x: left,
                            y: band.lowerBound - 1,
                            width: right - left,
                            height: band.upperBound - band.lowerBound + 2
                        )
                    }
                )
            }
            let masks = DrawingPathTree(paintMembers.map(\.rects), colors: paintMembers.map(\.color))
            for (ordinal, selected) in selections {
                guard let color = foreground[ordinal] else { continue }
                // 同一个普通颜色批次在按下后可以分成不同有效颜色。
                // 按原成员次序绘制原完整路径；不能全局排除显式色区域，否则会抹掉其后继承色的覆盖。
                observe(.selectionPreparation)
                actionPlans[ordinal].strokes[index] = SourcePaintPlan(
                    members: paintMembers,
                    tree: masks,
                    selected: selected,
                    color: color,
                    groups: 0 ... 0,
                    observe: observe
                )
            }
        }
        actions = actionPlans
    }

    func drawBackgrounds(in context: CGContext, pressed: Int?) {
        let action = pressed.flatMap { actions.indices.contains($0) ? actions[$0] : nil }
        var index = 0
        while index < backgrounds.count {
            if let patch = action?.backgrounds[index] {
                let range = index ..< index + patch.consumed
                patch.plan.draw(in: context, ordinary: {
                    for original in range {
                        let layer = backgrounds[original]
                        if let color = layer.color {
                            context.setFillColor(color)
                            context.addPath(layer.ordinary.path)
                            context.fillPath()
                        }
                    }
                }, colored: { color in context.setFillColor(color)
                    context.fill(patch.plan.bounds)
                })
                index += patch.consumed
            } else {
                let layer = backgrounds[index]
                if let color = layer.color {
                    context.setFillColor(color)
                    context.addPath(layer.ordinary.path)
                    context.fillPath()
                }
                index += 1
            }
        }
    }

    /// - Parameter tokenColor: 非 nil 时截断 token 的 run 使用该颜色，表示 token 处于按下状态。
    func drawGlyphs(
        in context: CGContext,
        pressed: Int?,
        tokenColor: CGColor? = nil,
        observe: (TextDecorations.PreparationEvent) -> Void = { _ in }
    ) {
        let action = pressed.flatMap { actions.indices.contains($0) ? actions[$0] : nil }
        for (index, run) in runs.enumerated() {
            guard let operations = action?.runs[index] else {
                draw(
                    run.run,
                    range: CFRange(location: 0, length: 0),
                    baseline: run.baseline,
                    in: context,
                    color: run.isTruncationToken ? tokenColor ?? run.color : run.color,
                    shadow: run.shadow,
                    observe: observe
                )
                continue
            }
            for operation in operations {
                switch operation {
                case let .ordinary(range):
                    draw(
                        run.run, range: range, baseline: run.baseline, in: context, color: run.color,
                        shadow: run.shadow, observe: observe
                    )
                case let .selected(glyphIndex, selected):
                    let glyph = glyphs[glyphIndex]
                    context.saveGState()
                    // 两份互补 clip 的抗锯齿覆盖率必须先相加；直接 source-over 会在非整数边界使半透明字形变浅。
                    // 局部透明层只合成一次，同时保留调用方的混合和抗锯齿设置。
                    context.beginTransparencyLayer(in: glyph.layerBounds, auxiliaryInfo: nil)
                    draw(glyph, in: context, color: UIColor.white.cgColor, observe: observe)
                    context.saveGState()
                    context.setBlendMode(.sourceIn)
                    context.beginTransparencyLayer(in: glyph.layerBounds, auxiliaryInfo: nil)
                    context.setBlendMode(.plusLighter)
                    context.saveGState()
                    selected.clip.applyOutside(to: context)
                    context.setFillColor(glyph.color)
                    context.fill(glyph.layerBounds)
                    context.restoreGState()
                    context.saveGState()
                    selected.clip.applyInside(to: context)
                    context.setFillColor(selected.color)
                    context.fill(glyph.layerBounds)
                    context.restoreGState()
                    context.endTransparencyLayer()
                    context.restoreGState()
                    context.endTransparencyLayer()
                    context.restoreGState()
                }
            }
        }
    }

    private func draw(
        _ glyph: Glyph,
        in context: CGContext,
        color: CGColor,
        observe: (TextDecorations.PreparationEvent) -> Void
    ) {
        // 按下的局部着色通过透明层和遮罩合成；阴影会进入遮罩，因此这部分字形不绘制阴影。
        draw(
            glyph.run, range: glyph.range, baseline: glyph.baseline, in: context, color: color, shadow: nil,
            observe: observe
        )
    }

    private func draw(
        _ run: CTRun,
        range: CFRange,
        baseline: CGPoint,
        in context: CGContext,
        color: CGColor,
        shadow: ResolvedShadow?,
        observe: (TextDecorations.PreparationEvent) -> Void
    ) {
        context.saveGState()
        if let shadow {
            // 阴影偏移位于设备基准空间，不受文本翻转矩阵影响；UIKit 上下文中正 height 向下。
            context.setShadow(offset: shadow.offset, blur: shadow.blurRadius, color: shadow.color)
        }
        context.setFillColor(color)
        context.textMatrix = .identity
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: baseline.x, y: -baseline.y)
        observe(.glyphDrawCall)
        CTRunDraw(run, context, range)
        context.restoreGState()
    }

    func drawStrokes(
        in context: CGContext,
        pressed: Int?,
        observe: (TextDecorations.PreparationEvent) -> Void = { _ in }
    ) {
        let action = pressed.flatMap { actions.indices.contains($0) ? actions[$0] : nil }
        for (index, group) in strokes.enumerated() {
            if let plan = action?.strokes[index] {
                plan.draw(
                    in: context,
                    ordinary: { group.draw(in: context, scale: 1, observe: observe) },
                    colored: { group.draw(in: context, scale: 1, color: $0, observe: observe) }
                )
            } else { group.draw(in: context, scale: 1, observe: observe) }
        }
    }
}

/// 仅分区动作覆盖的局部区域。每区先完成真实源 stack，再对区域 coverage 合成一次。
/// 共享树查询保留全文外的原批次，避免 A 个不相交动作各自复制或分区 N 个全文成员。
struct SourcePaintPlan {
    struct Member {
        let color: CGColor?
        let group: Int
        let rects: [CGRect]
    }

    private struct ColorStack: Hashable {
        let colors: [CGColor]

        func hash(into hasher: inout Hasher) {
            for color in colors {
                hasher.combine(CFHash(color))
            }
        }
    }

    private struct Region {
        let path: CGPath
        let colors: [CGColor]
    }

    let bounds: CGRect
    private let outside: CGPath
    private let regions: [Region]

    init(
        members: [Member], tree: DrawingPathTree, selected: [Int], color: CGColor,
        groups: ClosedRange<Int>, observe: (TextDecorations.PreparationEvent) -> Void
    ) {
        let selected = Set(selected)
        let selectedBounds = selected.reduce(CGRect.null) { bounds, index in
            members[index].rects.reduce(bounds) { $0.union($1) }
        }
        bounds = tree.bounds
        outside = DrawingClip([selectedBounds], covering: bounds).outside
        let indices = tree.members(intersecting: selectedBounds, observe: observe)
            .filter { groups.contains(members[$0].group) }
        // 每个 batch 是原始源序列中的一个有效颜色段；nil 不切断批次。
        let orderedSelection = selected.sorted()
        func hasBarrier(_ range: Range<Int>, target: CGColor) -> Bool {
            guard !range.isEmpty else { return false }
            var lower = 0, upper = orderedSelection.count
            while lower < upper {
                observe(.barrierMemberVisit)
                let middle = lower + (upper - lower) / 2
                if orderedSelection[middle] < range.lowerBound { lower = middle + 1 }
                else { upper = middle }
            }
            var start = range.lowerBound
            while lower < orderedSelection.count, orderedSelection[lower] < range.upperBound {
                observe(.barrierMemberVisit)
                let index = orderedSelection[lower]
                if tree.containsDifferentColor(in: start ..< index, from: target) { return true }
                if color != target { return true }
                start = index + 1
                lower += 1
            }
            return tree.containsDifferentColor(in: start ..< range.upperBound, from: target)
        }
        var batchColors: [CGColor] = []
        var batchRects: [[CGRect]] = []
        var lastIndex: Int?
        for index in indices {
            guard let effective = selected.contains(index) ? color : members[index].color else { continue }
            let rects = members[index].rects.map { $0.intersection(selectedBounds) }
                .filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
            guard !rects.isEmpty else { continue }
            if let previous = lastIndex, batchColors.last == effective,
               !hasBarrier(previous + 1 ..< index, target: effective)
            {
                batchRects[batchRects.count - 1].append(contentsOf: rects)
            } else {
                batchColors.append(effective)
                batchRects.append(rects)
            }
            lastIndex = index
        }
        // 事件只在矩形边界更新，slab 内只扫描真实活跃集合；单长动作不重复扫描全文矩形。
        struct RectEntry {
            let batch: Int
            let rect: CGRect
        }
        struct XEvent {
            let x: CGFloat
            let id: Int
            let enters: Bool
        }
        struct YEvent {
            let y: CGFloat
            let batch: Int
            let delta: Int
        }
        let entries = batchRects.enumerated()
            .flatMap { batch, rects in rects.map { RectEntry(batch: batch, rect: $0) } }
        let events = entries.enumerated().flatMap { id, entry in
            [XEvent(x: entry.rect.minX, id: id, enters: true), XEvent(x: entry.rect.maxX, id: id, enters: false)]
        }.sorted { $0.x < $1.x }
        var active: Set<Int> = []
        var cursor = 0
        var paths: [ColorStack: CGMutablePath] = [:]
        var stacks: [ColorStack] = []
        while cursor < events.count {
            let left = events[cursor].x
            while cursor < events.count, events[cursor].x == left {
                observe(.activeRectCheck)
                let event = events[cursor]
                if event.enters { active.insert(event.id) }
                else { active.remove(event.id) }
                cursor += 1
            }
            guard cursor < events.count, !active.isEmpty else { continue }
            let right = events[cursor].x
            let vertical = active.flatMap { id -> [YEvent] in
                observe(.activeRectCheck)
                let entry = entries[id]
                return [
                    YEvent(y: entry.rect.minY, batch: entry.batch, delta: 1),
                    YEvent(y: entry.rect.maxY, batch: entry.batch, delta: -1)
                ]
            }.sorted { $0.y < $1.y }
            var counts: [Int: Int] = [:]
            var next = 0
            while next < vertical.count {
                let top = vertical[next].y
                while next < vertical.count, vertical[next].y == top {
                    observe(.activeRectCheck)
                    let event = vertical[next]
                    counts[event.batch, default: 0] += event.delta
                    if counts[event.batch] == 0 { counts.removeValue(forKey: event.batch) }
                    next += 1
                }
                guard next < vertical.count, !counts.isEmpty else { continue }
                observe(.paintRegion)
                let stack = ColorStack(colors: counts.keys.sorted().map { batchColors[$0] })
                let path: CGMutablePath
                if let existing = paths[stack] { path = existing }
                else {
                    path = CGMutablePath()
                    paths[stack] = path
                    stacks.append(stack)
                }
                path.addRect(CGRect(x: left, y: top, width: right - left, height: vertical[next].y - top))
            }
        }
        // 同一颜色 stack 的区域互不重叠，可共用一次原完整路径绘制；不按每个字符重绘所有 byWord intervals。
        let prepared = stacks.compactMap { stack in paths[stack].map { Region(path: $0, colors: stack.colors) } }

        regions = prepared
    }

    func draw(in context: CGContext, ordinary: () -> Void, colored: (CGColor) -> Void) {
        context.saveGState()
        context.beginTransparencyLayer(in: bounds, auxiliaryInfo: nil)
        context.setBlendMode(.plusLighter)
        func drawRegion(_ path: CGPath, content: () -> Void) {
            context.saveGState()
            context.addPath(path)
            context.clip(using: .evenOdd)
            // clip 必须作用于完成后的源 stack，不能重复调制 stack 内每次 source-over 的 alpha。
            context.beginTransparencyLayer(in: bounds, auxiliaryInfo: nil)
            context.resetClip()
            context.setBlendMode(.normal)
            content()
            context.endTransparencyLayer()
            context.restoreGState()
        }
        drawRegion(outside, content: ordinary)
        for region in regions {
            drawRegion(region.path) {
                for color in region.colors {
                    colored(color)
                }
            }
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }
}

/// 所有动作共享源空间与颜色摘要树；查询只构造动作覆盖的局部区域，不复制全文装饰。
final class DrawingPathTree {
    let path: CGPath
    let bounds: CGRect
    private let range: Range<Int>
    private let left: DrawingPathTree?
    private let right: DrawingPathTree?
    private let rects: [CGRect]
    private let color: CGColor?
    private let hasMixedColors: Bool

    convenience init(_ rects: [[CGRect]], colors: [CGColor?]? = nil) {
        self.init(rects, colors: colors, range: 0 ..< rects.count)
    }

    private init(_ rects: [[CGRect]], colors: [CGColor?]?, range: Range<Int>) {
        self.range = range
        let path = CGMutablePath()
        if range.count > 1 {
            let middle = range.lowerBound + range.count / 2
            let left = DrawingPathTree(rects, colors: colors, range: range.lowerBound ..< middle)
            let right = DrawingPathTree(rects, colors: colors, range: middle ..< range.upperBound)
            self.left = left
            self.right = right
            self.rects = []
            color = left.color ?? right.color
            hasMixedColors = left.hasMixedColors || right.hasMixedColors
                || (left.color != nil && right.color != nil && left.color != right.color)
            path.addPath(left.path)
            path.addPath(right.path)
        } else {
            left = nil
            right = nil
            self.rects = range.first.map { rects[$0] } ?? []
            color = range.first.flatMap { colors?[$0] }
            hasMixedColors = false
            path.addRects(self.rects)
        }
        self.path = path
        bounds = path.boundingBoxOfPath
    }

    /// 通过共享边界树仅访问当前动作覆盖区；不为每个动作扫描全文成员。
    func members(intersecting rect: CGRect, observe: (TextDecorations.PreparationEvent) -> Void) -> [Int] {
        observe(.paintMemberQuery)
        let overlap = bounds.intersection(rect)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return [] }
        if let left, let right {
            return left.members(intersecting: rect, observe: observe) + right.members(
                intersecting: rect,
                observe: observe
            )
        }
        return rects.contains { value in
            let overlap = value.intersection(rect)
            return !overlap.isNull && overlap.width > 0 && overlap.height > 0
        } ? Array(range) : []
    }

    /// nil 不是颜色 barrier；混色节点才继续下探，保留远处异色源造成的原批次顺序。
    func containsDifferentColor(in selection: Range<Int>, from target: CGColor) -> Bool {
        guard range.overlaps(selection), let color else { return false }
        if !hasMixedColors, selection.lowerBound <= range.lowerBound, selection.upperBound >= range.upperBound {
            return color != target
        }
        return (left?.containsDifferentColor(in: selection, from: target) ?? false)
            || (right?.containsDifferentColor(in: selection, from: target) ?? false)
    }
}

/// 先对矩形求真正的 union，再建立互斥的 inside/complement，重叠部分不会变成 even-odd 洞。
struct DrawingClip {
    let inside: CGPath
    let outside: CGPath

    init(_ rects: [CGRect], excluding exclusions: [CGRect] = [], covering inkBounds: CGRect = .null) {
        let path = CGMutablePath()
        // 横向 slab 内的竖向区间合并，得到无重叠矩形；在准备阶段执行。
        let xs = Set((rects + exclusions).flatMap { [$0.minX, $0.maxX] }).sorted()
        for (left, right) in zip(xs, xs.dropFirst()) where right > left {
            let intervals = rects.filter { $0.minX < right && $0.maxX > left }.map { $0.minY ... $0.maxY }
                .sorted { $0.lowerBound < $1.lowerBound }
            var merged: [ClosedRange<CGFloat>] = []
            for interval in intervals {
                if let previous = merged.last, interval.lowerBound <= previous.upperBound {
                    merged[merged.count - 1] = previous.lowerBound ... max(previous.upperBound, interval.upperBound)
                } else { merged.append(interval) }
            }
            for interval in merged {
                var remaining = [interval]
                let blocked = exclusions.filter { $0.minX < right && $0.maxX > left }
                    .map { $0.minY ... $0.maxY }
                for block in blocked {
                    remaining = remaining.flatMap { value in
                        var pieces: [ClosedRange<CGFloat>] = []
                        if value.lowerBound < block.lowerBound { pieces.append(value.lowerBound ... min(
                            value.upperBound,
                            block.lowerBound
                        )) }
                        if value.upperBound > block
                            .upperBound { pieces.append(max(value.lowerBound, block.upperBound) ... value.upperBound) }
                        return pieces.filter { $0.upperBound > $0.lowerBound }
                    }
                }
                for value in remaining {
                    path.addRect(CGRect(
                        x: left,
                        y: value.lowerBound,
                        width: right - left,
                        height: value.upperBound - value.lowerBound
                    ))
                }
            }
        }
        inside = path
        let complement = CGMutablePath()
        // 补集仅需覆盖当前实际 glyph ink；不引入比公开输入更窄的硬编码坐标上限。
        let coverage = rects.reduce(inkBounds) { $0.union($1) }.insetBy(dx: -1, dy: -1)
        if !coverage.isNull { complement.addRect(coverage) }
        complement.addPath(path)
        outside = complement
    }

    func applyInside(to context: CGContext) {
        context.addPath(inside)
        context.clip()
    }

    func applyOutside(to context: CGContext) {
        context.addPath(outside)
        context.clip(using: .evenOdd)
    }
}

private struct RectKey: Hashable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    init(_ rect: CGRect) {
        x = rect.minX
        y = rect.minY
        width = rect.width
        height = rect.height
    }
}
