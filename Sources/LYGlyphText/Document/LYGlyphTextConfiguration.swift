import UIKit

/// 显示配置。使用单词换行和顶部对齐，支持行数限制及尾部省略。
public struct LYGlyphTextConfiguration: Equatable, Sendable {
    /// 文本换行策略，覆盖输入段落的 lineBreakMode。
    public enum Wrapping: Equatable, Sendable {
        /// 优先在单词边界换行。
        case word
        /// 按字符换行。
        case character
    }

    /// 文本在可用展示高度中的对齐方式。
    public enum VerticalAlignment: Equatable, Sendable {
        /// 顶部对齐。
        case top
        /// 居中对齐。
        case center
        /// 底部对齐。
        case bottom
    }

    /// 文本换行策略，默认单词换行。
    public var wrapping: Wrapping
    /// 展示垂直对齐，默认顶部。
    public var verticalAlignment: VerticalAlignment

    /// 包含在测量尺寸内的文本内边距，单位为 point。
    /// 非有限值和负值在使用时按 0 处理。
    public var textContainerInset: UIEdgeInsets

    /// 最大显示行数，默认 0 表示无限行，负值按 0 处理。
    /// 超出限制时在最后一条可见行显示尾部截断 token。
    public var numberOfLines: Int

    /// 行数限制生效时追加在最后一条可见行尾部的 token；默认 nil 使用继承末行样式的 `…`。
    public var truncationToken: LYGlyphTextTruncationToken?

    /// 创建显示配置，默认没有内边距且不限制行数。
    public init(
        textContainerInset: UIEdgeInsets = .zero, numberOfLines: Int = 0,
        wrapping: Wrapping = .word, verticalAlignment: VerticalAlignment = .top,
        truncationToken: LYGlyphTextTruncationToken? = nil
    ) {
        self.textContainerInset = textContainerInset
        self.numberOfLines = numberOfLines
        self.wrapping = wrapping
        self.verticalAlignment = verticalAlignment
        self.truncationToken = truncationToken
    }

    var insets: UIEdgeInsets {
        func valid(_ value: CGFloat) -> CGFloat {
            value.isFinite && Float(value).isFinite && (Float(value) * 4).isFinite ? max(0, value) : 0
        }
        return UIEdgeInsets(
            top: valid(textContainerInset.top),
            left: valid(textContainerInset.left),
            bottom: valid(textContainerInset.bottom),
            right: valid(textContainerInset.right)
        )
    }
}
