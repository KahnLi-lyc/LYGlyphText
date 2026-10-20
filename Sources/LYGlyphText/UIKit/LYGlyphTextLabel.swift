import os
import UIKit

/// 只读富文本视图，使用 Core Text 排版与绘制，支持宽度驱动的 Auto Layout 高度。
@MainActor
public final class LYGlyphTextLabel: UIView {
    /// 当前不可变文档。设为 nil 时清空显示并重新计算尺寸。
    public var document: LYGlyphTextDocument? {
        didSet {
            guard !isTearingDown else { return }
            if oldValue !== document {
                invalidateText()
                resetAttachments()
            }
        }
    }

    /// 附件视图工厂；同一对象重复赋值保持已挂载实例，nil 卸载全部视图附件。
    public var viewProvider: LYGlyphTextAttachmentViewProvider? {
        didSet {
            guard !isTearingDown else { return }
            if oldValue !== viewProvider { resetAttachments() }
        }
    }

    /// 显式丢弃附件实例与本次可见期间的失败记录，下次展示布局重新调用工厂。
    public func reloadAttachments() {
        guard !isTearingDown else { return }
        resetAttachments()
    }

    /// 当前显示配置。更新后清除布局缓存并重新计算固有尺寸。
    public var configuration = LYGlyphTextConfiguration() {
        didSet {
            if oldValue != configuration { invalidateText() }
        }
    }

    /// 包含内边距的固有高度估算宽度；默认 0 为自动模式。
    /// 实际绘制始终使用 bounds.width。负值或非有限值视为自动模式。
    public var preferredMaxLayoutWidth: CGFloat = 0 {
        didSet {
            if positiveWidth(oldValue) != positiveWidth(preferredMaxLayoutWidth) { invalidateIntrinsicContentSize() }
        }
    }

    private var resolvedText: ResolvedText?
    private var cachedLayouts: [(width: CGFloat?, layout: LYGlyphTextLayout)] = []
    private var previousLayoutWidth: CGFloat?
    private struct MountedAttachment {
        let descriptor: LYGlyphTextViewAttachment
        let view: UIView
        let provider: LYGlyphTextAttachmentViewProvider
    }

    private var attachmentContainer: AttachmentContainer?
    private var mountedAttachments: [String: MountedAttachment] = [:]
    private var failedAttachmentIDs: Set<String> = []
    private var attachmentRevision: UInt64 = 0
    private var isReconcilingAttachments = false
    private var isTearingDown = false
    private var attachmentCleanupDepth = 0
    private static let attachmentLogger = Logger(subsystem: "LYGlyphText", category: "Attachments")

    /// bounds 原点也参与附件裁切；几何变化不重建持续可见的视图。
    override public var bounds: CGRect {
        didSet {
            if oldValue != bounds {
                attachmentRevision &+= 1
                setNeedsLayout()
            }
        }
    }

