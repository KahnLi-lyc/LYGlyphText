import CoreGraphics
import Foundation

/// 已按显示环境解析的文字阴影；作为 run 属性随 Core Text 排版传递，只在字形绘制时使用。
final class ResolvedShadow {
    static let key = NSAttributedString.Key("LYGlyphText.shadow")

    let offset: CGSize
    let blurRadius: CGFloat
    let color: CGColor

    init(offset: CGSize, blurRadius: CGFloat, color: CGColor) {
        self.offset = offset
        self.blurRadius = blurRadius
        self.color = color
    }
}
