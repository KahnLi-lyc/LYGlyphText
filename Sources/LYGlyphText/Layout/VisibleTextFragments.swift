import CoreText
import UIKit

/// 原文查询的视觉片段；坐标属于 Layout，不包含展示层裁切和偏移。
@MainActor
struct VisibleTextFragment {
    struct RunPiece {
        let sourceRange: NSRange
        /// 最终 CTLine／CTRun 的局部 UTF-16 范围，尚未加 sourceOffset。
        let lineRange: NSRange
        let runRange: NSRange
        let font: CTFont
        /// 已包含最终 glyph position 的基线偏移，UIKit 坐标向下。
        let baseline: CGPoint
        let glyphBaselines: [CGPoint]
        let rect: CGRect
    }

    let sourceRange: NSRange
    let lineIndex: Int
    let rect: CGRect
    let runs: [RunPiece]
}

extension LYGlyphTextLayout {
    func visibleTextFragments(in range: NSRange, source: String) -> [VisibleTextFragment] {
        let string = source as NSString
        guard GeometryRange.end(range).map({ $0 <= string.length }) == true, range.length > 0 else { return [] }
        let clusters = SourceClusterIndex(source: string)
        let selectedClusters = clusters.overlapping(range)
        guard let first = selectedClusters.first, let last = selectedClusters.last else { return [] }
        let selectedRange = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        let placements = Dictionary(
            (attachments.map { ($0.sourceLocation, $0.rect) }
                + viewAttachments.map { ($0.sourceLocation, $0.rect) }),
            uniquingKeysWith: { first, _ in first }
        )
        return lines.enumerated().flatMap { lineIndex, line in
            guard line.baseline.x.isFinite, line.baseline.y.isFinite else { return [VisibleTextFragment]() }
            let visible = Set(line.visibleSourceRanges.flatMap { sourceRange -> [NSRange] in
                guard let intersection = GeometryRange.intersection(sourceRange, selectedRange) else { return [] }
                return clusters.overlapping(intersection).filter { GeometryRange.contains(sourceRange, $0) }
            })
            guard !visible.isEmpty else { return [] }
            let pieces = (CTLineGetGlyphRuns(line.text) as! [CTRun]).flatMap { run in
                VisibleRunGeometry(
                    run: run, line: line, sourceLength: string.length, clusters: clusters
                ).pieces(selected: visible, selectedRange: selectedRange, placements: placements)
            }
            return VisibleRunGeometry.merge(pieces, lineIndex: lineIndex)
        }
    }
}

/// 所有范围先验证整数运算，再交给 Foundation；不让畸形内部映射触发溢出。
private enum GeometryRange {
    static func end(_ range: NSRange) -> Int? {
        guard range.location >= 0, range.length >= 0, range.location != NSNotFound else { return nil }
        let result = range.location.addingReportingOverflow(range.length)
        return result.overflow ? nil : result.partialValue
    }

    static func intersects(_ first: NSRange, _ second: NSRange) -> Bool {
        guard let a = end(first), let b = end(second) else { return false }
        return first.location < b && second.location < a
    }

    static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        guard let a = end(outer), let b = end(inner) else { return false }
        return outer.location <= inner.location && b <= a
    }

    static func intersection(_ first: NSRange, _ second: NSRange) -> NSRange? {
        guard let a = end(first), let b = end(second) else { return nil }
        let start = max(first.location, second.location)
        let end = min(a, b)
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    static func shifted(_ index: Int, by offset: Int) -> Int? {
        let result = index.addingReportingOverflow(offset)
        return result.overflow ? nil : result.partialValue
    }
}

@MainActor
private struct VisibleRunGeometry {
    let run: CTRun
    let line: LYGlyphTextLayout.Line
    let sourceLength: Int
    let clusters: SourceClusterIndex

