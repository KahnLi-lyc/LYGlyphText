import CoreText
import UIKit

/// 基于最终原文 cell 的选区几何；坐标属于 Layout，不包含展示偏移与裁切。
struct SelectionGeometry {
    private struct Slot {
        let range: NSRange
        let lineIndex: Int
        let rect: CGRect
        let isRightToLeft: Bool
    }

    private let source: NSString
    private let slots: [Slot]
    private let layout: LYGlyphTextLayout

    init(layout: LYGlyphTextLayout, source: String) {
        self.layout = layout
        self.source = source as NSString
        let runs = layout.lines.map { CTLineGetGlyphRuns($0.text) as! [CTRun] }
        slots = (layout.sourceGeometry?.cells ?? []).compactMap { cell in
            let rects = cell.pieces.map(\.rect).filter { $0.width > 0 && $0.height > 0 }
            guard let first = rects.first, let piece = cell.pieces.first else { return nil }
            let run = runs.indices.contains(piece.lineIndex) && runs[piece.lineIndex].indices.contains(piece.runIndex)
                ? runs[piece.lineIndex][piece.runIndex] : nil
            let isRightToLeft = run.map { CTRunGetStatus($0).contains(.rightToLeft) } ?? false
            return Slot(
                range: cell.range, lineIndex: cell.lineIndex, rect: rects.dropFirst().reduce(first) { $0.union($1) },
                isRightToLeft: isRightToLeft
            )
        }
    }

    var isEmpty: Bool {
        slots.isEmpty
    }

    /// 可见原文的首尾边界；没有可见文字时为 nil。
    var visibleRange: NSRange? {
        guard let first = slots.map(\.range.location).min(),
              let last = slots.map({ NSMaxRange($0.range) }).max() else { return nil }
        return NSRange(location: first, length: last - first)
    }

    /// 距离点最近的原文组合字符边界：先取垂直方向最近的行，再按字符中线决定前后，RTL 字符方向相反。
    func closestBoundary(to point: CGPoint) -> Int? {
        guard !slots.isEmpty else { return nil }
        func verticalDistance(_ rect: CGRect) -> CGFloat {
            point.y < rect.minY ? rect.minY - point.y : (point.y > rect.maxY ? point.y - rect.maxY : 0)
        }
        guard let line = slots.min(by: { verticalDistance($0.rect) < verticalDistance($1.rect) })?.lineIndex
        else { return nil }
        let candidates = slots.filter { $0.lineIndex == line }
        func horizontalDistance(_ rect: CGRect) -> CGFloat {
            point.x < rect.minX ? rect.minX - point.x : (point.x > rect.maxX ? point.x - rect.maxX : 0)
        }
        guard let slot = candidates.min(by: { horizontalDistance($0.rect) < horizontalDistance($1.rect) })
        else { return nil }
        let beforeMiddle = point.x < slot.rect.midX
        return beforeMiddle != slot.isRightToLeft ? slot.range.location : NSMaxRange(slot.range)
    }

    /// 包含点的单词范围；点不在单词上时选择最近的组合字符，空白也作为可选内容。
    func wordRange(at point: CGPoint) -> NSRange? {
        guard let boundary = closestBoundary(to: point) else { return nil }
        let length = source.length
        guard length > 0 else { return nil }
        let index = min(max(0, boundary == length ? boundary - 1 : boundary), length - 1)
        let paragraph = source.paragraphRange(for: NSRange(location: index, length: 0))
        var result: NSRange?
        source.enumerateSubstrings(in: paragraph, options: [.byWords, .substringNotRequired]) { _, range, _, stop in
            if NSLocationInRange(index, range) {
                result = range
                stop.pointee = true
            }
        }
        return clamped(result ?? source.rangeOfComposedCharacterSequence(at: index))
    }

    /// 将范围扩展到完整组合字符并裁到原文长度；空范围返回 nil。
    func clamped(_ range: NSRange) -> NSRange? {
        guard range.location != NSNotFound, range.location >= 0, range.length > 0,
              range.location < source.length else { return nil }
        let end = min(source.length, range.location + min(range.length, source.length - range.location))
        let expanded = source.rangeOfComposedCharacterSequences(
            for: NSRange(location: range.location, length: end - range.location)
        )
        return expanded.length > 0 ? expanded : nil
    }

    /// 选区可见片段按行合并后的矩形。
    func rects(for range: NSRange) -> [CGRect] {
        LYGlyphTextLayout.mergedLineRects(
            layout.visibleTextFragments(in: range, source: source as String).map(\.rect)
        )
    }

    /// 选区开始和结束处的插入点矩形，宽度为 2pt；方向由所在字符决定。
    func carets(for range: NSRange) -> (start: CGRect, end: CGRect)? {
        let selected = slots.filter { NSIntersectionRange($0.range, range).length > 0 }
        guard let first = selected.min(by: { $0.range.location < $1.range.location }),
              let last = selected.max(by: { $0.range.location < $1.range.location }) else { return nil }
        func caret(_ slot: Slot, leading: Bool) -> CGRect {
            let x = leading != slot.isRightToLeft ? slot.rect.minX : slot.rect.maxX
            return CGRect(x: x - 1, y: slot.rect.minY, width: 2, height: slot.rect.height)
        }
        return (caret(first, leading: true), caret(last, leading: false))
    }
}
