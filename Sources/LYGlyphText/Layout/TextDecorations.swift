import CoreText
import UIKit

/// 已解析颜色的源样式，不写入 Core Text 属性，避免背景／删除线切断 shaping。
struct TextDecorations {
    enum PreparationEvent: Hashable {
        case drawCachedContent
        case drawingPlan
        case glyphPaintRecord
        case glyphImageBoundsQuery
        case glyphDrawCall
        case selectionPreparation
        case paintMemberQuery
        case paintRegion
        case barrierMemberVisit
        case activeRectCheck
        case strokeIntervalDraw
        case sourceSnapshot
        case geometryQuery
        case visiblePiece
        case styleComparison
        case groupComparison
    }

    struct Style {
        let range: NSRange
        let background: CGColor?
        let underlineStyle: Int
        let underlineColor: CGColor
        let strikethroughStyle: Int
        let strikethroughColor: CGColor
        var underlineColorIsInherited = false
        var strikethroughColorIsInherited = false
    }

    let source: String
    let styles: [Style]
    let scale: CGFloat

    /// 原生像素探针确认 byWord 被忽略，pattern 长度也不遵循字体 underline thickness 单位。
    /// shaping 属性保留原生 solid 值；最终普通和按压下划线统一消费缓存路径。
    static func needsUnderlineFallback(_ style: Int) -> Bool {
        style & NSUnderlineStyle.byWord.rawValue != 0 || style & 0xF00 != 0
    }

    /// 兼容独立装饰测试的准备入口；生产 Layout 在构造时直接传入已缓存的片段。
    func prepare(
        in layout: LYGlyphTextLayout, observe: (PreparationEvent) -> Void = { _ in }
    ) -> Prepared {
        prepare(fragments: layout.visibleTextFragments(
            in: NSRange(location: 0, length: source.utf16.count), source: source
        ), observe: observe)
    }

