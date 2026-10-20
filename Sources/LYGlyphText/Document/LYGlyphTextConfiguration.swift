import UIKit

/// 显示配置。使用单词换行和顶部对齐，支持行数限制及尾部省略。
public struct LYGlyphTextConfiguration: Equatable {
    /// 包含在测量尺寸内的文本内边距，单位为 point。
    /// 非有限值和负值在使用时按 0 处理。
    public var textContainerInset: UIEdgeInsets

    /// 最大显示行数，默认 0 表示无限行，负值按 0 处理。
    /// 超出限制时在最后一条可见行显示尾部省略号。
    public var numberOfLines: Int

    /// 创建显示配置，默认没有内边距且不限制行数。
    public init(textContainerInset: UIEdgeInsets = .zero, numberOfLines: Int = 0) {
        self.textContainerInset = textContainerInset
        self.numberOfLines = numberOfLines
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
