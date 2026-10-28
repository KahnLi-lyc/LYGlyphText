import CoreText
import UIKit

/// 最后一条可见行的头部／中间截断：保留剩余原文的末尾，中间截断另保留本行开头。
///
/// 末尾只取文档最后一个逻辑段落内的文字（去掉尾部空白），避免把多个段落拼进同一行；
/// 前缀、token 与后缀各自是独立 run，后缀使用 `Line.SourceSegment` 映射原文。
struct EdgeTruncation {
    enum Mode {
        case head
        case middle
    }

    let text: NSAttributedString
    let line: CTLine
    let alignmentOffset: CGFloat
    let tokenRange: NSRange
    let drawsToken: Bool
    let prefixOffset: Int
    let suffixSegment: LYGlyphTextLayout.Line.SourceSegment?
    let visibleSourceRanges: [NSRange]

    /// 剩余原文没有可保留的末尾文字时返回 nil，由调用方回退到尾部截断。
    init?(
        text: NSAttributedString, lineRange: NSRange, sourceLength: Int, width: CGFloat, mode: Mode,
        tokenString: String, tokenFont: UIFont?, tokenColor: CGColor?
    ) {
        let source = text.string as NSString
        let lineStart = lineRange.location
        func trimmedEnd(_ end: Int, floor: Int) -> Int {
            var end = end
            while end > floor {
                let cluster = source.rangeOfComposedCharacterSequence(at: end - 1)
                guard source.substring(with: cluster).unicodeScalars
                    .allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) else { break }
                end = max(floor, cluster.location)
            }
            return end
        }
        let documentEnd = trimmedEnd(min(sourceLength, source.length), floor: lineStart)
        guard documentEnd > lineStart else { return nil }
        let lastParagraph = source.paragraphRange(for: NSRange(location: documentEnd - 1, length: 0))
        let suffixFloor = max(lineStart, lastParagraph.location)
        guard documentEnd > suffixFloor else { return nil }
        func boundaries(from start: Int, to end: Int) -> [Int] {
            var result: [Int] = []
            var cursor = start
            while cursor < end {
                result.append(cursor)
                cursor = NSMaxRange(source.rangeOfComposedCharacterSequence(at: cursor))
            }
            result.append(min(cursor, end))
            return result
        }
        let setup = TruncationSetup(
            text: text, location: lineStart, width: width, tokenString: tokenString, tokenFont: tokenFont,
            tokenColor: tokenColor
        )
        func part(_ start: Int, _ end: Int) -> NSAttributedString {
            text.attributedSubstring(from: NSRange(location: start, length: max(0, end - start)))
        }
        func advance(_ attributed: NSAttributedString) -> CGFloat {
            CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil))
        }

        var prefixEnd = lineStart
        if mode == .middle, setup.drawsToken {
            // 前缀最多占 token 之外一半宽度；按组合字符二分查找最长前缀。
            let budget = max(
                0,
                (setup.capacity - CGFloat(CTLineGetTypographicBounds(setup.tokenLine, nil, nil, nil))) / 2
            )
            let lineEnd = trimmedEnd(min(NSMaxRange(lineRange), documentEnd), floor: lineStart)
            let candidates = boundaries(from: lineStart, to: min(lineEnd, documentEnd))
            var low = 0
            var high = candidates.count - 1
            while low < high {
                let middle = (low + high + 1) / 2
                if advance(part(lineStart, candidates[middle])) <= budget { low = middle } else { high = middle - 1 }
            }
            prefixEnd = candidates[low]
        }
        // 后缀起点不早于前缀结束；起点越靠后越短，二分查找能放下的最长后缀。
        let suffixStarts = boundaries(from: max(suffixFloor, prefixEnd), to: documentEnd)
        let prefix = part(lineStart, prefixEnd)
        var suffixStart = documentEnd
        if setup.drawsToken {
            var low = 0
            var high = suffixStarts.count - 1
            while low < high {
                let middle = (low + high) / 2
                if setup.candidate([prefix, setup.token, part(suffixStarts[middle], documentEnd)]).fits {
                    high = middle
                } else {
                    low = middle + 1
                }
            }
            suffixStart = suffixStarts[low]
        }
        let result = setup.candidate([prefix, setup.token, part(suffixStart, documentEnd)])
        self.text = result.text.copy() as! NSAttributedString
        line = result.line
        alignmentOffset = setup.alignmentOffset(for: result.line)
        drawsToken = setup.drawsToken
        let prefixLength = prefixEnd - lineStart
        tokenRange = NSRange(location: prefixLength, length: setup.token.length)
        prefixOffset = lineStart
        let suffixLocal = prefixLength + setup.token.length
        suffixSegment = suffixStart < documentEnd ? .init(lineStart: suffixLocal, offset: suffixStart - suffixLocal) :
            nil
        var ranges: [NSRange] = []
        if drawsToken, prefixEnd > lineStart { ranges.append(NSRange(location: lineStart, length: prefixLength)) }
        if drawsToken, suffixStart < documentEnd {
            ranges.append(NSRange(location: suffixStart, length: documentEnd - suffixStart))
        }
        visibleSourceRanges = ranges
    }
}
