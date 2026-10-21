import CoreText
import UIKit

/// 固定原段落方向，在组合字符边界收缩逻辑尾部，再由 Core Text 重新 shaping。
@MainActor
struct TailTruncation {
    let text: NSAttributedString
    let line: CTLine
    let alignmentOffset: CGFloat
    let sourceOffset: Int
    let tokenRange: NSRange
    let drawsToken: Bool
    /// 实际创建的候选 CTLine 数量，用于约束截断搜索成本。
    let candidateCount: Int

    /// - Parameter usesEstimate: 纯 LTR 行先按位置估算截断点；关闭时从行尾逐个组合字符回退，作为等价对照。
    init(
        text: NSAttributedString, range: NSRange, width: CGFloat, tokenString: String = "…", usesEstimate: Bool = true
    ) {
        let original = text.attributes(at: min(range.location, text.length - 1), effectiveRange: nil)
        // 使用白名单，生成字符不能继承附件 delegate、位置或未来的业务属性。
        var attributes = original.filter {
            $0.key == .font || $0.key == NSAttributedString.Key(kCTFontAttributeName as String)
                || $0.key == NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        }
        let paragraph = ResolvedParagraph(text: text, at: range.location)
        attributes[NSAttributedString.Key(kCTParagraphStyleAttributeName as String)] = paragraph.style
        let token = NSAttributedString(string: tokenString, attributes: attributes)
        let tokenLine = CTLineCreateWithAttributedString(token)
        let paragraphRange = (text.string as NSString).paragraphRange(for: NSRange(location: range.location, length: 0))
        var leading: CGFloat = 0
        var tail: CGFloat = 0
        let indent: CTParagraphStyleSpecifier = range.location == paragraphRange
            .location ? .firstLineHeadIndent : .headIndent
        CTParagraphStyleGetValueForSpecifier(paragraph.style, indent, MemoryLayout<CGFloat>.size, &leading)
        CTParagraphStyleGetValueForSpecifier(paragraph.style, .tailIndent, MemoryLayout<CGFloat>.size, &tail)
        let areaEnd = tail > 0 ? tail : (LayoutNumber.add(width, tail) ?? width)
        let capacity = max(0, LayoutNumber.add(areaEnd, -leading) ?? 0)
        let physicalStart = paragraph.direction == .rightToLeft ? (LayoutNumber.add(width, -areaEnd) ?? 0) : leading
        drawsToken = CGFloat(CTLineGetTypographicBounds(tokenLine, nil, nil, nil)) <= capacity
        let source = text.string as NSString
        sourceOffset = range.location
        var end = NSMaxRange(range)
        // 分隔符和行尾空白不排在生成的省略号之前。
        while end > range.location {
            let cluster = source.rangeOfComposedCharacterSequence(at: end - 1)
            let string = source.substring(with: cluster)
            guard string.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) else { break }
            end = max(range.location, cluster.location)
        }
        if end > range.location, end < source.length {
            let cluster = source.rangeOfComposedCharacterSequence(at: end)
            if cluster.location < end { end = max(range.location, cluster.location) }
        }
        if !drawsToken { end = range.location }
        var count = 0
        func candidate(ending end: Int) -> (text: NSMutableAttributedString, line: CTLine, fits: Bool) {
            count += 1
            let candidate = NSMutableAttributedString(attributedString: text.attributedSubstring(
                from: NSRange(location: range.location, length: end - range.location)
            ))
            candidate.append(token)
            candidate.addAttribute(
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String), value: paragraph.style,
                range: NSRange(location: 0, length: candidate.length)
            )
            let line = CTLineCreateWithAttributedString(candidate)
            return (candidate, line, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) <= capacity)
        }
        func previousBoundary(_ end: Int) -> Int {
            max(range.location, source.rangeOfComposedCharacterSequence(at: end - 1).location)
        }
        // 估算上界不满足时从其下一个边界继续；若上界已经满足，说明宽度并非单调，回到行尾逐个回退保持原结果。
        var start = end
        if usesEstimate, end > range.location, let upper = Self.estimatedUpperBound(
            text: text, range: NSRange(location: range.location, length: end - range.location),
            target: capacity - CGFloat(CTLineGetTypographicBounds(tokenLine, nil, nil, nil)),
            direction: paragraph.direction
        ), upper < end, !candidate(ending: upper).fits {
            start = previousBoundary(upper)
        }
        end = start
        while true {
            let result = candidate(ending: end)
            if result.fits || end == range.location {
                self.text = result.text.copy() as! NSAttributedString
                line = result.line
                alignmentOffset = physicalStart + CGFloat(CTLineGetPenOffsetForFlush(
                    result.line,
                    paragraph.flush,
                    Double(capacity)
                ))
                tokenRange = NSRange(location: result.text.length - token.length, length: token.length)
                break
            }
            end = previousBoundary(end)
        }
        candidateCount = count
    }

    /// 纯 LTR 行由前缀 caret 位置估算可保留的逻辑结尾，再向后放宽两个组合字符吸收 kerning 与 shaping 误差。
    private static func estimatedUpperBound(
        text: NSAttributedString, range: NSRange, target: CGFloat, direction: CTWritingDirection
    ) -> Int? {
        guard direction == .leftToRight, target.isFinite else { return nil }
        let prefix = CTLineCreateWithAttributedString(text.attributedSubstring(from: range))
        let runs = CTLineGetGlyphRuns(prefix) as! [CTRun]
        guard !runs.contains(where: { CTRunGetStatus($0).contains(.rightToLeft) }),
              CGFloat(CTLineGetTypographicBounds(prefix, nil, nil, nil)) > max(0, target) else { return nil }
        let index = CTLineGetStringIndexForPosition(prefix, CGPoint(x: max(0, target), y: 0))
        guard index != kCFNotFound else { return nil }
        let source = text.string as NSString
        var upper = range.location + min(max(0, index), range.length)
        for _ in 0 ..< 2 where upper < NSMaxRange(range) {
            upper = NSMaxRange(source.rangeOfComposedCharacterSequence(at: upper))
        }
        return min(upper, NSMaxRange(range))
    }

    /// 根据最终 run 映射，并合并同一组合字符中被属性切开的片段。
    func visibleSourceRanges(in line: CTLine, source: NSString) -> [NSRange] {
        let ranges: [NSRange] = (CTLineGetGlyphRuns(line) as! [CTRun]).compactMap { run in
            guard drawsToken, CTRunGetGlyphCount(run) > 0 else { return nil }
            let range = CTRunGetStringRange(run)
            let start = max(0, range.location)
            let end = min(tokenRange.location, range.location + range.length)
            guard end > start else { return nil }
            return source.rangeOfComposedCharacterSequences(
                for: NSRange(location: start + sourceOffset, length: end - start)
            )
        }.sorted { $0.location < $1.location }
        var result: [NSRange] = []
        for range in ranges {
            if let last = result.last, NSMaxRange(last) > range.location {
                result[result.count - 1] = NSUnionRange(last, range)
            } else {
                result.append(range)
            }
        }
        return result
    }
}

