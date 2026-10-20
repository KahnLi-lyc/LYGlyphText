import UIKit

@MainActor
protocol ActionGestureTimer: AnyObject {
    func cancel()
}

@MainActor
protocol ActionGestureClock: AnyObject {
    func schedule(
        after interval: TimeInterval,
        sequenceID: UInt64,
        handler: @escaping @MainActor (UInt64) -> Void
    ) -> ActionGestureTimer
}

@MainActor
final class SystemActionGestureClock: ActionGestureClock {
    static let shared = SystemActionGestureClock()

    private init() {}

    func schedule(
        after interval: TimeInterval,
        sequenceID: UInt64,
        handler: @escaping @MainActor (UInt64) -> Void
    ) -> ActionGestureTimer {
        let timer = Timer(timeInterval: interval, repeats: false) { _ in
            MainActor.assumeIsolated {
                handler(sequenceID)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return SystemActionGestureTimer(timer: timer)
    }
}

@MainActor
private final class SystemActionGestureTimer: ActionGestureTimer {
    private var timer: Timer?

    init(timer: Timer) {
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
final class ActionGestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private weak var actionOwner: LYGlyphTextLabel?
    private weak var primaryTouch: UITouch?

    init(owner: LYGlyphTextLabel) {
        actionOwner = owner
        super.init(target: nil, action: nil)
        delegate = self
        delaysTouchesBegan = false
        delaysTouchesEnded = true
        cancelsTouchesInView = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, primaryTouch == nil, let touch = touches.first, let actionOwner else {
            cancelActiveSequence()
            return
        }
        primaryTouch = touch
        guard actionOwner.beginActionInteraction(
            at: touch.location(in: actionOwner),
            touchedView: touch.view,
            fromRecognizer: true
        ) else {
            primaryTouch = nil
            state = .failed
            return
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let primaryTouch, touches.contains(primaryTouch), let actionOwner else { return }
        actionOwner.moveActionInteraction(to: primaryTouch.location(in: actionOwner))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let primaryTouch, touches.contains(primaryTouch), let actionOwner else { return }
        actionOwner.endActionInteraction(at: primaryTouch.location(in: actionOwner))
        self.primaryTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        primaryTouch = nil
        actionOwner?.cancelActionInteraction()
    }

    override func reset() {
        primaryTouch = nil
        actionOwner?.cancelActionInteraction(transitionRecognizer: false)
        super.reset()
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        if actionOwner?.isAncestorScrollPan(preventedGestureRecognizer) == true { return false }
        return super.canPrevent(preventedGestureRecognizer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === self, let actionOwner else { return false }
        return actionOwner.shouldReceiveActionTouch(
            at: touch.location(in: actionOwner),
            touchedView: touch.view
        )
    }

    func finishRecognition(succeeded: Bool) {
        primaryTouch = nil
        guard state == .possible else { return }
        state = succeeded ? .recognized : .cancelled
    }

    func cancelActiveSequence() {
        primaryTouch = nil
        actionOwner?.cancelActionInteraction(transitionRecognizer: false)
        guard state == .possible else { return }
        state = .cancelled
    }
}

@MainActor
final class ActionScrollObserver: NSObject {
    weak var owner: LYGlyphTextLabel?

    init(owner: LYGlyphTextLabel) {
        self.owner = owner
    }

    @objc func scrollPanChanged(_ recognizer: UIPanGestureRecognizer) {
        owner?.ancestorScrollDidChange(recognizer)
    }
}

@MainActor
struct ObservedScrollView {
    weak var scrollView: UIScrollView?
    weak var panGestureRecognizer: UIPanGestureRecognizer?
}
