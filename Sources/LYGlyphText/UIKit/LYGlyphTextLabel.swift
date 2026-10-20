import UIKit

/// 只读富文本视图，使用 Core Text 排版与绘制，支持宽度驱动的 Auto Layout 高度。
@MainActor
public final class LYGlyphTextLabel: UIView {
    /// 当前不可变文档。设为 nil 时清空显示并重新计算尺寸。
    public var document: LYGlyphTextDocument? {
        didSet {
            if oldValue !== document { invalidateText() }
        }
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
    }

    /// 绘制与测量共用布局结果，高度不足时裁切，不自动缩小字体。
    override public func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.clip(to: bounds)
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
        resolvedText = nil
        cachedLayouts.removeAll(keepingCapacity: true)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        setNeedsDisplay()
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
