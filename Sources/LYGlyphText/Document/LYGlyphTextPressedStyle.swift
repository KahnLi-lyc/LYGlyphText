import UIKit

/// MainActor 上的不可变动作按下样式；当前仅保存数据，尚不触发高亮绘制。
@MainActor
public struct LYGlyphTextPressedStyle {
    /// 按下时的前景色；默认 nil，表示沿用原样式。
    public let foregroundColor: UIColor?
    /// 按下时的背景色；默认 tertiarySystemFill，nil 表示不添加背景。
    public let backgroundColor: UIColor?

    /// 保存动作按下时使用的可选颜色，不创建视图。
    public init(foregroundColor: UIColor? = nil, backgroundColor: UIColor? = .tertiarySystemFill) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }
}
