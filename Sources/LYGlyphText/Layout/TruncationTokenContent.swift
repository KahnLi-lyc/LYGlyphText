import CoreText
import UIKit

/// 截断 token 的已解析内容：颜色已按显示环境解析，只保存可随预排版在后台使用的 Sendable 值。
///
/// 文字片段的 nil 字体／颜色继承最后一条可见行起点的样式；图片片段生成带度量 delegate 的 U+FFFC，
/// 用 `imageKey` 标记片段序号，不携带原文附件位置，因此不会被当作文档附件。
struct TruncationTokenContent {
    enum Piece {
        case text(String, font: UIFont?, color: CGColor?)
        case image(UIImage, size: CGSize, alignment: LYGlyphTextAttachmentAlignment)
    }

    /// 图片片段 run 的标记属性，值为 `pieces` 中的序号。
    static let imageKey = NSAttributedString.Key("LYGlyphText.truncationTokenImage")

    let pieces: [Piece]
    /// 无障碍与调试使用的文本：文字片段与非空图片替代文本按顺序拼接。
    let spokenText: String
    /// 继承属性缺少字体时，图片对齐使用的字体。
    let fallbackFont: UIFont

    /// 单段文字 token；nil 字体与颜色继承原文。
    static func text(_ string: String, font: UIFont? = nil, color: CGColor? = nil) -> Self {
        Self(
            pieces: [.text(string, font: font, color: color)], spokenText: string,
            fallbackFont: UIFont.preferredFont(forTextStyle: .body)
        )
    }

    private init(pieces: [Piece], spokenText: String, fallbackFont: UIFont) {
        self.pieces = pieces
        self.spokenText = spokenText
        self.fallbackFont = fallbackFont
    }

    /// nil token 为默认省略号；`pieces` 为空时使用 text／font／foregroundColor。
    init(_ token: LYGlyphTextTruncationToken?, traits: UITraitCollection) {
        let fallbackFont = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        guard let token else {
            self.init(pieces: [.text("…", font: nil, color: nil)], spokenText: "…", fallbackFont: fallbackFont)
            return
        }
        guard !token.pieces.isEmpty else {
            let text = token.displayText
            self.init(
                pieces: [.text(
                    text,
                    font: token.font,
                    color: token.foregroundColor?.resolvedColor(with: traits).cgColor
                )],
                spokenText: text, fallbackFont: fallbackFont
            )
            return
        }
        var pieces: [Piece] = []
        var spokenText = ""
        for piece in token.pieces {
            switch piece {
            case let .text(text, font, color):
                let text = LYGlyphTextTruncationToken.displayString(text)
                pieces.append(.text(text, font: font, color: color?.resolvedColor(with: traits).cgColor))
                spokenText += text
            case let .image(image, size, alignment, alternativeText):
                guard size.width > 0, size.height > 0, LayoutNumber.isSafe(size.width),
                      LayoutNumber.isSafe(size.height) else { continue }
                pieces.append(.image(image, size: size, alignment: alignment))
                if let alternativeText = alternativeText?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    spokenText += alternativeText
                }
            }
        }
        self.init(pieces: pieces, spokenText: spokenText, fallbackFont: fallbackFont)
    }

    /// 以继承属性（已含段落样式与 token 标记）为基础，按片段顺序生成 token 富文本。
    func attributedString(base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let result = NSMutableAttributedString()
        for (index, piece) in pieces.enumerated() {
            var attributes = base
            switch piece {
            case let .text(text, font, color):
                if let font { attributes[fontKey] = font }
                if let color { attributes[colorKey] = color }
                result.append(NSAttributedString(string: text, attributes: attributes))
            case let .image(_, size, alignment):
                let font = base[fontKey] as? UIFont ?? fallbackFont
                let metrics = AttachmentMetrics(
                    size: size, ascender: font.ascender, descender: font.descender, alignment: alignment
                )
                attributes[NSAttributedString.Key(kCTRunDelegateAttributeName as String)] = metrics.makeDelegate()
                attributes[Self.imageKey] = index
                result.append(NSAttributedString(string: "\u{FFFC}", attributes: attributes))
            }
        }
        return NSAttributedString(attributedString: result)
    }
}