/// 用完整原段落解析 natural 方向，避免强方向字符被截断后改变省略号位置。
@MainActor
private struct ResolvedParagraph {
    let style: CTParagraphStyle
    let flush: CGFloat
    let direction: CTWritingDirection

    init(text: NSAttributedString, at location: Int) {
        let original = text.attribute(
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String), at: location, effectiveRange: nil
        ) as! CTParagraphStyle
        var alignment = CTTextAlignment.natural
        var direction = CTWritingDirection.natural
        CTParagraphStyleGetValueForSpecifier(original, .alignment, MemoryLayout<CTTextAlignment>.size, &alignment)
        CTParagraphStyleGetValueForSpecifier(
            original,
            .baseWritingDirection,
            MemoryLayout<CTWritingDirection>.size,
            &direction
        )
        if direction == .natural {
            let range = (text.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
            let paragraph = NSMutableAttributedString(attributedString: text.attributedSubstring(from: range))
            // 以 natural 对齐探测 Core Text 解析的基本方向，独立于宿主的 left/center/right。
            paragraph.addAttribute(
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String),
                value: ResolvedParagraphStyle.copy(original, probe: true),
                range: NSRange(location: 0, length: paragraph.length)
            )
            let ideal = CTLineCreateWithAttributedString(paragraph)
            let advance = CGFloat(CTLineGetTypographicBounds(ideal, nil, nil, nil))
            let width = LayoutNumber.add(advance, 100) ?? 100
            let frame = TextFrame(
                framesetter: CTFramesetterCreateWithAttributedString(paragraph),
                width: width,
                scale: 1
            )
            direction = (frame.origins.first?.x ?? 0) > 1 ? .rightToLeft : .leftToRight
        }
        style = ResolvedParagraphStyle.copy(original, direction: direction)
        self.direction = direction
        flush = switch alignment {
        case .center: 0.5
        case .right: 1
        case .natural: direction == .rightToLeft ? 1 : 0
        default: 0
        }
    }
}
