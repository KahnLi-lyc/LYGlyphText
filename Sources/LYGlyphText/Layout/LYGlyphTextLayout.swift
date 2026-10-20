import CoreText
import UIKit

/// 所有基线均为 UIKit 本地坐标；原文范围使用 UTF-16，不包含补齐末尾空行的字符。
@MainActor
struct LYGlyphTextLayout {
    struct Line {
        let text: CTLine
        let baseline: CGPoint
        let sourceRange: NSRange
    }

    let size: CGSize
    let lines: [Line]

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
    }
}

/// 解析动态字体和颜色后的本次显示输入。仅在 MainActor 使用。
@MainActor
final class ResolvedText {
    let framesetter: CTFramesetter
    let sourceLength: Int
    let idealWidth: CGFloat
    private let isEmpty: Bool

    init(document: LYGlyphTextDocument?, traits: UITraitCollection) {
        let string = document?.string ?? ""
        sourceLength = (string as NSString).length
        isEmpty = sourceLength == 0
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
        // Core Text 默认不为末尾分隔符生成最后一个空行，添加零宽字符保留该行。
        if let last = string.unicodeScalars.last, CharacterSet.newlines.contains(last) {
            let attributes = text.attributes(at: sourceLength - 1, effectiveRange: nil)
            text.append(NSAttributedString(string: "\u{200B}", attributes: attributes))
        }
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

    func layout(width: CGFloat?, insets: UIEdgeInsets, scale: CGFloat) -> LYGlyphTextLayout {
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
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude), nil
        )
        let frameHeight = pixelCeil(suggested.height) + 1 / scale
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: contentWidth, height: frameHeight), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let textLines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: textLines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let lines = zip(textLines, origins).map { line, origin in
            let range = CTLineGetStringRange(line)
            let start = min(sourceLength, max(0, range.location))
            let end = min(sourceLength, max(start, range.location + range.length))
            return LYGlyphTextLayout.Line(
                text: line,
                baseline: CGPoint(x: insets.left + origin.x, y: insets.top + frameHeight - origin.y),
                sourceRange: NSRange(location: start, length: end - start)
            )
        }
        return LYGlyphTextLayout(
            size: CGSize(
                width: pixelCeil(min(outerWidth, idealWidth + horizontal)),
                height: pixelCeil(suggested.height + vertical)
            ),
            lines: lines
        )
    }
}
