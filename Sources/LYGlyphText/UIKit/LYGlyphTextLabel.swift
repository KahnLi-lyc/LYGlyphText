import os
import UIKit

/// 只读富文本视图，使用 Core Text 排版与绘制，支持宽度驱动的 Auto Layout 高度。
@MainActor
public final class LYGlyphTextLabel: UIView {
    /// 动作完成回调；置 nil 会立即取消当前按压，替换非空回调不会中断同一序列。
    public var onAction: (@MainActor (LYGlyphTextActionEvent) -> Void)? {
        didSet {
            if isTearingDown, onAction != nil {
                onAction = nil
                return
            }
            if onAction == nil { cancelActionInteraction() }
        }
    }

    /// 当前不可变文档。设为 nil 时清空显示并重新计算尺寸。
    public var document: LYGlyphTextDocument? {
        didSet {
            guard !isTearingDown else { return }
            if oldValue !== document {
                documentRevision &+= 1
                cancelActionInteraction()
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
            if oldValue != configuration {
                geometryRevision &+= 1
                cancelActionInteraction()
                invalidateText()
            }
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
    private struct PressSession {
        let actionIndex: Int
        let documentRevision: UInt64
        let geometryRevision: UInt64
        let ancestorScrollPanIDs: Set<ObjectIdentifier>
        let origin: CGPoint
        var latestPoint: CGPoint
        let sequenceID: UInt64
        let usesRecognizer: Bool
    }

    private var pressSession: PressSession?
    private var actionTimer: ActionGestureTimer?
    private var nextSequenceID: UInt64 = 0
    private var documentRevision: UInt64 = 0
    private var geometryRevision: UInt64 = 0
    private var actionRecognizer: ActionGestureRecognizer?
    private lazy var scrollObserver = ActionScrollObserver(owner: self)
    private var observedScrollViews: [ObservedScrollView] = []
    var actionClock: ActionGestureClock = SystemActionGestureClock.shared {
        didSet {
            if oldValue !== actionClock { cancelActionInteraction() }
        }
    }

    private static let attachmentLogger = Logger(subsystem: "LYGlyphText", category: "Attachments")

    var pressedActionIndex: Int? {
        pressSession?.actionIndex
    }

    var observedScrollViewCount: Int {
        observedScrollViews.count
    }

    /// bounds 原点也参与附件裁切；几何变化不重建持续可见的视图。
    override public var bounds: CGRect {
        didSet {
            if oldValue != bounds {
                geometryRevision &+= 1
                cancelActionInteraction()
                attachmentRevision &+= 1
                setNeedsLayout()
                setNeedsDisplay()
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
        let recognizer = ActionGestureRecognizer(owner: self)
        actionRecognizer = recognizer
        addGestureRecognizer(recognizer)
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
        cancelActionInteraction()
        if window == nil { resetAttachments() } else { setNeedsLayout() }
    }

    /// 层级变化会使祖先滚动观察和触摸归属失效。
    override public func didMoveToSuperview() {
        super.didMoveToSuperview()
        cancelActionInteraction()
    }

    /// 绘制与测量共用布局结果，高度不足时裁切，不自动缩小字体。
    override public func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let layout = measuredLayout(width: max(0, bounds.width))
        guard let geometry = DisplayGeometry(bounds: bounds, layoutSize: layout.size, configuration: configuration)
        else { return }
        context.saveGState()
        context.clip(to: bounds)
        context.clip(to: geometry.contentClip)
        context.translateBy(x: geometry.translation.x, y: geometry.translation.y)
        layout.draw(in: context, pressedActionIndex: pressedActionIndex)
        context.restoreGState()
    }

    /// 更新默认 body 字体、动态颜色及显示比例后重新排版。
    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        geometryRevision &+= 1
        cancelActionInteraction()
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
        cancelActionInteraction()
        onAction = nil
        document = nil
        viewProvider = nil
        resetAttachments()
        onAction = nil
        document = nil
        viewProvider = nil
        invalidateText()
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
        cancelActionInteraction()
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
        let layout = measuredLayout(width: max(0, bounds.width))
        let geometry = DisplayGeometry(bounds: bounds, layoutSize: layout.size, configuration: configuration)
        let contentRect = geometry?.contentClip ?? .zero
        let placements = layout.viewAttachments.compactMap { placement -> (LYGlyphTextLayout.ViewAttachment, CGRect)? in
            guard let rect = geometry?.displayRect(placement.rect),
                  !contentRect.isEmpty, rect.intersects(contentRect) else { return nil }
            return (placement, rect)
        }
        let visibleIDs = Set(placements.map(\.0.attachment.id))
        failedAttachmentIDs.formIntersection(visibleIDs)
        let hiddenIDs = Set(mountedAttachments.keys).subtracting(visibleIDs)
        if !hiddenIDs.isEmpty { cancelActionInteraction() }
        let removed = hiddenIDs.compactMap { mountedAttachments.removeValue(forKey: $0) }
        unmount(removed)
        guard revision == attachmentRevision, window != nil, let provider = viewProvider else { return }
        attachmentContainer?.frame = contentRect
        for (placement, displayRect) in placements {
            guard revision == attachmentRevision, window != nil, viewProvider === provider else { return }
            let descriptor = placement.attachment
            let rect = displayRect.offsetBy(dx: -contentRect.minX, dy: -contentRect.minY)
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
            cancelActionInteraction()
            mountedAttachments[descriptor.id] = MountedAttachment(
                descriptor: descriptor, view: candidate, provider: provider
            )
            container.addSubview(candidate)
        }
    }

    func measuredLayout(width: CGFloat?) -> LYGlyphTextLayout {
        let width = width.flatMap(normalizedWidth)
        if let cached = cachedLayouts.first(where: { $0.width == width }) { return cached.layout }
        let text = resolvedText ?? ResolvedText(
            document: document,
            traits: traitCollection,
            wrapping: configuration.wrapping
        )
        resolvedText = text
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        let layout = text.layout(
            width: width, insets: configuration.insets, scale: scale, numberOfLines: max(0, configuration.numberOfLines)
        )
        cachedLayouts.insert((width, layout), at: 0)
        if cachedLayouts.count > 2 { cachedLayouts.removeLast() }
        return layout
    }

    func shouldReceiveActionTouch(at point: CGPoint, touchedView: UIView?) -> Bool {
        if pressSession != nil {
            cancelActionInteraction()
            return false
        }
        return actionEntry(at: point, touchedView: touchedView) != nil
    }

    @discardableResult
    func beginActionInteraction(at point: CGPoint, touchedView: UIView?, fromRecognizer: Bool = false) -> Bool {
        guard pressSession == nil else {
            cancelActionInteraction()
            return false
        }
        guard let entry = actionEntry(at: point, touchedView: touchedView) else { return false }
        let scrollViews = ancestorScrollViews()
        guard !scrollViews.contains(where: isScrollViewActive) else { return false }
        nextSequenceID &+= 1
        let sequenceID = nextSequenceID
        pressSession = PressSession(
            actionIndex: entry.actionIndex,
            documentRevision: documentRevision,
            geometryRevision: geometryRevision,
            ancestorScrollPanIDs: scrollPanIDs(for: scrollViews),
            origin: point,
            latestPoint: point,
            sequenceID: sequenceID,
            usesRecognizer: fromRecognizer
        )
        bindScrollObservers(scrollViews)
        actionTimer = actionClock.schedule(after: 0.5, sequenceID: sequenceID) { [weak self] value in
            self?.longPressTimerFired(sequenceID: value)
        }
        setNeedsDisplay()
        return true
    }

    func moveActionInteraction(to point: CGPoint) {
        guard var session = pressSession else { return }
        session.latestPoint = point
        pressSession = session
        let distance = hypot(point.x - session.origin.x, point.y - session.origin.y)
        guard distance <= 10, validatedEntry(for: session, at: point) != nil else {
            cancelActionInteraction()
            return
        }
    }

    func endActionInteraction(at point: CGPoint) {
        guard var session = pressSession else { return }
        session.latestPoint = point
        pressSession = session
        guard let entry = validatedEntry(for: session, at: point), let callback = onAction else {
            cancelActionInteraction()
            return
        }
        let event = entry.event(kind: .tap)
        finishActionInteraction(succeeded: true)
        callback(event)
    }

    func cancelActionInteraction(transitionRecognizer: Bool = true) {
        guard pressSession != nil || actionTimer != nil || !observedScrollViews.isEmpty else { return }
        finishActionInteraction(succeeded: false, transitionRecognizer: transitionRecognizer)
    }

    func ancestorScrollDidChange(_ recognizer: UIPanGestureRecognizer) {
        guard let observed = observedScrollViews.first(where: { $0.panGestureRecognizer === recognizer }),
              recognizer.state == .began || recognizer.state == .changed
              || observed.scrollView.map(isScrollViewActive) == true
        else { return }
        cancelActionInteraction()
    }

    func isAncestorScrollPan(_ recognizer: UIGestureRecognizer) -> Bool {
        ancestorScrollViews().contains { $0.panGestureRecognizer === recognizer }
    }

    private func longPressTimerFired(sequenceID: UInt64) {
        guard let session = pressSession, session.sequenceID == sequenceID else { return }
        guard let entry = validatedEntry(for: session, at: session.latestPoint), let callback = onAction else {
            cancelActionInteraction()
            return
        }
        let event = entry.event(kind: .longPress)
        finishActionInteraction(succeeded: true)
        callback(event)
    }

    private func finishActionInteraction(succeeded: Bool, transitionRecognizer: Bool = true) {
        guard let session = pressSession else {
            actionTimer?.cancel()
            actionTimer = nil
            unbindScrollObservers()
            return
        }
        pressSession = nil
        actionTimer?.cancel()
        actionTimer = nil
        unbindScrollObservers()
        setNeedsDisplay()
        if transitionRecognizer, session.usesRecognizer {
            actionRecognizer?.finishRecognition(succeeded: succeeded)
        }
    }

    private func actionEntry(at point: CGPoint, touchedView: UIView?) -> ActionGeometry.Entry? {
        guard !isTearingDown, window != nil, document != nil, onAction != nil,
              bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0,
              !isInteractiveAttachmentTarget(touchedView)
        else { return nil }
        let layout = measuredLayout(width: max(0, bounds.width))
        return ActionGeometry(layout: layout, bounds: bounds, configuration: configuration).hit(at: point)
    }

    private func validatedEntry(for session: PressSession, at point: CGPoint) -> ActionGeometry.Entry? {
        let scrollViews = ancestorScrollViews()
        guard session.documentRevision == documentRevision, session.geometryRevision == geometryRevision,
              session.ancestorScrollPanIDs == scrollPanIDs(for: scrollViews),
              !scrollViews.contains(where: isScrollViewActive),
              let entry = actionEntry(at: point, touchedView: nil), entry.actionIndex == session.actionIndex
        else { return nil }
        return entry
    }

    private func isInteractiveAttachmentTarget(_ view: UIView?) -> Bool {
        guard let view else { return false }
        return mountedAttachments.values.contains { mounted in
            mounted.descriptor.isInteractive && (view === mounted.view || view.isDescendant(of: mounted.view))
        }
    }

    private func ancestorScrollViews() -> [UIScrollView] {
        var result: [UIScrollView] = []
        var ancestor = superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView { result.append(scrollView) }
            ancestor = current.superview
        }
        return result
    }

    private func isScrollViewActive(_ scrollView: UIScrollView) -> Bool {
        scrollView.isDragging || scrollView.isDecelerating
            || scrollView.panGestureRecognizer.state == .began
            || scrollView.panGestureRecognizer.state == .changed
    }

    private func scrollPanIDs(for scrollViews: [UIScrollView]) -> Set<ObjectIdentifier> {
        Set(scrollViews.map { ObjectIdentifier($0.panGestureRecognizer) })
    }

    private func bindScrollObservers(_ scrollViews: [UIScrollView]) {
        unbindScrollObservers()
        for scrollView in scrollViews {
            let pan = scrollView.panGestureRecognizer
            pan.addTarget(scrollObserver, action: #selector(ActionScrollObserver.scrollPanChanged(_:)))
            observedScrollViews.append(.init(scrollView: scrollView, panGestureRecognizer: pan))
        }
    }

    private func unbindScrollObservers() {
        for observed in observedScrollViews {
            observed.panGestureRecognizer?.removeTarget(
                scrollObserver,
                action: #selector(ActionScrollObserver.scrollPanChanged(_:))
            )
        }
        observedScrollViews.removeAll()
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