    /// 创建支持代码布局的富文本视图，初始 Hugging 为 defaultLow，抗压缩为 defaultHigh。
    override public init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        clipsToBounds = true
        contentMode = .redraw
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            setContentHuggingPriority(.defaultLow, for: axis)
            setContentCompressionResistancePriority(.defaultHigh, for: axis)
        }
    }

    /// 当前仅支持代码创建，不支持 Storyboard 和归档恢复。
    @available(*, unavailable, message: "请使用 init(frame:)")
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) 不可用")
    }

    /// 理想宽度与当前有效测量宽度下的高度，均按显示比例向上对齐像素。
    override public var intrinsicContentSize: CGSize {
        let ideal = measuredLayout(width: nil).size
        guard let width = explicitWidth ?? positiveWidth(bounds.width) else { return ideal }
        return CGSize(width: ideal.width, height: measuredLayout(width: width).size.height)
    }

    /// 按调用方宽度测量，不读取旧 frame、不修改约束或自身尺寸；高度不限制内容测量。
    override public func sizeThatFits(_ size: CGSize) -> CGSize {
        measuredLayout(width: normalizedWidth(size.width)).size
    }

    /// 横向 required 时直接按目标宽度测量，适用于列表离屏自适应高度。
    override public func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        let width = horizontalFittingPriority == .required ? normalizedWidth(targetSize.width) : nil
        var result = measuredLayout(width: width).size
        if horizontalFittingPriority == .required, targetSize.width.isFinite {
            result.width = max(0, targetSize.width)
        }
        if verticalFittingPriority == .required, targetSize.height.isFinite {
            result.height = max(0, targetSize.height)
        }
        return result
    }

    /// Auto Layout 的压缩尺寸查询使用同一个测量入口。
    override public func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
    }

    /// 仅在有效宽度改变时更新固有高度，避免反复布局失效。
    override public func layoutSubviews() {
        super.layoutSubviews()
        let width = positiveWidth(bounds.width)
        if width != previousLayoutWidth {
            previousLayoutWidth = width
            if explicitWidth == nil { invalidateIntrinsicContentSize() }
            setNeedsDisplay()
        }
        reconcileAttachments()
    }

    /// 离开 window 即卸载，重新进入后在展示布局重建。
    override public func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { resetAttachments() } else { setNeedsLayout() }
    }

    /// 绘制与测量共用布局结果，高度不足时裁切，不自动缩小字体。
    override public func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.clip(to: bounds)
        let insets = configuration.insets
        context.clip(to: CGRect(
            x: bounds.minX + insets.left, y: bounds.minY + insets.top,
            width: max(0, bounds.width - insets.left - insets.right),
            height: max(0, bounds.height - insets.top - insets.bottom)
        ))
        context.translateBy(x: bounds.minX, y: bounds.minY)
        measuredLayout(width: max(0, bounds.width)).draw(in: context)
        context.restoreGState()
    }

    /// 更新默认 body 字体、动态颜色及显示比例后重新排版。
    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        invalidateText()
    }

    private var explicitWidth: CGFloat? {
        positiveWidth(preferredMaxLayoutWidth)
    }

    private func positiveWidth(_ value: CGFloat) -> CGFloat? {
        value.isFinite && value > 0 ? value : nil
    }

    private func normalizedWidth(_ value: CGFloat) -> CGFloat? {
        value.isFinite ? max(0, value) : nil
    }

    private func invalidateText() {
        attachmentRevision &+= 1
        resolvedText = nil
        cachedLayouts.removeAll(keepingCapacity: true)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        setNeedsDisplay()
    }

    /// SwiftUI 拆卸是终止事务；业务清理回调的同步赋值不能恢复被拆卸的输入。
    func clearForDismantle() {
        guard !isTearingDown else { return }
        isTearingDown = true
        defer { isTearingDown = false }
        document = nil
        viewProvider = nil
        resetAttachments()
        document = nil
        viewProvider = nil
        invalidateText()
    }

    private var attachmentContentRect: CGRect {
        let insets = configuration.insets
        return CGRect(
            x: bounds.minX + insets.left, y: bounds.minY + insets.top,
            width: max(0, bounds.width - insets.left - insets.right),
            height: max(0, bounds.height - insets.top - insets.bottom)
        )
    }

    /// 先移除全部内部状态和 superview，再允许业务清理回调重入。
    private func unmount(_ removed: [MountedAttachment], removing container: AttachmentContainer? = nil) {
        guard !removed.isEmpty || container != nil else { return }
        attachmentCleanupDepth += 1
        defer {
            attachmentCleanupDepth -= 1
            setNeedsLayout()
        }
        // 一个旧批次全部清理完毕前，不允许新工厂重新取得尚未回调的旧实例。
        container?.removeFromSuperview()
        for attachment in removed {
            attachment.view.removeFromSuperview()
        }
        for attachment in removed {
            attachment.provider.onUnmount?(attachment.descriptor, attachment.view)
        }
    }

    private func resetAttachments() {
        attachmentRevision &+= 1
        failedAttachmentIDs.removeAll()
        let removed = Array(mountedAttachments.values)
        mountedAttachments.removeAll()
        let container = attachmentContainer
        attachmentContainer = nil
        setNeedsLayout()
        unmount(removed, removing: container)
    }

    private func reconcileAttachments() {
        guard !isTearingDown, attachmentCleanupDepth == 0, !isReconcilingAttachments, window != nil else { return }
        isReconcilingAttachments = true
        defer { isReconcilingAttachments = false }
        let revision = attachmentRevision
        let contentRect = attachmentContentRect
        let placements = measuredLayout(width: max(0, bounds.width)).viewAttachments.filter {
            let rect = $0.rect.offsetBy(dx: bounds.minX, dy: bounds.minY)
            return !contentRect.isEmpty && rect.intersects(contentRect)
        }
        let visibleIDs = Set(placements.map(\.attachment.id))
        failedAttachmentIDs.formIntersection(visibleIDs)
        let hiddenIDs = Set(mountedAttachments.keys).subtracting(visibleIDs)
        let removed = hiddenIDs.compactMap { mountedAttachments.removeValue(forKey: $0) }
        unmount(removed)
        guard revision == attachmentRevision, window != nil, let provider = viewProvider else { return }
        attachmentContainer?.frame = contentRect
        for placement in placements {
            guard revision == attachmentRevision, window != nil, viewProvider === provider else { return }
            let descriptor = placement.attachment
            let rect = placement.rect.offsetBy(dx: bounds.minX - contentRect.minX, dy: bounds.minY - contentRect.minY)
            if let mounted = mountedAttachments[descriptor.id] {
                mounted.view.frame = rect
                continue
            }
            guard !failedAttachmentIDs.contains(descriptor.id) else { continue }
            let candidate = provider.makeView(descriptor)
            // 工厂可以同步替换文档、provider、reload 或移出 window；过期结果从未挂载。
            guard revision == attachmentRevision, window != nil, viewProvider === provider else { return }
            guard let candidate else {
                failedAttachmentIDs.insert(descriptor.id)
                continue
            }
            guard candidate !== self, candidate.superview == nil,
                  !isDescendant(of: candidate),
                  !mountedAttachments.values.contains(where: { $0.view === candidate })
            else {
                Self.attachmentLogger.debug("拒绝已有宿主、重复实例或自身／祖先的附件视图")
                failedAttachmentIDs.insert(descriptor.id)
                continue
            }
            let container: AttachmentContainer
            if let existing = attachmentContainer {
                container = existing
            } else {
                container = AttachmentContainer(frame: contentRect)
                attachmentContainer = container
                addSubview(container)
            }
            candidate.isUserInteractionEnabled = descriptor.isInteractive
            candidate.frame = rect
            guard revision == attachmentRevision, window != nil, viewProvider === provider else { return }
            mountedAttachments[descriptor.id] = MountedAttachment(
                descriptor: descriptor, view: candidate, provider: provider
            )
            container.addSubview(candidate)
        }
    }

    func measuredLayout(width: CGFloat?) -> LYGlyphTextLayout {
        let width = width.flatMap(normalizedWidth)
        if let cached = cachedLayouts.first(where: { $0.width == width }) { return cached.layout }
        let text = resolvedText ?? ResolvedText(document: document, traits: traitCollection)
        resolvedText = text
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        let layout = text.layout(
            width: width, insets: configuration.insets, scale: scale, numberOfLines: max(0, configuration.numberOfLines)
        )
        cachedLayouts.insert((width, layout), at: 0)
        if cachedLayouts.count > 2 { cachedLayouts.removeLast() }
        return layout
    }
}

/// 容器只命中实际交互附件，不拦截文字和空白区域的宿主手势。
@MainActor
private final class AttachmentContainer: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(frame:)")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else { return nil }
        let result = super.hitTest(point, with: event)
        return result === self ? nil : result
    }
}
