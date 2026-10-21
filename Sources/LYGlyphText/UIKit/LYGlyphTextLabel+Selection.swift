import UIKit

extension LYGlyphTextLabel {
    /// 选区拖柄的位置。
    enum SelectionHandle {
        case start
        case end
    }

    /// 当前选区的纯文本；附件输出其替代文本，没有替代文本的附件不输出。
    public var selectedText: String? {
        guard let range = selectedRange, let document else { return nil }
        return Self.plainText(of: document, in: range)
    }

    /// 选中全部可见原文；截断隐藏的原文不在选择范围内。
    override public func selectAll(_ sender: Any?) {
        guard isSelectable, let range = selectionGeometry()?.geometry.visibleRange else { return }
        setSelection(range, presentsMenu: true)
    }

    /// 把选区纯文本写入通用剪贴板。
    override public func copy(_ sender: Any?) {
        guard let text = selectedText, !text.isEmpty else { return }
        UIPasteboard.general.string = text
    }

    override public var canBecomeFirstResponder: Bool {
        isSelectable && selectedRange != nil
    }

    override public func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard isSelectable, selectedRange != nil else { return super.canPerformAction(action, withSender: sender) }
        if action == #selector(copy(_:)) { return selectedText?.isEmpty == false }
        if action == #selector(selectAll(_:)) {
            return selectionGeometry()?.geometry.visibleRange.map { $0 != selectedRange } ?? false
        }
        return false
    }

    /// 失去第一响应者时收起菜单并清除选区。
    override public func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, !isUpdatingSelection { setSelection(nil, presentsMenu: false) }
        return resigned
    }

    // MARK: - Internal

    func selectionGeometry() -> (geometry: SelectionGeometry, display: DisplayGeometry)? {
        guard let document else { return nil }
        let layout = measuredLayout(width: max(0, bounds.width))
        guard let display = DisplayGeometry(bounds: bounds, layoutSize: layout.size, configuration: configuration)
        else { return nil }
        let geometry = SelectionGeometry(layout: layout, source: document.string)
        return geometry.isEmpty ? nil : (geometry, display)
    }

    func layoutPoint(_ point: CGPoint, display: DisplayGeometry) -> CGPoint {
        CGPoint(x: point.x - display.translation.x, y: point.y - display.translation.y)
    }

    /// 选区在展示坐标中的可见矩形，已裁到内容区。
    func selectionDisplayRects() -> [CGRect] {
        guard let range = selectedRange, let selection = selectionGeometry() else { return [] }
        let (geometry, display) = (selection.geometry, selection.display)
        return geometry.rects(for: range).compactMap { rect in
            guard let shown = display.displayRect(rect) else { return nil }
            let clipped = shown.intersection(bounds).intersection(display.contentClip)
            return clipped.isNull || clipped.isEmpty ? nil : clipped
        }
    }

    /// 在点所在单词开始选择；动作范围、无文字或不可选时返回 false。
    @discardableResult
    func beginSelection(at point: CGPoint) -> Bool {
        guard isSelectable, window != nil, !isActionTarget(at: point), let selection = selectionGeometry(),
              let range = selection.geometry.wordRange(at: layoutPoint(point, display: selection.display))
        else { return false }
        cancelActionInteraction()
        setSelection(range, presentsMenu: true)
        return true
    }

    /// 拖动一端拖柄；两端交叉时交换，选区至少保留一个组合字符。
    func moveSelectionHandle(_ handle: SelectionHandle, to point: CGPoint) {
        guard let range = selectedRange, let selection = selectionGeometry(),
              let boundary = selection.geometry.closestBoundary(to: layoutPoint(point, display: selection.display))
        else { return }
        let geometry = selection.geometry
        let fixed = handle == .start ? NSMaxRange(range) : range.location
        let lower = min(boundary, fixed)
        let upper = max(boundary, fixed)
        guard let updated = geometry.clamped(NSRange(location: lower, length: upper - lower)) else { return }
        setSelection(updated, presentsMenu: false)
    }

    func setSelection(_ range: NSRange?, presentsMenu: Bool) {
        let validated = range.flatMap { range -> NSRange? in
            guard isSelectable, let document else { return nil }
            let source = document.string as NSString
            guard range.location != NSNotFound, range.location >= 0, range.length > 0,
                  range.location < source.length else { return nil }
            let end = min(source.length, range.location + min(range.length, source.length - range.location))
            return source.rangeOfComposedCharacterSequences(for: NSRange(
                location: range.location,
                length: end - range.location
            ))
        }
        let changed = validated != selectedRange
        isUpdatingSelection = true
        defer { isUpdatingSelection = false }
        selectionStorage = validated
        if validated == nil {
            editMenu?.dismissMenu()
            if isFirstResponder { _ = super.resignFirstResponder() }
        } else if !isFirstResponder {
            _ = becomeFirstResponder()
        }
        updateSelectionHandles()
        setNeedsDisplay()
        if presentsMenu, validated != nil { presentSelectionMenu() }
        if changed { onSelectionChange?(validated) }
    }

    func presentSelectionMenu() {
        guard let interaction = editMenu else { return }
        let target = selectionDisplayRects().reduce(CGRect.null) { $0.union($1) }
        guard !target.isNull else { return }
        interaction.presentEditMenu(with: UIEditMenuConfiguration(
            identifier: nil, sourcePoint: CGPoint(x: target.midX, y: target.minY)
        ))
    }

    func updateSelectionGestures() {
        if isSelectable, selectionLongPress == nil {
            let press = UILongPressGestureRecognizer(target: self, action: #selector(selectionLongPressed(_:)))
            press.minimumPressDuration = 0.5
            press.delegate = selectionGestureDelegate
            addGestureRecognizer(press)
            selectionLongPress = press
            let tap = UITapGestureRecognizer(target: self, action: #selector(selectionTapped(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = selectionGestureDelegate
            addGestureRecognizer(tap)
            selectionTap = tap
            // 菜单位置由 sourcePoint 指定，不需要代理；菜单项来自本视图的标准编辑动作。
            let menu = UIEditMenuInteraction(delegate: nil)
            addInteraction(menu)
            editMenu = menu
        } else if !isSelectable, let press = selectionLongPress {
            removeGestureRecognizer(press)
            selectionTap.map(removeGestureRecognizer)
            editMenu.map(removeInteraction)
            selectionLongPress = nil
            selectionTap = nil
            editMenu = nil
        }
    }

    func shouldBeginSelectionGesture(_ recognizer: UIGestureRecognizer) -> Bool {
        guard isSelectable, window != nil else { return false }
        let point = recognizer.location(in: self)
        if recognizer === selectionTap { return selectedRange != nil }
        return !isActionTarget(at: point)
    }

    func updateSelectionHandles() {
        guard let range = selectedRange, let selection = selectionGeometry(),
              let carets = selection.geometry.carets(for: range),
              let start = selection.display.displayRect(carets.start),
              let end = selection.display.displayRect(carets.end)
        else {
            selectionHandles?.start.removeFromSuperview()
            selectionHandles?.end.removeFromSuperview()
            selectionHandles = nil
            return
        }
        let handles = selectionHandles ?? (
            SelectionHandleView(owner: self, handle: .start), SelectionHandleView(owner: self, handle: .end)
        )
        selectionHandles = handles
        for (view, caret) in [(handles.start, start), (handles.end, end)] {
            view.tintColor = tintColor
            // Label 裁切子视图；拖柄超出上下边界时移回 bounds 内，保持可见可拖。
            var frame = SelectionHandleView.frame(for: caret, handle: view.handle)
            frame.origin.y = min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height))
            view.frame = frame
            if view.superview !== self { addSubview(view) } else { bringSubviewToFront(view) }
        }
    }

    @objc private func selectionLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        beginSelection(at: recognizer.location(in: self))
    }

    @objc private func selectionTapped(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        if selectionDisplayRects().contains(where: { $0.insetBy(dx: -4, dy: -4).contains(point) }) {
            presentSelectionMenu()
        } else {
            setSelection(nil, presentsMenu: false)
        }
    }

    static func plainText(of document: LYGlyphTextDocument, in range: NSRange) -> String {
        let source = document.string as NSString
        guard NSMaxRange(range) <= source.length else { return "" }
        var result = ""
        var cursor = range.location
        while cursor < NSMaxRange(range) {
            let cluster = source.rangeOfComposedCharacterSequence(at: cursor)
            if cluster.length == 1, source.character(at: cursor) == 0xFFFC {
                let alternative = document.attachments[cursor]?.alternativeText
                    ?? document.viewAttachments[cursor]?.alternativeText
                if let alternative, !alternative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(alternative)
                }
            } else {
                result.append(source.substring(with: cluster))
            }
            cursor = NSMaxRange(cluster)
        }
        return result
    }
}

