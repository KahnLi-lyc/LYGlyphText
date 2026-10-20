@testable import LYGlyphText
import SwiftUI
import UIKit
import XCTest

@MainActor
final class ActionInteractionTests: XCTestCase {
    private final class ManualClock: ActionGestureClock {
        private final class Token: ActionGestureTimer {
            var isCancelled = false

            func cancel() {
                isCancelled = true
            }
        }

        private struct Task {
            let deadline: TimeInterval
            let sequenceID: UInt64
            let token: Token
            let handler: @MainActor (UInt64) -> Void
        }

        private(set) var now: TimeInterval = 0
        private var tasks: [Task] = []

        func schedule(
            after interval: TimeInterval,
            sequenceID: UInt64,
            handler: @escaping @MainActor (UInt64) -> Void
        ) -> ActionGestureTimer {
            let token = Token()
            tasks.append(.init(deadline: now + interval, sequenceID: sequenceID, token: token, handler: handler))
            return token
        }

        func advance(to value: TimeInterval) {
            now = value
            let ready = tasks.filter { $0.deadline <= value }
            tasks.removeAll { $0.deadline <= value }
            for task in ready where !task.token.isCancelled {
                task.handler(task.sequenceID)
            }
        }

        func fireIncludingCancelled(at index: Int) {
            let task = tasks[index]
            task.handler(task.sequenceID)
        }

        var scheduledCount: Int {
            tasks.count
        }
    }

    private final class ScrollView: UIScrollView {
        var testIsDragging = false
        var testIsDecelerating = false

        override var isDragging: Bool {
            testIsDragging
        }

        override var isDecelerating: Bool {
            testIsDecelerating
        }
    }

