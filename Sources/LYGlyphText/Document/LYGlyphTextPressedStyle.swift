import UIKit

/// MainActor 上的不可变动作按下样式；绘制阶段消费颜色与圆角，高亮不改变排版度量。
@MainActor
public struct LYGlyphTextPressedStyle {
    /// 按下时的前景色；默认 nil，表示沿用原样式。
    public let foregroundColor: UIColor?
    /// 按下时的背景色；默认 tertiarySystemFill，nil 表示不添加背景。
    public let backgroundColor: UIColor?
    /// 按下背景的圆角半径，单位 point；默认 0 为直角。
    ///
    /// 大于 0 时每个可见片段矩形分别绘制圆角背景；非有限值和负值按 0 处理，
    /// 半径不超过片段高度或宽度的一半。
    public let cornerRadius: CGFloat

    /// 保存动作按下时使用的可选颜色与圆角，不创建视图。
    public init(
        foregroundColor: UIColor? = nil, backgroundColor: UIColor? = .tertiarySystemFill, cornerRadius: CGFloat = 0
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius.isFinite ? max(0, cornerRadius) : 0
    }
}