/// 选择手势的代理对象，避免把 Label 本身暴露为公开的手势代理。
@MainActor
final class SelectionGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var owner: LYGlyphTextLabel?

    init(owner: LYGlyphTextLabel) {
        self.owner = owner
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        owner?.shouldBeginSelectionGesture(gestureRecognizer) ?? false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer is UITapGestureRecognizer
    }
}

/// 选区两端的拖柄：竖线加圆点，命中区扩展到约 44pt。
@MainActor
final class SelectionHandleView: UIView {
    let handle: LYGlyphTextLabel.SelectionHandle
    private weak var owner: LYGlyphTextLabel?
    private static let knob: CGFloat = 10

    init(owner: LYGlyphTextLabel, handle: LYGlyphTextLabel.SelectionHandle) {
        self.owner = owner
        self.handle = handle
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isAccessibilityElement = false
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(owner:handle:)")
    }

    static func frame(for caret: CGRect, handle: LYGlyphTextLabel.SelectionHandle) -> CGRect {
        let width = knob
        let height = caret.height + knob
        let y = handle == .start ? caret.minY - knob : caret.minY
        return CGRect(x: caret.midX - width / 2, y: y, width: width, height: height)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -17, dy: -12).contains(point)
    }

    override func draw(_ rect: CGRect) {
        tintColor.setFill()
        let bar = CGRect(
            x: bounds.midX - 1,
            y: handle == .start ? Self.knob : 0,
            width: 2,
            height: bounds.height - Self.knob
        )
        UIBezierPath(rect: bar).fill()
        let knobY = handle == .start ? 0 : bounds.height - Self.knob
        UIBezierPath(ovalIn: CGRect(x: 0, y: knobY, width: Self.knob, height: Self.knob)).fill()
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        guard let owner else { return }
        switch recognizer.state {
        case .changed:
            var point = recognizer.location(in: owner)
            // 拖柄圆点在字符上下方，换算回字符中线所在高度。
            point.y += handle == .start ? Self.knob : -Self.knob
            owner.moveSelectionHandle(handle, to: point)
        case .ended:
            owner.presentSelectionMenu()
        default:
            break
        }
    }
}