    private final class AttachmentMutationView: UIView {
        var onSuperviewChange: (() -> Void)?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            onSuperviewChange?()
        }
    }

    private final class AttachmentFactoryState {
        weak var label: LYGlyphTextLabel?
        var returnsView = false
        var hierarchyMutations = 0
    }

    private struct Fixture {
        let window: UIWindow
        let label: LYGlyphTextLabel
        let clock: ManualClock
    }

    private func document(
        _ source: String = "first second",
        actions: [LYGlyphTextAction]? = nil,
        viewAttachment: LYGlyphTextViewAttachment? = nil
    ) throws -> LYGlyphTextDocument {
        let text = NSAttributedString(string: source, attributes: [.font: UIFont.systemFont(ofSize: 24)])
        let actions = actions ?? [.init(actionID: "action", range: NSRange(location: 0, length: 5))]
        let attachments = viewAttachment.map { [source.utf16.count - 1: $0] } ?? [:]
        return try LYGlyphTextDocument(attributedText: text, viewAttachments: attachments, actions: actions)
    }

    private func fixture(
        document: LYGlyphTextDocument,
        onAction: @escaping @MainActor (LYGlyphTextActionEvent) -> Void = { _ in },
        container: UIView? = nil
    ) -> Fixture {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        let host = container ?? window
        if let container {
            container.frame = window.bounds
            window.addSubview(container)
        }
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 260, height: 160))
        label.document = document
        label.onAction = onAction
        let clock = ManualClock()
        label.actionClock = clock
        host.addSubview(label)
        label.setNeedsLayout()
        label.layoutIfNeeded()
        return .init(window: window, label: label, clock: clock)
    }

    private func point(_ label: LYGlyphTextLabel, actionIndex: Int = 0) throws -> CGPoint {
        let layout = label.measuredLayout(width: label.bounds.width)
        let geometry = ActionGeometry(layout: layout, bounds: label.bounds, configuration: label.configuration)
        let entry = try XCTUnwrap(geometry.entries.first { $0.actionIndex == actionIndex })
        let rect = try XCTUnwrap(entry.rects.first)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    func testTapClearsPressedStateBeforeSendingFullEventOnce() throws {
        var events: [LYGlyphTextActionEvent] = []
        var observedPressedIndex: Int?
        weak var fixtureLabel: LYGlyphTextLabel?
        let fixture = try fixture(document: document()) { event in
            events.append(event)
            observedPressedIndex = fixtureLabel?.pressedActionIndex
        }
        fixtureLabel = fixture.label
        let point = try point(fixture.label)
        XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        XCTAssertEqual(fixture.label.pressedActionIndex, 0)
        fixture.label.endActionInteraction(at: point)
        fixture.label.endActionInteraction(at: point)
        XCTAssertNil(observedPressedIndex)
        XCTAssertNil(fixture.label.pressedActionIndex)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .tap)
        XCTAssertEqual(events.first?.actionID, "action")
        XCTAssertEqual(events.first?.range, NSRange(location: 0, length: 5))
        XCTAssertFalse(events.first?.visibleRects.isEmpty ?? true)
        fixture.window.isHidden = true
    }

    func testLongPressFiresAtHalfSecondAndUpDoesNotDuplicate() throws {
        var kinds: [LYGlyphTextActionEvent.Kind] = []
        let fixture = try fixture(document: document()) { kinds.append($0.kind) }
        let point = try point(fixture.label)
        XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        fixture.clock.advance(to: 0.499)
        XCTAssertTrue(kinds.isEmpty)
        XCTAssertEqual(fixture.label.pressedActionIndex, 0)
        fixture.clock.advance(to: 0.5)
        XCTAssertEqual(kinds, [.longPress])
        XCTAssertNil(fixture.label.pressedActionIndex)
        fixture.label.endActionInteraction(at: point)
        XCTAssertEqual(kinds, [.longPress])
        fixture.window.isHidden = true
    }

    func testTimerAndUpFirstTerminalWinsAndOldTimerCannotAffectNewSequence() throws {
        var kinds: [LYGlyphTextActionEvent.Kind] = []
        let fixture = try fixture(document: document()) { kinds.append($0.kind) }
        let point = try point(fixture.label)
        XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        fixture.label.endActionInteraction(at: point)
        fixture.clock.fireIncludingCancelled(at: 0)
        XCTAssertEqual(kinds, [.tap])
        XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        fixture.clock.fireIncludingCancelled(at: 0)
        XCTAssertEqual(kinds, [.tap])
        fixture.clock.advance(to: 0.5)
        XCTAssertEqual(kinds, [.tap, .longPress])
        fixture.window.isHidden = true
    }

    func testMovementAtThresholdRemainsButOverThresholdAndLeavingCancelPermanently() throws {
        var taps = 0
        let fixture = try fixture(document: document()) { _ in taps += 1 }
        let start = try point(fixture.label)
        XCTAssertTrue(fixture.label.beginActionInteraction(at: start, touchedView: fixture.label))
        fixture.label.moveActionInteraction(to: CGPoint(x: start.x + 10, y: start.y))
        fixture.label.endActionInteraction(at: start)
        XCTAssertEqual(taps, 1)

        XCTAssertTrue(fixture.label.beginActionInteraction(at: start, touchedView: fixture.label))
        fixture.label.moveActionInteraction(to: CGPoint(x: start.x + 10.01, y: start.y))
        fixture.label.endActionInteraction(at: start)
        XCTAssertEqual(taps, 1)

        XCTAssertTrue(fixture.label.beginActionInteraction(at: start, touchedView: fixture.label))
        fixture.label.moveActionInteraction(to: CGPoint(x: fixture.label.bounds.maxX, y: fixture.label.bounds.maxY))
        fixture.label.moveActionInteraction(to: start)
        fixture.label.endActionInteraction(at: start)
        XCTAssertEqual(taps, 1)
        fixture.window.isHidden = true
    }

    func testAdjacentSameIDUsesInputOrdinalAndSecondTouchCancelsFirst() throws {
        let actions = [0, 1].map { LYGlyphTextAction(actionID: "same", range: NSRange(location: $0, length: 1)) }
        var ranges: [NSRange] = []
        let fixture = try fixture(document: document("ab", actions: actions)) { ranges.append($0.range) }
        let first = try point(fixture.label, actionIndex: 0)
        let second = try point(fixture.label, actionIndex: 1)
        XCTAssertTrue(fixture.label.beginActionInteraction(at: first, touchedView: fixture.label))
        let secondTouchButton = UIButton(type: .system)
        XCTAssertFalse(fixture.label.beginActionInteraction(at: second, touchedView: secondTouchButton))
        fixture.label.endActionInteraction(at: first)
        XCTAssertTrue(ranges.isEmpty)
        XCTAssertTrue(fixture.label.beginActionInteraction(at: second, touchedView: fixture.label))
        fixture.label.endActionInteraction(at: second)
        XCTAssertEqual(ranges, [NSRange(location: 1, length: 1)])
        fixture.window.isHidden = true
    }

    func testSecondTouchDelegatePathCancelsFirstForBlankAndButtonWithoutClaimingSecond() throws {
        let fixture = try fixture(document: document())
        let actionPoint = try point(fixture.label)
        let blankPoint = CGPoint(x: fixture.label.bounds.maxX - 1, y: fixture.label.bounds.maxY - 1)

        XCTAssertTrue(fixture.label.beginActionInteraction(at: actionPoint, touchedView: fixture.label))
        XCTAssertFalse(fixture.label.shouldReceiveActionTouch(at: blankPoint, touchedView: fixture.label))
        XCTAssertNil(fixture.label.pressedActionIndex)

        var buttonActions = 0
        let button = UIButton(type: .system, primaryAction: UIAction { _ in buttonActions += 1 })
        button.frame = CGRect(x: 200, y: 100, width: 40, height: 40)
        fixture.label.addSubview(button)
        XCTAssertTrue(fixture.label.beginActionInteraction(at: actionPoint, touchedView: fixture.label))
        XCTAssertFalse(fixture.label.shouldReceiveActionTouch(at: button.center, touchedView: button))
        XCTAssertNil(fixture.label.pressedActionIndex)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(buttonActions, 1)
        fixture.window.isHidden = true
    }

    func testLatestCallbackWinsNilCancelsAndRestoredCallbackStartsNewGesture() throws {
        var first = 0
        var second = 0
        let fixture = try fixture(document: document()) { _ in first += 1 }
        let point = try point(fixture.label)
        XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        fixture.label.onAction = { _ in second += 1 }
        fixture.label.endActionInteraction(at: point)
        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 1)

        XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        fixture.label.onAction = nil
        fixture.label.endActionInteraction(at: point)
        XCTAssertEqual(second, 1)
        fixture.label.onAction = { _ in second += 1 }
        XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        fixture.label.endActionInteraction(at: point)
        XCTAssertEqual(second, 2)
        fixture.window.isHidden = true
    }

    func testReentrantTerminalOperationsSeeIdleAndNeverDuplicate() throws {
        for operation in 0 ..< 4 {
            var calls = 0
            weak var host: LYGlyphTextLabel?
            let fixture = try fixture(document: document()) { _ in
                calls += 1
                XCTAssertNil(host?.pressedActionIndex)
                switch operation {
                case 0: host?.document = nil
                case 1: host?.onAction = nil
                case 2: host?.removeFromSuperview()
                default: host?.clearForDismantle()
                }
            }
            host = fixture.label
            let point = try point(fixture.label)
            XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
            fixture.label.endActionInteraction(at: point)
            fixture.clock.advance(to: 1)
            XCTAssertEqual(calls, 1)
            fixture.window.isHidden = true
        }
    }

    func testDocumentGeometryProviderTraitHierarchyAndSystemCancellationProduceNoEvent() throws {
        typealias Mutation = @MainActor (LYGlyphTextLabel) throws -> Void
        let mutations: [Mutation] = [
            { $0.document = try self.document("replacement") },
            { $0.document = nil },
            { $0.bounds.origin.x += 1 },
            { $0.bounds.size.width -= 1 },
            { $0.configuration.numberOfLines = 1 },
            { $0.configuration.textContainerInset.top = 1 },
            { $0.configuration.wrapping = .character },
            { $0.configuration.verticalAlignment = .bottom },
            { $0.traitCollectionDidChange(nil) },
            { $0.viewProvider = .init { _ in nil } },
            { $0.reloadAttachments() },
            { $0.removeFromSuperview() },
            { $0.cancelActionInteraction() }
        ]
        for mutate in mutations {
            var events = 0
            let fixture = try fixture(document: document()) { _ in events += 1 }
            let point = try point(fixture.label)
            XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
            try mutate(fixture.label)
            fixture.label.endActionInteraction(at: point)
            fixture.clock.advance(to: 1)
            XCTAssertEqual(events, 0)
            XCTAssertNil(fixture.label.pressedActionIndex)
            fixture.window.isHidden = true
        }
    }

    func testEquivalentInputsAndUnchangedLayoutDoNotCancel() throws {
        var taps = 0
        let doc = try document()
        let fixture = fixture(document: doc) { _ in taps += 1 }
        let point = try point(fixture.label)
        XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        fixture.label.document = doc
        fixture.label.configuration = fixture.label.configuration
        fixture.label.viewProvider = fixture.label.viewProvider
        fixture.label.layoutIfNeeded()
        fixture.label.endActionInteraction(at: point)
        XCTAssertEqual(taps, 1)
        fixture.window.isHidden = true
    }

    func testEquivalentNonNilProviderDoesNotCancel() throws {
        var taps = 0
        let fixture = try fixture(document: document()) { _ in taps += 1 }
        let provider = LYGlyphTextAttachmentViewProvider { _ in nil }
        fixture.label.viewProvider = provider
        let point = try point(fixture.label)
        XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        fixture.label.viewProvider = provider
        fixture.label.endActionInteraction(at: point)
        XCTAssertEqual(taps, 1)
        fixture.window.isHidden = true
    }

    func testInteractiveMountedViewIsRejectedButNilFactoryPlaceholderRemainsActionable() throws {
        let descriptor = LYGlyphTextViewAttachment(
            id: "view",
            viewID: "button",
            size: CGSize(width: 40, height: 30),
            isInteractive: true
        )
        let document = try document(
            "A\u{FFFC}",
            actions: [.init(actionID: "attachment", range: NSRange(location: 1, length: 1))],
            viewAttachment: descriptor
        )
        var taps = 0
        let mounted = fixture(document: document) { _ in taps += 1 }
        let button = UIButton(type: .system)
        mounted.label.viewProvider = .init { _ in button }
        mounted.label.layoutIfNeeded()
        let point = try point(mounted.label)
        XCTAssertFalse(mounted.label.beginActionInteraction(at: point, touchedView: button))
        mounted.window.isHidden = true

        let placeholder = fixture(document: document) { _ in taps += 1 }
        placeholder.label.viewProvider = .init { _ in nil }
        placeholder.label.layoutIfNeeded()
        let placeholderPoint = try self.point(placeholder.label)
        XCTAssertTrue(placeholder.label.beginActionInteraction(at: placeholderPoint, touchedView: placeholder.label))
        placeholder.label.endActionInteraction(at: placeholderPoint)
        XCTAssertEqual(taps, 1)
        placeholder.window.isHidden = true
    }

    func testAttachmentReceiverChangesCancelBeforeViewHierarchyMutation() throws {
        let descriptor = LYGlyphTextViewAttachment(
            id: "view",
            viewID: "badge",
            size: CGSize(width: 40, height: 30)
        )
        let attachmentDocument = try document(
            "A\u{FFFC}",
            actions: [.init(actionID: "attachment", range: NSRange(location: 1, length: 1))],
            viewAttachment: descriptor
        )
        let fixture = fixture(document: attachmentDocument)
        let state = AttachmentFactoryState()
        state.label = fixture.label
        let provider = LYGlyphTextAttachmentViewProvider { _ in
            guard state.returnsView else { return nil }
            let view = AttachmentMutationView()
            view.onSuperviewChange = {
                state.hierarchyMutations += 1
                XCTAssertNil(state.label?.pressedActionIndex)
            }
            return view
        }
        fixture.label.viewProvider = provider
        fixture.label.layoutIfNeeded()
        let point = try point(fixture.label)

        XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        state.returnsView = true
        fixture.label.reloadAttachments()
        fixture.label.layoutIfNeeded()
        XCTAssertNil(fixture.label.pressedActionIndex)
        XCTAssertEqual(state.hierarchyMutations, 1)

        XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        fixture.label.reloadAttachments()
        fixture.label.layoutIfNeeded()
        XCTAssertNil(fixture.label.pressedActionIndex)
        XCTAssertGreaterThanOrEqual(state.hierarchyMutations, 3)
        fixture.window.isHidden = true
    }

    func testSingleRecognizerPolicyAndOrdinaryRegionsRemainUnclaimed() throws {
        var taps = 0
        let fixture = try fixture(document: document()) { _ in taps += 1 }
        let recognizers = fixture.label.gestureRecognizers?.compactMap { $0 as? ActionGestureRecognizer } ?? []
        XCTAssertEqual(recognizers.count, 1)
        let recognizer = try XCTUnwrap(recognizers.first)
        XCTAssertFalse(recognizer.delaysTouchesBegan)
        XCTAssertTrue(recognizer.delaysTouchesEnded)
        XCTAssertTrue(recognizer.cancelsTouchesInView)

        let actionPoint = try point(fixture.label)
        let layout = fixture.label.measuredLayout(width: fixture.label.bounds.width)
        let geometry = ActionGeometry(
            layout: layout,
            bounds: fixture.label.bounds,
            configuration: fixture.label.configuration
        )
        let actionRects = try XCTUnwrap(geometry.entries.first?.rects)
        let actionRect = actionRects.reduce(CGRect.null) { $0.union($1) }
        let blank = CGPoint(x: min(fixture.label.bounds.maxX - 1, actionRect.maxX + 30), y: actionRect.midY)
        XCTAssertNil(geometry.hit(at: blank))
        XCTAssertFalse(fixture.label.beginActionInteraction(at: blank, touchedView: fixture.label))
        fixture.label.onAction = nil
        XCTAssertFalse(fixture.label.beginActionInteraction(at: actionPoint, touchedView: fixture.label))
        XCTAssertEqual(taps, 0)
        fixture.window.isHidden = true
    }

    func testAncestorScrollStateRejectsStartAndNestedScrollCancellationUnbindsObservers() throws {
        let outer = ScrollView()
        let inner = ScrollView()
        outer.addSubview(inner)
        inner.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        let fixture = try fixture(document: document(), container: outer)
        inner.addSubview(fixture.label)
        let point = try point(fixture.label)
        outer.testIsDragging = true
        XCTAssertFalse(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        outer.testIsDragging = false
        outer.testIsDecelerating = true
        XCTAssertFalse(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        outer.testIsDecelerating = false
        XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        XCTAssertEqual(fixture.label.observedScrollViewCount, 2)
        inner.testIsDragging = true
        fixture.label.ancestorScrollDidChange(inner.panGestureRecognizer)
        XCTAssertNil(fixture.label.pressedActionIndex)
        XCTAssertEqual(fixture.label.observedScrollViewCount, 0)
        fixture.label.endActionInteraction(at: point)
        fixture.window.isHidden = true
    }

    func testSameWindowAncestorScrollReparentCancelsAndDoesNotKeepStaleTargets() throws {
        var events = 0
        let bridge = UIView()
        let fixture = try fixture(document: document(), onAction: { _ in events += 1 }, container: bridge)
        let first = ScrollView(frame: fixture.window.bounds)
        let second = ScrollView(frame: fixture.window.bounds)
        fixture.window.addSubview(first)
        fixture.window.addSubview(second)
        first.addSubview(bridge)
        let point = try point(fixture.label)

        XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        XCTAssertEqual(fixture.label.observedScrollViewCount, 1)
        second.addSubview(bridge)
        XCTAssertTrue(fixture.label.window === fixture.window)
        XCTAssertNotNil(fixture.label.pressedActionIndex)
        fixture.label.moveActionInteraction(to: point)
        XCTAssertNil(fixture.label.pressedActionIndex)
        XCTAssertEqual(fixture.label.observedScrollViewCount, 0)
        fixture.label.endActionInteraction(at: point)
        XCTAssertEqual(events, 0)

        XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        XCTAssertEqual(fixture.label.observedScrollViewCount, 1)
        first.testIsDragging = true
        fixture.label.ancestorScrollDidChange(first.panGestureRecognizer)
        XCTAssertNotNil(fixture.label.pressedActionIndex)
        second.testIsDragging = true
        fixture.label.ancestorScrollDidChange(second.panGestureRecognizer)
        XCTAssertNil(fixture.label.pressedActionIndex)
        XCTAssertEqual(fixture.label.observedScrollViewCount, 0)
        fixture.clock.advance(to: 1)
        XCTAssertEqual(events, 0)
        fixture.window.isHidden = true
    }

    func testSameWindowAncestorScrollReparentAlsoCancelsOnTimerAndUp() throws {
        for terminal in 0 ..< 2 {
            var events = 0
            let bridge = UIView()
            let fixture = try fixture(document: document(), onAction: { _ in events += 1 }, container: bridge)
            let first = ScrollView(frame: fixture.window.bounds)
            let second = ScrollView(frame: fixture.window.bounds)
            fixture.window.addSubview(first)
            fixture.window.addSubview(second)
            first.addSubview(bridge)
            let point = try point(fixture.label)
            XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
            second.addSubview(bridge)

            if terminal == 0 {
                fixture.clock.advance(to: 0.5)
            } else {
                fixture.label.endActionInteraction(at: point)
            }
            XCTAssertNil(fixture.label.pressedActionIndex)
            XCTAssertEqual(fixture.label.observedScrollViewCount, 0)
            XCTAssertEqual(events, 0)
            fixture.window.isHidden = true
        }
    }

    func testTerminalRecognizerNeverPreventsAncestorPanAfterObserversUnbind() throws {
        let scroll = ScrollView()
        let fixture = try fixture(document: document(), container: scroll)
        let point = try point(fixture.label)
        let recognizer = try XCTUnwrap(
            fixture.label.gestureRecognizers?.compactMap { $0 as? ActionGestureRecognizer }.first
        )
        XCTAssertTrue(fixture.label.beginActionInteraction(
            at: point,
            touchedView: fixture.label,
            fromRecognizer: true
        ))
        XCTAssertFalse(recognizer.canPrevent(scroll.panGestureRecognizer))
        fixture.label.endActionInteraction(at: point)
        XCTAssertEqual(fixture.label.observedScrollViewCount, 0)
        XCTAssertFalse(recognizer.canPrevent(scroll.panGestureRecognizer))
        fixture.window.isHidden = true
    }

    func testAncestorWindowRemovalCancelsWithoutRemovingLabelFromSuperview() throws {
        let container = UIView()
        let fixture = try fixture(document: document(), container: container)
        let point = try point(fixture.label)
        XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        container.removeFromSuperview()
        XCTAssertNil(fixture.label.window)
        XCTAssertTrue(fixture.label.superview === container)
        XCTAssertNil(fixture.label.pressedActionIndex)
        fixture.label.endActionInteraction(at: point)
    }

    func testInteractionTimerAndScrollObservationDoNotRetainLabelOrClosureOwner() {
        final class Owner {
            var calls = 0
        }
        let clock = ManualClock()
        weak var weakLabel: LYGlyphTextLabel?
        weak var weakOwner: Owner?
        autoreleasepool {
            let owner = Owner()
            weakOwner = owner
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.isHidden = false
            let scroll = UIScrollView(frame: window.bounds)
            window.addSubview(scroll)
            let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 260, height: 160))
            label.document = try? document()
            label.onAction = { [weak owner] _ in owner?.calls += 1 }
            label.actionClock = clock
            scroll.addSubview(label)
            label.layoutIfNeeded()
            weakLabel = label
            if let point = try? self.point(label) {
                XCTAssertTrue(label.beginActionInteraction(at: point, touchedView: label))
            }
            label.removeFromSuperview()
            label.onAction = nil
            window.isHidden = true
        }
        XCTAssertNil(weakLabel)
        XCTAssertNil(weakOwner)
        clock.advance(to: 1)
    }

    func testSwiftUIUpdatesLatestCallbackAndDismantleIsAtomicAgainstUnmountReentry() throws {
        let descriptor = LYGlyphTextViewAttachment(id: "view", viewID: "badge", size: CGSize(width: 30, height: 20))
        let document = try document(
            "A\u{FFFC}",
            actions: [.init(actionID: "all", range: NSRange(location: 0, length: 2))],
            viewAttachment: descriptor
        )
        var first = 0
        var second = 0
        weak var hostLabel: LYGlyphTextLabel?
        let provider = LYGlyphTextAttachmentViewProvider(makeView: { _ in UIView() }, onUnmount: { _, _ in
            hostLabel?.onAction = { _ in XCTFail("拆卸回调不能恢复 action") }
            hostLabel?.document = document
            hostLabel?.viewProvider = .init { _ in UIView() }
        })
        let host = UIHostingController(rootView: LYGlyphTextView(
            document: document,
            viewProvider: provider,
            displayHeight: 100,
            onAction: { _ in first += 1 }
        ).frame(width: 260))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        host.loadViewIfNeeded()
        host.view.frame = window.bounds
        window.addSubview(host.view)
        window.isHidden = false
        host.view.layoutIfNeeded()
        let label = try XCTUnwrap(findLabel(host.view))
        hostLabel = label
        label.actionClock = ManualClock()
        let point = try point(label)
        XCTAssertTrue(label.beginActionInteraction(at: point, touchedView: label))
        host.rootView = LYGlyphTextView(
            document: document,
            viewProvider: provider,
            displayHeight: 100,
            onAction: { _ in second += 1 }
        ).frame(width: 260)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        label.endActionInteraction(at: point)
        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 1)

        LYGlyphTextView.dismantleUIView(label, coordinator: ())
        LYGlyphTextView.dismantleUIView(label, coordinator: ())
        XCTAssertNil(label.onAction)
        XCTAssertNil(label.document)
        XCTAssertNil(label.viewProvider)
        XCTAssertNil(label.pressedActionIndex)
        window.isHidden = true
    }

    func testPressedDrawKeepsCachedLayoutAndAuthoritativeLines() throws {
        let fixture = try fixture(document: document())
        let point = try point(fixture.label)
        let before = fixture.label.measuredLayout(width: fixture.label.bounds.width)
        let lines = before.lines.map(\.text)
        let renderer = UIGraphicsImageRenderer(bounds: fixture.label.bounds)
        XCTAssertTrue(fixture.label.beginActionInteraction(at: point, touchedView: fixture.label))
        _ = renderer.image { _ in fixture.label.draw(fixture.label.bounds) }
        fixture.label.cancelActionInteraction()
        _ = renderer.image { _ in fixture.label.draw(fixture.label.bounds) }
        let after = fixture.label.measuredLayout(width: fixture.label.bounds.width)
        XCTAssertEqual(lines.count, after.lines.count)
        for (original, current) in zip(lines, after.lines.map(\.text)) {
            XCTAssertTrue(original === current)
        }
        fixture.window.isHidden = true
    }

    private func findLabel(_ view: UIView) -> LYGlyphTextLabel? {
        if let label = view as? LYGlyphTextLabel { return label }
        return view.subviews.lazy.compactMap(findLabel).first
    }
}
