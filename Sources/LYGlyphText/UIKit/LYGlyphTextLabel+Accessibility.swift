import UIKit

extension LYGlyphTextLabel {
    func clearAccessibilitySnapshot() {
        preparedAccessibilityElements = []
        preparedAccessibilityActions = [:]
        preparedAccessibilityElementIDs = []
        preparedAccessibilityRevision = nil
    }

    func prepareAccessibility(revision: AccessibilityRevision) {
        guard revision == accessibilityRevision, !isTearingDown, attachmentCleanupDepth == 0,
              !isReconcilingAttachments, window != nil else { return }
        guard preparedAccessibilityRevision != revision else { return }
        guard let document else {
            clearAccessibilitySnapshot()
            preparedAccessibilityRevision = revision
            return
        }
        MeasurementCounters.accessibilityPreparations &+= 1
        let layout = measuredLayout(width: max(0, bounds.width))
        let nativeViews = mountedAttachments.mapValues(\.view)
        let semantics = TextAccessibility(
            layout: layout,
            document: document,
            bounds: bounds,
            configuration: configuration,
            nativeViews: nativeViews
        )
        let elements: [Any] = semantics.items.map { item in
            switch item {
            case let .text(entry): TextAccessibilityElement(owner: self, revision: revision, entry: entry)
            case let .native(view): view
            }
        }
        guard revision == accessibilityRevision, window != nil else { return }
        let actions = ActionGeometry(layout: layout, bounds: bounds, configuration: configuration).entries
        preparedAccessibilityActions = Dictionary(uniqueKeysWithValues: actions.map { ($0.actionIndex, $0) })
        preparedAccessibilityElementIDs = Set(elements
            .compactMap { ($0 as? TextAccessibilityElement).map(ObjectIdentifier.init) })
        preparedAccessibilityElements = elements
        preparedAccessibilityRevision = revision
    }

    func isCurrentAccessibilityElement(_ element: TextAccessibilityElement) -> Bool {
        !isTearingDown && window != nil && element.revision == accessibilityRevision
            && preparedAccessibilityRevision == accessibilityRevision
            && preparedAccessibilityElementIDs.contains(ObjectIdentifier(element))
    }

    func canActivateAccessibilityElement(_ element: TextAccessibilityElement) -> Bool {
        hostAccessibilityElements == nil && !isAccessibilityElement && isAccessibilityVisible
            && isCurrentAccessibilityElement(element) && onAction != nil && element.entry.actionIndex != nil
            && element.entry.actionIndex.flatMap { preparedAccessibilityActions[$0] } != nil
    }

    private var isAccessibilityVisible: Bool {
        var ancestor: UIView? = self
        while let view = ancestor {
            guard !view.isHidden, view.alpha > 0, !view.accessibilityElementsHidden else { return false }
            ancestor = view.superview
        }
        return true
    }

    func activateAccessibilityElement(_ element: TextAccessibilityElement) -> Bool {
        guard !isSendingAccessibilityAction, canActivateAccessibilityElement(element) else { return false }
        isSendingAccessibilityAction = true
        defer { isSendingAccessibilityAction = false }
        cancelActionInteraction()
        // 取消路径也可能进入宿主代码；重新核对事务，再读最新闭包。
        guard canActivateAccessibilityElement(element), let callback = onAction,
              let index = element.entry.actionIndex, let entry = preparedAccessibilityActions[index]
        else { return false }
        callback(entry.event(kind: .tap))
        return true
    }
}
