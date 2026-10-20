import CoreText
import UIKit

/// 所有基线均为 UIKit 本地坐标；原文范围使用 UTF-16，不包含补齐末尾空行的字符。
@MainActor
struct LYGlyphTextLayout {
    struct Line {
        let text: CTLine
        let baseline: CGPoint
        /// 原文 UTF-16 区间；生成的省略号没有原文索引。
        let visibleSourceRanges: [NSRange]
        /// CTLine 索引到原文索引的偏移；截断行重建后使用局部索引。
        let sourceOffset: Int
        /// 生成的省略号在 CTLine 内的索引，与原文中的省略号字符区分。
        let truncationTokenRange: NSRange?
    }

    struct Attachment {
        let attachment: LYGlyphTextAttachment
        let sourceLocation: Int
        /// 相对于文本容器左上原点的完整图片矩形，裁切由展示层统一完成。
        let rect: CGRect
    }

    let size: CGSize
    let lines: [Line]
    let attachments: [Attachment]

    init(size: CGSize, lines: [Line], attachments: [Attachment] = []) {
        self.size = size
        self.lines = lines
        self.attachments = attachments
    }

    func draw(in context: CGContext) {
        context.saveGState()
        context.textMatrix = .identity
        // Core Text 的字形坐标向上，布局基线向下；统一在绘制边界翻转。
        context.scaleBy(x: 1, y: -1)
        for line in lines {
            context.textPosition = CGPoint(x: line.baseline.x, y: -line.baseline.y)
            CTLineDraw(line.text, context)
        }
        context.restoreGState()
        // UIImage 的 UIKit 绘制路径负责方向与 scale；不直接翻转其 CGImage。
        UIGraphicsPushContext(context)
        for placement in attachments {
            placement.attachment.image.draw(in: placement.rect)
        }
        UIGraphicsPopContext()
    }
}

/// 解析动态字体和颜色后的本次显示输入。仅在 MainActor 使用。
@MainActor
final class ResolvedText {
    let framesetter: CTFramesetter
    let sourceLength: Int
    let idealWidth: CGFloat
    private let isEmpty: Bool
    private let attributedText: NSAttributedString
    private let attachments: [Int: LYGlyphTextAttachment]