    func pieces(
        selected: Set<NSRange>, selectedRange: NSRange, placements: [Int: CGRect]
    ) -> [VisibleTextFragment.RunPiece] {
        let count = CTRunGetGlyphCount(run)
        let range = CTRunGetStringRange(run)
        guard count > 0,
              let runEnd = GeometryRange.end(NSRange(location: range.location, length: range.length)),
              let originalStart = GeometryRange.shifted(range.location, by: line.sourceOffset),
              let originalEnd = GeometryRange.shifted(runEnd, by: line.sourceOffset),
              originalStart >= 0, originalEnd >= originalStart,
              GeometryRange.intersects(
                  NSRange(location: originalStart, length: originalEnd - originalStart), selectedRange
              )
        else { return [] }
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let fontValue = attributes[kCTFontAttributeName] else { return [] }
        let font = fontValue as! CTFont
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        guard ascent.isFinite, descent.isFinite, ascent + descent > 0 else { return [] }
        var indices = [CFIndex](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        var advances = [CGSize](repeating: .zero, count: count)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
        CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
        CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
        // 字形数与字符数没有对应关系；重复索引属于同一 shaping group。
        let starts = Set(indices.filter { $0 >= range.location && $0 < runEnd }).sorted()
        let groups = Dictionary(grouping: indices.indices, by: { indices[$0] })
        let rtl = CTRunGetStatus(run).contains(.rightToLeft)
        let runRange = NSRange(location: range.location, length: range.length)
        let finalLineRange = CTLineGetStringRange(line.text)
        let lineRange = NSRange(location: finalLineRange.location, length: finalLineRange.length)
        var result: [VisibleTextFragment.RunPiece] = []
        for (offset, start) in starts.enumerated() {
            guard !(line.truncationTokenRange
                .map { GeometryRange.contains($0, NSRange(location: start, length: 1)) } ?? false),
                let original = GeometryRange.shifted(start, by: line.sourceOffset),
                let end = GeometryRange.shifted(
                    offset + 1 < starts.count ? starts[offset + 1] : runEnd,
                    by: line.sourceOffset
                ),
                original >= 0, original < sourceLength, end > original,
                let members = groups[start]
            else { continue }
            let covered = NSRange(location: original, length: min(end, sourceLength) - original)
            guard GeometryRange.intersects(covered, selectedRange) else { continue }
            let candidates = clusters.overlapping(covered)
            guard candidates.contains(where: { selected.contains($0) }) else { continue }
            // caret 分区仍使用 glyph 覆盖的全部 cluster，不能只保留此次选中的字符。
            let groupClusters = candidates.filter { !isZeroAdvanceControl($0) }
            guard !groupClusters.isEmpty else { continue }
            let valid = members.filter {
                positions[$0].x.isFinite && positions[$0].y.isFinite && advances[$0].width.isFinite
            }
            guard valid.count == members.count, let first = valid.first else { continue }
            let lower = valid.map { min(positions[$0].x, positions[$0].x + advances[$0].width) }.min() ?? 0
            let upper = valid.map { max(positions[$0].x, positions[$0].x + advances[$0].width) }.max() ?? 0
            guard lower.isFinite, upper.isFinite else { continue }
            let boundaries = caretBoundaries(
                clusters: groupClusters, lower: lower, upper: upper, rtl: rtl, font: font,
                glyph: valid.count == 1 ? glyphs[first] : nil
            )
            for (index, cluster) in groupClusters.enumerated() where selected.contains(cluster) {
                // 硬分隔符、软分隔符与末尾 sentinel 永远不产生源矩形。
                let baseline = CGPoint(x: line.baseline.x + positions[first].x, y: line.baseline.y - positions[first].y)
                let rect: CGRect
                if clusters.isObjectReplacement(cluster) {
                    guard let placement = placements[cluster.location] else { continue }
                    rect = placement
                } else {
                    let x1 = line.baseline.x + boundaries[index]
                    let x2 = line.baseline.x + boundaries[index + 1]
                    let top = valid.map { line.baseline.y - positions[$0].y - ascent }.min() ?? 0
                    let bottom = valid.map { line.baseline.y - positions[$0].y + descent }.max() ?? 0
                    rect = CGRect(x: min(x1, x2), y: top, width: abs(x2 - x1), height: bottom - top)
                }
                guard Self.isFinite(rect), baseline.x.isFinite, baseline.y.isFinite else { continue }
                let glyphBaselines = valid.map {
                    CGPoint(x: line.baseline.x + positions[$0].x, y: line.baseline.y - positions[$0].y)
                }
                guard glyphBaselines.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { continue }
                result.append(.init(
                    sourceRange: cluster, lineRange: lineRange, runRange: runRange, font: font,
                    baseline: baseline, glyphBaselines: glyphBaselines, rect: rect
                ))
            }
        }
        return result
    }

    private func isZeroAdvanceControl(_ cluster: NSRange) -> Bool {
        if clusters.isSeparator(cluster) { return true }
        guard clusters.isDefaultIgnorable(cluster) else { return false }
        let start = cluster.location.subtractingReportingOverflow(line.sourceOffset)
        let end = NSMaxRange(cluster).subtractingReportingOverflow(line.sourceOffset)
        guard !start.overflow, !end.overflow else { return true }
        var secondaryStart: CGFloat = 0
        var secondaryEnd: CGFloat = 0
        let primaryStart = CTLineGetOffsetForStringIndex(line.text, start.partialValue, &secondaryStart)
        let primaryEnd = CTLineGetOffsetForStringIndex(line.text, end.partialValue, &secondaryEnd)
        // shaping 可能完全省去控制字符的 glyph；不能把它误认为连字中的一个可见 grapheme。
        return primaryStart == primaryEnd && secondaryStart == secondaryEnd
    }

    private func caretBoundaries(
        clusters: [NSRange], lower: CGFloat, upper: CGFloat, rtl: Bool, font: CTFont, glyph: CGGlyph?
    ) -> [CGFloat] {
        let fallback = LigatureCells.boundaries(minX: lower, maxX: upper, count: clusters.count, rightToLeft: rtl)
        guard clusters.count > 1, upper > lower else { return fallback }
        // 双向交界可能有 primary/secondary 两个位置；只接受当前实际 glyph advance 内的 caret。
        var native = [rtl ? upper : lower]
        for cluster in clusters.dropFirst() {
            let local = cluster.location.subtractingReportingOverflow(line.sourceOffset)
            guard !local.overflow else { return fallback }
            var secondary: CGFloat = 0
            let primary = CTLineGetOffsetForStringIndex(line.text, local.partialValue, &secondary)
            let target = fallback[native.count]
            let candidates = [primary, secondary].filter { $0.isFinite && $0 > lower && $0 < upper }
            guard let caret = candidates.min(by: { abs($0 - target) < abs($1 - target) }),
                  let previous = native.last, rtl ? caret < previous : caret > previous
            else { return fontCarets(font, glyph: glyph, fallback: fallback, lower: lower, upper: upper, rtl: rtl) }
            native.append(caret)
        }
        native.append(rtl ? lower : upper)
        return native
    }

    private func fontCarets(
        _ font: CTFont, glyph: CGGlyph?, fallback: [CGFloat], lower: CGFloat, upper: CGFloat, rtl: Bool
    ) -> [CGFloat] {
        guard let glyph else { return fallback }
        let count = fallback.count - 2
        var carets = [CGFloat](repeating: 0, count: count)
        let available = CTFontGetLigatureCaretPositions(font, glyph, &carets, count)
        guard available == count else { return fallback }
        let interior = carets.map { lower + $0 }.sorted()
        guard interior.allSatisfy({ $0.isFinite && $0 > lower && $0 < upper }),
              zip(interior, interior.dropFirst()).allSatisfy({ $0 < $1 }) else { return fallback }
        let ascending = [lower] + interior + [upper]
        return rtl ? Array(ascending.reversed()) : ascending
    }

    static func isFinite(_ rect: CGRect) -> Bool {
        rect.minX.isFinite && rect.maxX.isFinite && rect.minY.isFinite && rect.maxY.isFinite
            && rect.width >= 0 && rect.height > 0
    }

    static func merge(_ pieces: [VisibleTextFragment.RunPiece], lineIndex: Int) -> [VisibleTextFragment] {
        // 先合并一个完整 cluster 的多 run（包括零 advance 的组合附加符），再按视觉位置合并。
        let clusters = Dictionary(grouping: pieces, by: \.sourceRange)
            .compactMap { range, runs -> VisibleTextFragment? in
                let runs = runs.sorted { $0.runRange.location < $1.runRange.location }
                guard let first = runs.first else { return nil }
                let rect = runs.dropFirst().reduce(first.rect) { $0.union($1.rect) }
                guard rect.width > 0, isFinite(rect) else { return nil }
                return .init(sourceRange: range, lineIndex: lineIndex, rect: rect, runs: runs)
            }.sorted {
                $0.rect.minX == $1.rect.minX ? $0.sourceRange.location < $1.sourceRange.location : $0.rect.minX < $1
                    .rect
                    .minX
            }
        var result: [FragmentAccumulator] = []
        for fragment in clusters {
            if !result.isEmpty, result[result.count - 1].merge(fragment) { continue }
            result.append(FragmentAccumulator(fragment))
        }
        return result.map {
            .init(sourceRange: $0.sourceRange, lineIndex: lineIndex, rect: $0.rect, runs: $0.runs)
        }
    }

    @MainActor
    private struct FragmentAccumulator {
        var sourceRange: NSRange
        var rect: CGRect
        var runs: [VisibleTextFragment.RunPiece]

        init(_ fragment: VisibleTextFragment) {
            sourceRange = fragment.sourceRange
            rect = fragment.rect
            runs = fragment.runs
        }

        mutating func merge(_ fragment: VisibleTextFragment) -> Bool {
            guard fragment.rect.minX <= rect.maxX + 0.000001,
                  abs(rect.minY - fragment.rect.minY) < 0.000001,
                  abs(rect.maxY - fragment.rect.maxY) < 0.000001,
                  max(sourceRange.location, fragment.sourceRange.location)
                  <= min(NSMaxRange(sourceRange), NSMaxRange(fragment.sourceRange)),
                  VisibleRunGeometry.isFinite(rect.union(fragment.rect)) else { return false }
            let start = min(sourceRange.location, fragment.sourceRange.location)
            let end = max(NSMaxRange(sourceRange), NSMaxRange(fragment.sourceRange))
            sourceRange = NSRange(location: start, length: end - start)
            rect = rect.union(fragment.rect)
            // 原地追加，避免长行每合并一个 cluster 都复制整个此前的 run 数组。
            runs.append(contentsOf: fragment.runs)
            return true
        }
    }
}

/// 无原生连字 caret 时，按完整 grapheme 分配 advance；RTL 的逻辑顺序与视觉顺序相反。
enum LigatureCells {
    static func boundaries(minX: CGFloat, maxX: CGFloat, count: Int, rightToLeft: Bool) -> [CGFloat] {
        guard minX.isFinite, maxX.isFinite, maxX >= minX, count > 0, count < Int.max else { return [] }
        let width = maxX - minX
        guard width.isFinite else { return [] }
        return (0 ... count).map { index in
            let fraction = CGFloat(rightToLeft ? count - index : index) / CGFloat(count)
            return minX + width * fraction
        }
    }
}

/// 原文 cluster 的有序索引；一次构建后，覆盖查询只访问边界与实际覆盖的 cluster。
struct SourceClusterIndex {
    private let ranges: [NSRange]
    private let separators: Set<NSRange>
    private let defaultIgnorables: Set<NSRange>
    private let objectReplacements: Set<NSRange>

