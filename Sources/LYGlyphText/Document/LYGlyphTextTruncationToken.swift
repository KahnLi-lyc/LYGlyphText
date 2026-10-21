import UIKit

/// 行数限制截断时追加的生成内容，例如 `…` 或 `…展开全文`；不属于原文，不参与原文 UTF-16 映射。
///
/// token 与可保留的末行前缀共同排版，宽度不足时先回退原文组合字符，再整体省略 token。
/// 换行符按空格显示；空字符串表示截断但不追加内容。
public struct LYGlyphTextTruncationToken: Equatable {
    /// token 文字，默认 `…`。
    public var text: String
    /// token 字体；nil 时继承最后一条可见行起点的字体（包括动态 body）。
    public var font: UIFont?
    /// token 前景色；nil 时继承最后一条可见行起点的颜色。动态颜色随显示环境解析。
    public var foregroundColor: UIColor?
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

    var displayText: String {
        String(String.UnicodeScalarView(text.unicodeScalars.map {
            CharacterSet.newlines.contains($0) ? " " : $0
        }))
    }

    var interactiveActionID: String? {
        actionID.flatMap { $0.isEmpty ? nil : $0 }
    }
}
