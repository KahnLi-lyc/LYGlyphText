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

    /// 可选的实际展示高度，单位为 point；不改变文档的自然测量高度。
    /// 默认 nil 使用自然高度；有限非负值（包含 0）直接作为展示高度，其他值回退自然高度。
    public var displayHeight: CGFloat?

    /// 动作完成回调；每次更新都使用最新闭包。
    public var onAction: (@MainActor (LYGlyphTextActionEvent) -> Void)?

    /// 创建富文本展示。SwiftUI 的 layoutPriority 由宿主管理。
    public init(
        document: LYGlyphTextDocument?,
        configuration: LYGlyphTextConfiguration = .init(),
        viewProvider: LYGlyphTextAttachmentViewProvider? = nil,
        displayHeight: CGFloat? = nil,
        onAction: (@MainActor (LYGlyphTextActionEvent) -> Void)? = nil
    ) {
        self.document = document
        self.configuration = configuration
        self.viewProvider = viewProvider
        self.displayHeight = displayHeight
        self.onAction = onAction
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

    /// 有限宽度提议决定实际展示宽度，nil／无限宽度为理想尺寸；负宽度安全归零。
    /// 高度提议不限制自然测量；仅显式 displayHeight 决定额外或受压的展示高度。
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: LYGlyphTextLabel, context: Context) -> CGSize? {
        var size = uiView.sizeThatFits(CGSize(width: proposal.width ?? .infinity, height: .infinity))
        if let width = proposal.width, width.isFinite { size.width = max(0, width) }
        if let displayHeight, displayHeight.isFinite, displayHeight >= 0 { size.height = displayHeight }
        return size
    }

    /// 拆卸时释放文档与 provider，回调重入和重复清理不会恢复已拆卸内容。
    public static func dismantleUIView(_ uiView: LYGlyphTextLabel, coordinator: ()) {
        uiView.clearForDismantle()
    }

    private func apply(to label: LYGlyphTextLabel) {
        label.onAction = onAction
        label.configuration = configuration
        label.document = document
        label.viewProvider = viewProvider
    }
}
