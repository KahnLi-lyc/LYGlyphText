import UIKit

/// 行数限制截断时追加的生成内容，例如 `…` 或 `…展开全文`；不属于原文，不参与原文 UTF-16 映射。
///
/// token 与可保留的末行前缀共同排版，宽度不足时先回退原文组合字符，再整体省略 token。
/// 换行符按空格显示；空字符串表示截断但不追加内容。需要混合样式或图标时使用 `pieces`。
public struct LYGlyphTextTruncationToken: Equatable, Sendable {
    /// token 的一个片段。
    public enum Piece: Equatable, Sendable {
        /// 文字片段；font／foregroundColor 为 nil 时继承最后一条可见行起点的样式。换行符按空格显示。
        case text(String, font: UIFont? = nil, foregroundColor: UIColor? = nil)
        /// 图片片段，按 point 尺寸参与宽度计算并拉伸填满该尺寸，相对最后一条可见行起点的字体区域对齐；
        /// 宽高不是正的有限值时忽略该片段。图片不随按下状态改色。
        /// alternativeText 非空时按片段顺序参与 token 的无障碍朗读，否则图片只是装饰。
        case image(
            UIImage, size: CGSize, alignment: LYGlyphTextAttachmentAlignment = .center,
            alternativeText: String? = nil
        )
    }

    /// token 文字，默认 `…`。`pieces` 非空时不使用。
    public var text: String
    /// token 字体；nil 时继承最后一条可见行起点的字体（包括动态 body）。`pieces` 非空时不使用。
    public var font: UIFont?
    /// token 前景色；nil 时继承最后一条可见行起点的颜色。动态颜色随显示环境解析。`pieces` 非空时不使用。
    public var foregroundColor: UIColor?
    /// 按顺序排列的文字与图片片段；非空时取代 `text`、`font` 与 `foregroundColor`。默认空。
    /// 整个 token 仍是一个点击区域，按下前景色作用于全部文字片段。
    public var pieces: [Piece] = []
    /// 非空时 token 可点击和长按，事件的 `isTruncationToken` 为 true；空字符串视为不可交互。
    public var actionID: String?
    /// 按下 token 时的前景色；nil 沿用 token 颜色。
    public var pressedForegroundColor: UIColor?
    /// 按下 token 时的背景色；nil 不绘制背景。
    public var pressedBackgroundColor: UIColor?
    /// 按下背景圆角半径，单位 point；非有限值和负值按 0 处理。
    public var pressedCornerRadius: CGFloat

    /// 创建截断 token，默认与未配置时的 `…` 外观相同且不可交互。
    public init(
        text: String = "…", font: UIFont? = nil, foregroundColor: UIColor? = nil, actionID: String? = nil,
        pressedForegroundColor: UIColor? = nil, pressedBackgroundColor: UIColor? = .tertiarySystemFill,
        pressedCornerRadius: CGFloat = 0
    ) {
        self.text = text
        self.font = font
        self.foregroundColor = foregroundColor
        self.actionID = actionID
        self.pressedForegroundColor = pressedForegroundColor
        self.pressedBackgroundColor = pressedBackgroundColor
        self.pressedCornerRadius = pressedCornerRadius
    }

    /// 用文字与图片片段创建截断 token，例如“…全文”加一个箭头图标。
    /// `text` 设为文字片段的拼接，`font` 与 `foregroundColor` 为 nil；其余参数与另一初始化方法相同。
    public init(
        pieces: [Piece], actionID: String? = nil, pressedForegroundColor: UIColor? = nil,
        pressedBackgroundColor: UIColor? = .tertiarySystemFill, pressedCornerRadius: CGFloat = 0
    ) {
        self.init(
            text: pieces.map {
                if case let .text(text, _, _) = $0 { text } else { "" }
            }.joined(),
            actionID: actionID, pressedForegroundColor: pressedForegroundColor,
            pressedBackgroundColor: pressedBackgroundColor, pressedCornerRadius: pressedCornerRadius
        )
        self.pieces = pieces
    }

    var displayText: String {
        Self.displayString(text)
    }

    /// 生成内容只占一行，换行符按空格显示。
    static func displayString(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map {
            CharacterSet.newlines.contains($0) ? " " : $0
        }))
    }

    var interactiveActionID: String? {
        actionID.flatMap { $0.isEmpty ? nil : $0 }
    }
}
