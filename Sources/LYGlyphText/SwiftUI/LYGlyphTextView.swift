import SwiftUI

/// SwiftUI 富文本展示包装，与 UIKit 使用同一个排版和测量入口。
@MainActor
public struct LYGlyphTextView: UIViewRepresentable {
    /// 当前文档；nil 表示清空。
    public var document: LYGlyphTextDocument?
    /// 文本内边距等显示配置。
    public var configuration: LYGlyphTextConfiguration

    /// 创建富文本展示。SwiftUI 的 layoutPriority 由宿主管理。
    public init(
        document: LYGlyphTextDocument?,
        configuration: LYGlyphTextConfiguration = .init()
    ) {
        self.document = document
        self.configuration = configuration
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

    /// 拆卸时释放文档，重复清理安全。
    public static func dismantleUIView(_ uiView: LYGlyphTextLabel, coordinator: ()) {
        uiView.document = nil
    }

    private func apply(to label: LYGlyphTextLabel) {
        label.configuration = configuration
        label.document = document
    }
}
