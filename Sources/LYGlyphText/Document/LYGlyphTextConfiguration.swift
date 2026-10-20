import UIKit

/// 显示配置。当前固定为无限行、单词换行和顶部对齐。
public struct LYGlyphTextConfiguration: Equatable {
    /// 包含在测量尺寸内的文本内边距，单位为 point。
    /// 非有限值和负值在使用时按 0 处理。
    public var textContainerInset: UIEdgeInsets

    /// 创建显示配置，默认没有内边距。
    public init(textContainerInset: UIEdgeInsets = .zero) {
        self.textContainerInset = textContainerInset
    }

    var insets: UIEdgeInsets {
        func valid(_ value: CGFloat) -> CGFloat {
            value.isFinite ? max(0, value) : 0
        }
        return UIEdgeInsets(
            top: valid(textContainerInset.top),
            left: valid(textContainerInset.left),
            bottom: valid(textContainerInset.bottom),
            right: valid(textContainerInset.right)
        )
    }
}