    func prepare(
        fragments: [VisibleTextFragment], observe: (PreparationEvent) -> Void = { _ in }
    ) -> Prepared {
        guard styles.contains(where: {
            $0.background != nil || $0.strikethroughStyle & 0xF != 0 || $0.underlineStyle & 0xF != 0
        }) else { return Prepared(
            fills: [],
            groups: [],
            nativeUnderlineGroups: [],
            strokes: [],
            allGroups: [],
            scale: scale
        ) }
        observe(.geometryQuery)
        var selected: [Int: [LocatedPiece]] = [:]
        for fragment in fragments {
            for piece in fragment.runs {
                observe(.visiblePiece)
                // 样式在快照内按源范围排序且互不重叠；完整 cluster 可同时关联多个样式。
                var lower = 0
                var upper = styles.count
                while lower < upper {
                    let middle = lower + (upper - lower) / 2
                    observe(.styleComparison)
                    if NSMaxRange(styles[middle].range) <= piece.sourceRange.location { lower = middle + 1 }
                    else { upper = middle }
                }
                while lower < styles.count {
                    observe(.styleComparison)
                    guard styles[lower].range.location < NSMaxRange(piece.sourceRange) else { break }
                    selected[lower, default: []].append(.init(line: fragment.lineIndex, piece: piece))
                    lower += 1
                }
            }
        }
        let string = source as NSString
        var fills: [Fill] = []
        var primitives: [Stroke] = []
        var underlines: [Int: LineGroups] = [:]
        var strikes: [Int: LineGroups] = [:]
        var nativeUnderlines: [Int: LineGroups] = [:]
        var allUnderlines: [Int: LineGroups] = [:]
        for index in selected.keys.sorted() {
            guard let pieces = selected[index] else { continue }
            let style = styles[index]
            if let color = style.background {
                let rects = pieces.map(\.piece.rect)
                let members = pieces.map { Member(styleIndex: index, piece: $0.piece) }
                if let last = fills.last, last.color == color {
                    fills[fills.count - 1].rects.append(contentsOf: rects)
                    fills[fills.count - 1].members.append(contentsOf: members)
                } else { fills.append(.init(color: color, rects: rects, members: members)) }
            }
            let underline = Self.needsUnderlineFallback(style.underlineStyle) && style.underlineStyle & 0xF != 0
            guard style.underlineStyle & 0xF != 0 || style.strikethroughStyle & 0xF != 0 else { continue }
            for located in pieces {
                let piece = located.piece
                let whitespace = string.substring(with: piece.sourceRange).unicodeScalars.allSatisfy {
                    CharacterSet.whitespacesAndNewlines.contains($0)
                }
                let unit = max(CTFontGetUnderlineThickness(piece.font), 1 / scale)
                if style.underlineStyle & 0xF != 0,
                   style.underlineStyle & NSUnderlineStyle.byWord.rawValue == 0 || !whitespace
                {
                    let stroke = Stroke(
                        line: located.line, rect: piece.rect,
                        center: piece.baseline.y - CTFontGetUnderlinePosition(piece.font), unit: unit,
                        style: style.underlineStyle, color: style.underlineColor,
                        kind: .underline, colorIsInherited: style.underlineColorIsInherited,
                        member: .init(styleIndex: index, piece: piece)
                    )
                    primitives.append(stroke)
                    allUnderlines[located.line, default: LineGroups()].append(stroke, scale: scale, observe: observe)
                    if underline {
                        underlines[located.line, default: LineGroups()].append(stroke, scale: scale, observe: observe)
                    } else {
                        nativeUnderlines[located.line, default: LineGroups()].append(
                            stroke,
                            scale: scale,
                            observe: observe
                        )
                    }
                }
                if style.strikethroughStyle & 0xF != 0,
                   style.strikethroughStyle & NSUnderlineStyle.byWord.rawValue == 0 || !whitespace
                {
                    let stroke = Stroke(
                        line: located.line, rect: piece.rect,
                        center: piece.baseline.y - CTFontGetXHeight(piece.font) / 2, unit: unit,
                        style: style.strikethroughStyle, color: style.strikethroughColor,
                        kind: .strikethrough, colorIsInherited: style.strikethroughColorIsInherited,
                        member: .init(styleIndex: index, piece: piece)
                    )
                    primitives.append(stroke)
                    strikes[located.line, default: LineGroups()].append(stroke, scale: scale, observe: observe)
                }
            }
        }
        // 两类线分别准备，避免 underline/strike 交织使连续样式的 dash 在每字重置。
        let groups = underlines.keys.sorted().flatMap { underlines[$0]?.groups ?? [] }
            + strikes.keys.sorted().flatMap { strikes[$0]?.groups ?? [] }
        let nativeGroups = nativeUnderlines.keys.sorted().flatMap { nativeUnderlines[$0]?.groups ?? [] }
        return Prepared(
            fills: fills,
            groups: groups.map { $0.finalized(scale: scale) },
            nativeUnderlineGroups: nativeGroups.map { $0.finalized(scale: scale) },
            strokes: primitives,
            allGroups: (allUnderlines.keys.sorted().flatMap { allUnderlines[$0]?.groups ?? [] }
                + strikes.keys.sorted().flatMap { strikes[$0]?.groups ?? [] }).map { $0.finalized(scale: scale) },
            scale: scale
        )
    }

    struct Prepared {
        let fills: [Fill]
        let groups: [StrokeGroup]
        /// 原生 solid underline 的独立归属快照；最终绘制消费包含它们的 allGroups。
        let nativeUnderlineGroups: [StrokeGroup]
        let strokes: [Stroke]
        let allGroups: [StrokeGroup]
        fileprivate let scale: CGFloat

        func drawBackgrounds(in context: CGContext) {
            context.saveGState()
            for fill in fills {
                context.setFillColor(fill.color)
                // 相邻同色完整 cluster 一次填充只合成一次 alpha，且不跨其他颜色重排。
                context.beginPath()
                context.addRects(fill.rects)
                context.fillPath()
            }
            context.restoreGState()
        }

        func drawLines(in context: CGContext) {
            context.saveGState()
            for group in groups {
                group.draw(in: context, scale: scale)
            }
            context.restoreGState()
        }
    }

    private struct LocatedPiece {
        let line: Int
        let piece: VisibleTextFragment.RunPiece
    }

    struct Member {
        let styleIndex: Int
        let piece: VisibleTextFragment.RunPiece
    }

    struct Fill {
        let color: CGColor
        var rects: [CGRect]
        var members: [Member]
    }

    private struct StrokeKey: Hashable {
        let center: CGFloat
        let unit: CGFloat
        let style: Int
        let color: CGColor

        init(_ stroke: Stroke) {
            center = stroke.center
            unit = stroke.unit
            style = stroke.style
            color = stroke.color
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(center)
            hasher.combine(unit)
            hasher.combine(style)
            hasher.combine(CFHash(color))
        }
    }

