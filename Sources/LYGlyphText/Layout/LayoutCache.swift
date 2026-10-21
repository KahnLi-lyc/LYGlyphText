import UIKit

/// 单个展示宿主的有界布局缓存：同一解析输入最多保留最近两个宽度的结果。
///
/// 缓存不保存宿主或回调；文档、配置或显示环境变化时由宿主调用 `invalidate()`。
@MainActor
struct LayoutCache {
    static let capacity = 2

    private var resolvedText: ResolvedText?
    private var entries: [(width: CGFloat?, layout: LYGlyphTextLayout)] = []
    /// 实际新建布局的次数；命中缓存不计数。
    private(set) var buildCount = 0

    var count: Int {
        entries.count
    }

    /// 返回指定内容外宽度（包含内边距；nil 为理想宽度）的布局，未命中时按最近使用顺序淘汰。
    mutating func layout(
        width: CGFloat?, document: LYGlyphTextDocument?, configuration: LYGlyphTextConfiguration,
        traits: UITraitCollection
    ) -> LYGlyphTextLayout {
        if let cached = entries.first(where: { $0.width == width }) { return cached.layout }
        let text = resolvedText ?? ResolvedText(document: document, traits: traits, wrapping: configuration.wrapping)
        resolvedText = text
        let scale = traits.displayScale > 0 ? traits.displayScale : 1
        buildCount &+= 1
        let layout = text.layout(
            width: width, insets: configuration.insets, scale: scale, numberOfLines: max(0, configuration.numberOfLines)
        )
        entries.insert((width, layout), at: 0)
        if entries.count > Self.capacity { entries.removeLast() }
        return layout
    }

    /// 丢弃解析输入与全部布局，不重置构建计数。
    mutating func invalidate() {
        resolvedText = nil
        entries.removeAll(keepingCapacity: true)
    }

    mutating func resetBuildCount() {
        buildCount = 0
    }
}
