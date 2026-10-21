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
                if selectedRange != nil { setSelection(nil, presentsMenu: false) }
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

    /// 远程图片加载器，由宿主创建并可在多个 Label 间共享；默认 nil 时远程图片只显示占位图。
    /// 更换加载器会卸载全部附件并在下次展示布局重新挂载和请求。
    public var imageLoader: (any LYGlyphTextImageLoading)? {
        didSet {
            guard !isTearingDown else { return }
            if oldValue !== imageLoader { resetAttachments() }
        }
    }

    /// 设置预排版结果的文档与配置，并在之后首次测量相同宽度且显示环境一致时直接采用其布局，不在主线程重新排版。
    ///
    /// 列表 cell 常在加入 window 之前调用；环境在加入后才确定，因此采用推迟到测量时判断。
    /// 文档或配置随后被替换时放弃该结果；环境始终不一致（例如字号类别已变化）时按普通路径排版。
    /// 回调、附件工厂与图片加载器保持不变。
    public func apply(_ prepared: LYGlyphTextPreparedLayout) {
        guard !isTearingDown else { return }
        configuration = prepared.configuration
        document = prepared.document
        pendingPreparedLayout = prepared
    }

    /// 是否允许长按选择文字并通过系统编辑菜单拷贝；默认 false。
    ///
    /// 长按非动作文字选中所在单词并显示菜单，拖动两端拖柄调整范围；动作范围仍优先发送动作。
    /// 点按选区外、替换文档、移出 window 或关闭此属性会清除选区。
    public var isSelectable = false {
        didSet {
            guard oldValue != isSelectable else { return }
            if !isSelectable { setSelection(nil, presentsMenu: false) }
            updateSelectionGestures()
        }
    }

    /// 当前选中的原文 UTF-16 范围；设置时扩展到完整组合字符，空、越界或不可选时为 nil。
    public var selectedRange: NSRange? {
        get { selectionStorage }
        set { setSelection(newValue, presentsMenu: false) }
    }

    /// 选区变化回调，参数为新的原文 UTF-16 范围或 nil。
    public var onSelectionChange: (@MainActor (NSRange?) -> Void)?

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
                clearAccessibilitySnapshot()
                cancelActionInteraction()
                invalidateText()
            }
        }
    }

    /// 包含内边距的固有高度估算宽度；默认 0 为自动模式。
    /// 实际绘制始终使用 bounds.width。负值或非有限值视为自动模式。
    public var preferredMaxLayoutWidth: CGFloat = 0 {
        didSet {
            if positiveWidth(oldValue) != positiveWidth(preferredMaxLayoutWidth) {
                requestIntrinsicSizeInvalidation()
            }
        }
    }

    var selectionStorage: NSRange?
    var isUpdatingSelection = false
    var selectionLongPress: UILongPressGestureRecognizer?
    var selectionTap: UITapGestureRecognizer?
    var editMenu: UIEditMenuInteraction?
    var selectionHandles: (start: SelectionHandleView, end: SelectionHandleView)?
    lazy var selectionGestureDelegate = SelectionGestureDelegate(owner: self)

    var hostAccessibilityElements: [Any]?
    var preparedAccessibilityElements: [Any] = []
    var preparedAccessibilityRevision: AccessibilityRevision?
    var preparedAccessibilityActions: [Int: ActionGeometry.Entry] = [:]
    var preparedAccessibilityElementIDs: Set<ObjectIdentifier> = []
    var isSendingAccessibilityAction = false

    /// 宿主显式数组（包括空数组）优先；nil 恢复最近展示事务准备的自动内容。
    override public var accessibilityElements: [Any]? {
        get {
            if let hostAccessibilityElements { return hostAccessibilityElements }
            guard preparedAccessibilityRevision == accessibilityRevision, window != nil else { return [] }
            return preparedAccessibilityElements
        }
        set { hostAccessibilityElements = newValue }
    }

    var accessibilityRevision: AccessibilityRevision {
        .init(document: documentRevision, geometry: geometryRevision, attachment: attachmentRevision)
    }

    private var layoutCache = LayoutCache()
    private var pendingPreparedLayout: LYGlyphTextPreparedLayout?
    private var intrinsicInvalidationCount = 0
    private var previousLayoutWidth: CGFloat?
    struct MountedAttachment {
        let descriptor: LYGlyphTextViewAttachment
        let view: UIView
        /// 远程图片由组件内部创建，没有宿主工厂与卸载回调。
        let provider: LYGlyphTextAttachmentViewProvider?
    }

    var attachmentContainer: AttachmentContainer?
    var mountedAttachments: [String: MountedAttachment] = [:]
    var failedAttachmentIDs: Set<String> = []
    var attachmentRevision: UInt64 = 0
    var isReconcilingAttachments = false
    var isTearingDown = false
    var attachmentCleanupDepth = 0
    struct PressSession {
        let actionIndex: Int
        let documentRevision: UInt64
        let geometryRevision: UInt64
        let ancestorScrollPanIDs: Set<ObjectIdentifier>
        let origin: CGPoint
        var latestPoint: CGPoint
        let sequenceID: UInt64
        let usesRecognizer: Bool
    }

    var pressSession: PressSession?
    var actionTimer: ActionGestureTimer?
    var nextSequenceID: UInt64 = 0
    var documentRevision: UInt64 = 0
    var geometryRevision: UInt64 = 0
    var actionRecognizer: ActionGestureRecognizer?
    lazy var scrollObserver = ActionScrollObserver(owner: self)
    var observedScrollViews: [ObservedScrollView] = []
    var actionClock: ActionGestureClock = SystemActionGestureClock.shared {
        didSet {
            if oldValue !== actionClock { cancelActionInteraction() }
        }
    }

    static let attachmentLogger = Logger(subsystem: "LYGlyphText", category: "Attachments")

    var pressedActionIndex: Int? {
        pressSession?.actionIndex
    }

    var observedScrollViewCount: Int {
        observedScrollViews.count
    }

    var layoutMeasurementSnapshot: LayoutMeasurementSnapshot {
        LayoutMeasurementSnapshot(
            layoutBuildCount: layoutCache.buildCount,
            intrinsicInvalidationCount: intrinsicInvalidationCount,
            cachedLayoutCount: layoutCache.count
        )
    }

    func resetLayoutMeasurementCounts() {
        layoutCache.resetBuildCount()
        intrinsicInvalidationCount = 0
    }

    /// bounds 原点也参与附件裁切；几何变化不重建持续可见的视图。
    override public var bounds: CGRect {
        didSet {
            if oldValue != bounds {
                geometryRevision &+= 1
                clearAccessibilitySnapshot()
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
        isAccessibilityElement = false
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
            if explicitWidth == nil { requestIntrinsicSizeInvalidation() }
            setNeedsDisplay()
        }
        let revision = accessibilityRevision
        reconcileAttachments()
        prepareAccessibility(revision: revision)
        if selectedRange != nil { updateSelectionHandles() }
    }

    /// 离开 window 即卸载，重新进入后在展示布局重建。
    override public func didMoveToWindow() {
        super.didMoveToWindow()
        cancelActionInteraction()
        if window == nil {
            if selectedRange != nil { setSelection(nil, presentsMenu: false) }
            resetAttachments()
        } else { setNeedsLayout() }
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
        if let range = selectedRange, let source = document?.string {
            // 选区背景在文字下方绘制，使用宿主 tintColor 的半透明色。
            context.setFillColor(tintColor.withAlphaComponent(0.25).resolvedColor(with: traitCollection).cgColor)
            for rect in SelectionGeometry(layout: layout, source: source).rects(for: range) {
                context.fill(rect)
            }
        }
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
        clearAccessibilitySnapshot()
        attachmentRevision &+= 1
        layoutCache.invalidate()
        requestIntrinsicSizeInvalidation()
        setNeedsLayout()
        setNeedsDisplay()
    }

    private func requestIntrinsicSizeInvalidation() {
        intrinsicInvalidationCount &+= 1
        invalidateIntrinsicContentSize()
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
        imageLoader = nil
        resetAttachments()
        onAction = nil
        document = nil
        viewProvider = nil
        imageLoader = nil
        invalidateText()
    }

    func measuredLayout(width: CGFloat?) -> LYGlyphTextLayout {
        if let prepared = pendingPreparedLayout {
            if prepared.document !== document || prepared.configuration != configuration {
                pendingPreparedLayout = nil
            } else if prepared.width == width.flatMap(normalizedWidth),
                      LayoutEnvironment(traitCollection) == prepared.environment
            {
                pendingPreparedLayout = nil
                layoutCache.adopt(width: prepared.width, layout: prepared.layout, resolvedText: prepared.resolvedText)
            }
        }
        return layoutCache.layout(
            width: width.flatMap(normalizedWidth), document: document, configuration: configuration,
            traits: traitCollection
        )
    }
}