    init(source: NSString) {
        var ranges: [NSRange] = []
        var separators: Set<NSRange> = []
        var defaultIgnorables: Set<NSRange> = []
        var objectReplacements: Set<NSRange> = []
        var location = 0
        while location < source.length {
            let range = source.rangeOfComposedCharacterSequence(at: location)
            let string = source.substring(with: range)
            if string.unicodeScalars.allSatisfy({ CharacterSet.newlines.contains($0) }) { separators.insert(range) }
            if string.unicodeScalars.allSatisfy(\.properties.isDefaultIgnorableCodePoint) {
                defaultIgnorables.insert(range)
            }
            if string == "\u{FFFC}" { objectReplacements.insert(range) }
            ranges.append(range)
            location = NSMaxRange(range)
        }
        self.ranges = ranges
        self.separators = separators
        self.defaultIgnorables = defaultIgnorables
        self.objectReplacements = objectReplacements
    }

    /// visitor 只观察本次比较的候选，不保存闭包或公开诊断状态。
    func overlapping(_ range: NSRange, visit: (NSRange) -> Void = { _ in }) -> ArraySlice<NSRange> {
        guard let end = GeometryRange.end(range), range.length > 0 else { return ranges[0 ..< 0] }
        let first = boundary { candidate in
            visit(candidate)
            return NSMaxRange(candidate) <= range.location
        }
        let last = boundary { candidate in
            visit(candidate)
            return candidate.location < end
        }
        return ranges[first ..< last]
    }

    private func boundary(isBefore: (NSRange) -> Bool) -> Int {
        var lower = 0
        var upper = ranges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if isBefore(ranges[middle]) { lower = middle + 1 } else { upper = middle }
        }
        return lower
    }

    func isSeparator(_ range: NSRange) -> Bool {
        separators.contains(range)
    }

    func isDefaultIgnorable(_ range: NSRange) -> Bool {
        defaultIgnorables.contains(range)
    }

    func isObjectReplacement(_ range: NSRange) -> Bool {
        objectReplacements.contains(range)
    }
}