    private struct LineGroups {
        var groups: [StrokeGroup] = []
        private var active: [StrokeKey: Int] = [:]
        private var intervals: StrokeIntervalNode?

        mutating func append(_ stroke: Stroke, scale: CGFloat, observe: (PreparationEvent) -> Void) {
            guard stroke.interval.upperBound > stroke.interval.lowerBound else { return }
            let key = StrokeKey(stroke)
            // 按真实水平区间和绘制时的线宽／像素基线查询，覆盖不同 cluster 的合法重叠。
            // 新片段只能并入晚于实际重叠异色批次的同色批次，避免向旧批次扩展时倒置合成顺序。
            var barrier = -1
            intervals?.overlapping(stroke, scale: scale, observe: observe) { previous, index in
                if StrokeKey(previous) != key { barrier = max(barrier, index) }
            }
            observe(.groupComparison)
            let index: Int
            if let existing = active[key], existing >= barrier {
                groups[existing].intervals.append(stroke.interval)
                groups[existing].members.append(stroke)
                index = existing
            } else {
                index = groups.count
                groups.append(StrokeGroup(stroke))
                active[key] = index
            }
            intervals = StrokeIntervalNode.inserting(stroke, index: index, into: intervals)
        }
    }

    /// 按行维护的 AVL 区间索引；同几何仅保留最近批次，查询为 O(log n + 实际重叠候选)。
    private final class StrokeIntervalNode {
        var stroke: Stroke
        var index: Int
        var left: StrokeIntervalNode?
        var right: StrokeIntervalNode?
        var height = 1
        var maximumX: CGFloat

        init(_ stroke: Stroke, index: Int) {
            self.stroke = stroke
            self.index = index
            maximumX = stroke.interval.upperBound
        }

        func overlapping(
            _ target: Stroke, scale: CGFloat, observe: (PreparationEvent) -> Void,
            visit: (Stroke, Int) -> Void
        ) {
            observe(.groupComparison)
            if let left, left.maximumX > target.interval.lowerBound {
                left.overlapping(target, scale: scale, observe: observe, visit: visit)
            }
            if stroke.interval.lowerBound < target.interval.upperBound,
               stroke.interval.upperBound > target.interval.lowerBound,
               stroke.verticalIntervals(scale: scale).contains(where: { first in
                   target.verticalIntervals(scale: scale).contains { second in
                       first.lowerBound < second.upperBound && first.upperBound > second.lowerBound
                   }
               }) { visit(stroke, index) }
            if stroke.interval.lowerBound < target.interval.upperBound {
                right?.overlapping(target, scale: scale, observe: observe, visit: visit)
            }
        }

        static func inserting(_ stroke: Stroke, index: Int, into root: StrokeIntervalNode?) -> StrokeIntervalNode {
            guard let root else { return StrokeIntervalNode(stroke, index: index) }
            let order = compare(stroke, root.stroke)
            if order == 0 { root.stroke = stroke
                root.index = index
                return root
            }
            if order < 0 { root.left = inserting(stroke, index: index, into: root.left) }
            else { root.right = inserting(stroke, index: index, into: root.right) }
            root.update()
            let balance = (root.left?.height ?? 0) - (root.right?.height ?? 0)
            if balance > 1, let left = root.left {
                if (left.left?.height ?? 0) < (left.right?.height ?? 0) { root.left = rotateLeft(left) }
                return rotateRight(root)
            }
            if balance < -1, let right = root.right {
                if (right.right?.height ?? 0) < (right.left?.height ?? 0) { root.right = rotateRight(right) }
                return rotateLeft(root)
            }
            return root
        }

        private static func compare(_ first: Stroke, _ second: Stroke) -> Int {
            let firstValues = [
                first.interval.lowerBound,
                first.interval.upperBound,
                first.center,
                first.unit,
                CGFloat(first.style & 0xF)
            ]
            let secondValues = [
                second.interval.lowerBound,
                second.interval.upperBound,
                second.center,
                second.unit,
                CGFloat(second.style & 0xF)
            ]
            for (a, b) in zip(firstValues, secondValues) where a != b {
                return a < b ? -1 : 1
            }
            return 0
        }

