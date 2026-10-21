import UIKit

extension LYGlyphTextLabel {
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
