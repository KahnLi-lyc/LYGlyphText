import SwiftUI

/// SwiftUI 富文本展示包装，与 UIKit 使用同一个排版和测量入口。
@MainActor
public struct LYGlyphTextView: UIViewRepresentable {
    /// 当前文档；nil 表示清空。
    public var document: LYGlyphTextDocument?
    /// 文本内边距等显示配置。
    public var configuration: LYGlyphTextConfiguration

    /// 主线程附件工厂；保持对象身份可复用持续可见的附件。
    public var viewProvider: LYGlyphTextAttachmentViewProvider?

    /// 创建富文本展示。SwiftUI 的 layoutPriority 由宿主管理。
    public init(
        document: LYGlyphTextDocument?,
        configuration: LYGlyphTextConfiguration = .init(),
        viewProvider: LYGlyphTextAttachmentViewProvider? = nil
    ) {
        self.document = document
        self.configuration = configuration
        self.viewProvider = viewProvider
    }

    /// 创建底层 UIKit 视图。
    public func makeUIView(context: Context) -> LYGlyphTextLabel {
        let label = LYGlyphTextLabel(frame: .zero)
        apply(to: label)
        return label
    }

    /// 原位替换内容，不保留上一次的文档。
    public func updateUIView(_ uiView: LYGlyphTextLabel, context: Context) {
        apply(to: uiView)
    }

    /// 直接消费宽度提议，nil／无限宽度为理想尺寸，0 宽度安全返回。
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: LYGlyphTextLabel, context: Context) -> CGSize? {
        uiView.sizeThatFits(CGSize(width: proposal.width ?? .infinity, height: .infinity))
    }

    /// 拆卸时释放文档与 provider，回调重入和重复清理不会恢复已拆卸内容。
    public static func dismantleUIView(_ uiView: LYGlyphTextLabel, coordinator: ()) {
        uiView.clearForDismantle()
    }

    private func apply(to label: LYGlyphTextLabel) {
        label.configuration = configuration
        label.document = document
        label.viewProvider = viewProvider
    }
}