        private func update() {
            height = max(left?.height ?? 0, right?.height ?? 0) + 1
            maximumX = max(
                stroke.interval.upperBound,
                left?.maximumX ?? stroke.interval.upperBound,
                right?.maximumX ?? stroke.interval.upperBound
            )
        }

        private static func rotateLeft(_ root: StrokeIntervalNode) -> StrokeIntervalNode {
            guard let pivot = root.right else { return root }
            root.right = pivot.left
            pivot.left = root
            root.update()
            pivot.update()
            return pivot
        }

        private static func rotateRight(_ root: StrokeIntervalNode) -> StrokeIntervalNode {
            guard let pivot = root.left else { return root }
            root.left = pivot.right
            pivot.right = root
            root.update()
            pivot.update()
            return pivot
        }
    }

    struct Stroke {
        enum Kind { case underline, strikethrough }
        let kind: Kind
        let colorIsInherited: Bool
        let member: Member
        let line: Int
        let interval: ClosedRange<CGFloat>
        let center: CGFloat
        let unit: CGFloat
        let style: Int
        let color: CGColor

        init(
            line: Int, rect: CGRect, center: CGFloat, unit: CGFloat, style: Int, color: CGColor,
            kind: Kind, colorIsInherited: Bool, member: Member
        ) {
            self.kind = kind
            self.colorIsInherited = colorIsInherited
            self.member = member
            self.line = line
            interval = rect.minX ... rect.maxX
            self.center = center
            self.unit = unit
            self.style = style
            self.color = color
        }

        var width: CGFloat {
            style & 0xF == NSUnderlineStyle.thick.rawValue ? unit * 2 : unit
        }

        func verticalIntervals(scale: CGFloat) -> [ClosedRange<CGFloat>] {
            let centers = style & 0xF == NSUnderlineStyle.double.rawValue ? [center - unit, center + unit] : [center]
            return centers.map { center in
                let top = ((center - width / 2) * scale).rounded() / scale
                return top ... (top + width)
            }
        }
    }

    struct StrokeGroup {
        let stroke: Stroke
        var intervals: [ClosedRange<CGFloat>]
        var members: [Stroke]
        private(set) var mergedIntervals: [ClosedRange<CGFloat>] = []
        private var centers: [CGFloat] = []
        private var dashLengths: [CGFloat] = []

        init(_ stroke: Stroke) {
            self.stroke = stroke
            intervals = [stroke.interval]
            members = [stroke]
        }

        func finalized(scale: CGFloat) -> Self {
            var merged: [ClosedRange<CGFloat>] = []
            for interval in intervals.sorted(by: { $0.lowerBound < $1.lowerBound }) {
                if let last = merged.last, interval.lowerBound <= last.upperBound + 0.000001 {
                    merged[merged.count - 1] = last.lowerBound ... max(last.upperBound, interval.upperBound)
                } else {
                    merged.append(interval)
                }
            }
            var result = self
            result.mergedIntervals = merged
            let unit = stroke.unit
            let centers = stroke.verticalIntervals(scale: scale).map { ($0.lowerBound + $0.upperBound) / 2 }
            let pattern: [CGFloat] = switch stroke.style & 0xF00 {
            case NSUnderlineStyle.patternDot.rawValue: [1, 2]
            case NSUnderlineStyle.patternDash.rawValue: [4, 2]
            case NSUnderlineStyle.patternDashDot.rawValue: [4, 2, 1, 2]
            case NSUnderlineStyle.patternDashDotDot.rawValue: [4, 2, 1, 2, 1, 2]
            default: []
            }
            result.centers = centers
            result.dashLengths = pattern.map { $0 * unit }
            return result
        }

        func draw(
            in context: CGContext,
            scale _: CGFloat,
            color: CGColor? = nil,
            observe: (PreparationEvent) -> Void = { _ in }
        ) {
            context.setStrokeColor(color ?? stroke.color)
            context.setLineWidth(stroke.width)
            context.setLineCap(.butt)
            context.setLineDash(phase: 0, lengths: dashLengths)
            for interval in mergedIntervals {
                for center in centers {
                    // 仅对绘制边缘做像素对齐，源矩形和 CTLine 均不改写。
                    let y = center
                    context.beginPath()
                    context.move(to: CGPoint(x: interval.lowerBound, y: y))
                    context.addLine(to: CGPoint(x: interval.upperBound, y: y))
                    observe(.strokeIntervalDraw)
                    context.strokePath()
                }
            }
        }
    }
}