    init(document: LYGlyphTextDocument?, traits: UITraitCollection) {
        let string = document?.string ?? ""
        sourceLength = (string as NSString).length
        isEmpty = sourceLength == 0
        attachments = document?.attachments ?? [:]
        let text = NSMutableAttributedString(string: string)
        for run in document?.styleRuns ?? [] {
            let font = run.font ?? UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
            let color = (run.color ?? .label).resolvedColor(with: traits)
            text.setAttributes([
                .font: font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): Self.paragraphStyle(for: run)
            ], range: run.range)
        }
        for (location, attachment) in attachments {
            let font = text.attribute(.font, at: location, effectiveRange: nil) as? UIFont
                ?? UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
            let metrics = AttachmentMetrics(
                size: attachment.size, ascender: font.ascender, descender: font.descender,
                alignment: attachment.alignment
            )
            text.addAttributes([
                NSAttributedString.Key(kCTRunDelegateAttributeName as String): metrics.makeDelegate(),
                AttachmentMetrics.locationKey: location
            ], range: NSRange(location: location, length: 1))
        }
        // Core Text 默认不为末尾分隔符生成最后一个空行，添加零宽字符保留该行。
        if let last = string.unicodeScalars.last, CharacterSet.newlines.contains(last) {
            let attributes = text.attributes(at: sourceLength - 1, effectiveRange: nil)
            text.append(NSAttributedString(string: "\u{200B}", attributes: attributes))
        }
        attributedText = text.copy() as! NSAttributedString
        framesetter = CTFramesetterCreateWithAttributedString(text)
        // 按显式行测量 advance；framesetter 的建议宽度会省略行尾空白。
        let stringValue = text.string as NSString
        var cursor = 0
        var maximumWidth: CGFloat = 0
        while cursor < text.length {
            let range = stringValue.lineRange(for: NSRange(location: cursor, length: 0))
            let line = CTLineCreateWithAttributedString(text.attributedSubstring(from: range))
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            maximumWidth = max(maximumWidth, width)
            cursor = NSMaxRange(range)
        }
        idealWidth = maximumWidth
    }

    private static func paragraphStyle(for run: LYGlyphTextDocument.StyleRun) -> CTParagraphStyle {
        var alignment: CTTextAlignment = switch run.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        case .justified: .justified
        default: .natural
        }
        var direction: CTWritingDirection = switch run.writingDirection {
        case .leftToRight: .leftToRight
        case .rightToLeft: .rightToLeft
        default: .natural
        }
        var lineBreakMode = CTLineBreakMode.byWordWrapping
        // CTParagraphStyleCreate 在调用内复制值；指针不逃逸这些作用域。
        return withUnsafePointer(to: &alignment) { alignmentPointer in
            withUnsafePointer(to: &direction) { directionPointer in
                withUnsafePointer(to: &lineBreakMode) { lineBreakPointer in
                    let settings = [
                        CTParagraphStyleSetting(
                            spec: .alignment,
                            valueSize: MemoryLayout<CTTextAlignment>.size,
                            value: alignmentPointer
                        ),
                        CTParagraphStyleSetting(
                            spec: .baseWritingDirection,
                            valueSize: MemoryLayout<CTWritingDirection>.size,
                            value: directionPointer
                        ),
                        CTParagraphStyleSetting(
                            spec: .lineBreakMode,
                            valueSize: MemoryLayout<CTLineBreakMode>.size,
                            value: lineBreakPointer
                        )
                    ]
                    return CTParagraphStyleCreate(settings, settings.count)
                }
            }
        }
    }

    func layout(
        width: CGFloat?, insets: UIEdgeInsets, scale: CGFloat, numberOfLines: Int = 0
    ) -> LYGlyphTextLayout {
        let horizontal = insets.left + insets.right
        let vertical = insets.top + insets.bottom
        let outerWidth = width ?? (idealWidth + horizontal)
        let available = max(0, outerWidth - horizontal)
        func pixelCeil(_ value: CGFloat) -> CGFloat {
            ceil(value * scale) / scale
        }
        if isEmpty || (width != nil && available <= 0) {
            return LYGlyphTextLayout(
                size: CGSize(width: min(outerWidth, pixelCeil(horizontal)), height: pixelCeil(vertical)), lines: []
            )
        }
        // 理想宽度向上对齐像素，避免浮点误差换行；纯换行仍需正宽路径保留行高。
        let contentWidth = width == nil ? max(1 / scale, pixelCeil(available)) : available
        let frame = TextFrame(framesetter: framesetter, width: contentWidth, scale: scale)
        let lines = zip(frame.lines, frame.origins).map { line, origin in
            let range = CTLineGetStringRange(line)
            let start = min(sourceLength, max(0, range.location))
            let end = min(sourceLength, max(start, range.location + range.length))
            return LYGlyphTextLayout.Line(
                text: line,
                baseline: CGPoint(x: insets.left + origin.x, y: insets.top + frame.height - origin.y),
                visibleSourceRanges: end > start ? [NSRange(location: start, length: end - start)] : [],
                sourceOffset: 0,
                truncationTokenRange: nil
            )
        }
        if numberOfLines > 0, lines.count > numberOfLines {
            let visible = truncatedLines(
                Array(lines.prefix(numberOfLines)), width: contentWidth, insets: insets, scale: scale
            )
            return LYGlyphTextLayout(
                size: CGSize(
                    width: pixelCeil(min(outerWidth, idealWidth + horizontal)),
                    height: pixelCeil(visible.height + vertical)
                ),
                lines: visible.lines, attachments: visibleAttachments(in: visible.lines)
            )
        }
        return LYGlyphTextLayout(
            size: CGSize(
                width: pixelCeil(min(outerWidth, idealWidth + horizontal)),
                height: pixelCeil(frame.contentHeight + vertical)
            ),
            lines: lines, attachments: visibleAttachments(in: lines)
        )
    }

    private func visibleAttachments(in lines: [LYGlyphTextLayout.Line]) -> [LYGlyphTextLayout.Attachment] {
        lines.flatMap { line in
            (CTLineGetGlyphRuns(line.text) as! [CTRun]).compactMap { run in
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let location = attributes[AttachmentMetrics.locationKey] as? Int,
                      let attachment = attachments[location], CTRunGetGlyphCount(run) > 0,
                      line.visibleSourceRanges.contains(where: { NSLocationInRange(location, $0) })
                else { return nil }
                let runRange = CTRunGetStringRange(run)
                guard runRange.location + line.sourceOffset == location,
                      line.truncationTokenRange.map({ !NSLocationInRange(runRange.location, $0) }) ?? true
                else { return nil }
                var position = CGPoint.zero
                CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
                let delegate = attributes[kCTRunDelegateAttributeName] as! CTRunDelegate
                let metrics = Unmanaged<AttachmentMetrics>.fromOpaque(
                    CTRunDelegateGetRefCon(delegate)
                ).takeUnretainedValue()
                return LYGlyphTextLayout.Attachment(
                    attachment: attachment, sourceLocation: location,
                    rect: CGRect(
                        x: line.baseline.x + position.x,
                        y: line.baseline.y - position.y - metrics.bottom - attachment.size.height,
                        width: attachment.size.width, height: attachment.size.height
                    )
                )
            }
        }
    }

    private func truncatedLines(
        _ original: [LYGlyphTextLayout.Line], width: CGFloat, insets: UIEdgeInsets, scale: CGFloat
    ) -> (lines: [LYGlyphTextLayout.Line], height: CGFloat) {
        guard let last = original.last else { return ([], 0) }
        let sourceRange = CTLineGetStringRange(last.text)
        let start = min(sourceLength, sourceRange.location)
        let end = min(sourceLength, sourceRange.location + sourceRange.length)
        let truncation = TailTruncation(
            text: attributedText, range: NSRange(location: start, length: end - start), width: width
        )
        let finalText = truncation.text
        let metricsText = NSMutableAttributedString(string: "")
        let previous = original.dropLast().last
        if let previous {
            let range = CTLineGetStringRange(previous.text)
            metricsText.append(attributedText.attributedSubstring(from: NSRange(
                location: range.location,
                length: range.length
            )))
            if let last = metricsText.string.unicodeScalars.last, !CharacterSet.newlines.contains(last) {
                var attributes = attributedText.attributes(at: range.location + range.length - 1, effectiveRange: nil)
                attributes.removeValue(forKey: NSAttributedString.Key(kCTRunDelegateAttributeName as String))
                attributes.removeValue(forKey: AttachmentMetrics.locationKey)
                metricsText.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }
        metricsText.append(finalText)
        // 无限宽只用于两个最终显示行的垂直度量，避免超宽字形把人工分隔符另排一行。
        // 真实字形来自已固定段落方向的末行，前面各行位置保持不变。
        let metrics = TextFrame(
            framesetter: CTFramesetterCreateWithAttributedString(metricsText),
            width: .greatestFiniteMagnitude, scale: scale
        )
        let firstBaseline = metrics.origins.first.map { metrics.height - $0.y } ?? 0
        let lastBaseline = metrics.origins.last.map { metrics.height - $0.y } ?? firstBaseline
        let offset = previous.map { $0.baseline.y - insets.top - firstBaseline } ?? 0
        var lines = Array(original.dropLast())
        lines.append(LYGlyphTextLayout.Line(
            text: truncation.drawsToken ? truncation
                .line : CTLineCreateWithAttributedString(NSAttributedString(string: "")),
            baseline: CGPoint(x: insets.left + truncation.alignmentOffset, y: insets.top + offset + lastBaseline),
            visibleSourceRanges: truncation.visibleSourceRanges(
                in: truncation.line,
                source: attributedText.string as NSString
            ),
            sourceOffset: truncation.sourceOffset,
            truncationTokenRange: truncation.drawsToken ? truncation.tokenRange : nil
        ))
        return (lines, offset + metrics.contentHeight)
    }
}

/// Core Text 的帧度量与行原点，保持系统行高规则；坐标尚未转换为 UIKit。
@MainActor
struct TextFrame {
    let contentHeight: CGFloat
    let height: CGFloat
    let lines: [CTLine]
    let origins: [CGPoint]

    init(framesetter: CTFramesetter, width: CGFloat, scale: CGFloat) {
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude), nil
        )
        contentHeight = suggested.height
        height = ceil(suggested.height * scale) / scale + 1 / scale
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        self.origins = origins
    }
}
