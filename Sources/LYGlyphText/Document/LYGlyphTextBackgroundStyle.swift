import UIKit

public extension NSAttributedString.Key {
    /// LYGlyphText 的圆角背景／边框属性，值为 `LYGlyphTextBackgroundStyle`；其他类型的值被忽略。
    static let lyGlyphTextBackground = NSAttributedString.Key("LYGlyphText.backgroundStyle")
}

/// 文字片段的圆角背景与边框，例如话题胶囊或徽标文字。只影响绘制，不改变测量与排版。
///
/// 同一行内相邻且样式相等的片段合并为一个形状；跨行时每行各绘制一段。绘制在普通 `.backgroundColor`
/// 之上、文字之下；被截断隐藏或裁切的文字不绘制背景。
public struct LYGlyphTextBackgroundStyle: Equatable, Sendable {
    /// 填充色；nil 不填充。动态颜色按显示环境解析。
    public var fillColor: UIColor?
    /// 描边色；nil 或描边宽度为 0 时不描边。
    public var strokeColor: UIColor?
    /// 描边宽度，单位 point；非有限值和负值按 0 处理。
    public var strokeWidth: CGFloat
    /// 圆角半径，单位 point；非有限值和负值按 0 处理，绘制时不超过形状宽高的一半。
    public var cornerRadius: CGFloat
    /// 形状相对文字片段向外扩展的距离，单位 point；非有限值按 0 处理，负值表示向内收缩。
    public var padding: UIEdgeInsets

    /// 创建背景样式；默认无填充、无描边、直角、无外扩。
    public init(
        fillColor: UIColor? = nil, strokeColor: UIColor? = nil, strokeWidth: CGFloat = 0, cornerRadius: CGFloat = 0,
        padding: UIEdgeInsets = .zero
    ) {
        func nonnegative(_ value: CGFloat) -> CGFloat {
            value.isFinite ? max(0, value) : 0
        }
        func finite(_ value: CGFloat) -> CGFloat {
            value.isFinite ? value : 0
        }
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWidth = nonnegative(strokeWidth)
        self.cornerRadius = nonnegative(cornerRadius)
        self.padding = UIEdgeInsets(
            top: finite(padding.top), left: finite(padding.left), bottom: finite(padding.bottom),
            right: finite(padding.right)
        )
    }

    var isVisible: Bool {
        fillColor != nil || (strokeColor != nil && strokeWidth > 0)
    }
}
