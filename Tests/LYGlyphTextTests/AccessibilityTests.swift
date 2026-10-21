import CoreText
@testable import LYGlyphText
import UIKit
import XCTest

@MainActor
final class AccessibilityTests: XCTestCase {
    private struct Fixture {
        let window: UIWindow
        let label: LYGlyphTextLabel
    }

    private func document(
        _ source: String = "first second",
        actions: [LYGlyphTextAction]? = nil,
        views: [Int: LYGlyphTextViewAttachment] = [:],
        images: [Int: LYGlyphTextAttachment] = [:]
    ) throws -> LYGlyphTextDocument {
        try .init(
            attributedText: NSAttributedString(string: source, attributes: [.font: UIFont.systemFont(ofSize: 24)]),
            attachments: images,
            viewAttachments: views,
            actions: actions ?? [.init(actionID: "action", range: NSRange(location: 0, length: source.utf16.count))]
        )
    }

    private func fixture(
        _ document: LYGlyphTextDocument,
        width: CGFloat = 260,
        height: CGFloat = 160,
        provider: LYGlyphTextAttachmentViewProvider? = nil
    ) -> Fixture {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        let label = LYGlyphTextLabel(frame: CGRect(x: 10, y: 20, width: width, height: height))
        label.document = document
        label.viewProvider = provider
        label.onAction = { _ in }
        window.addSubview(label)
        label.layoutIfNeeded()
        return .init(window: window, label: label)
    }

    private func elements(_ label: LYGlyphTextLabel) -> [UIAccessibilityElement] {
        (label.accessibilityElements ?? []).compactMap { $0 as? UIAccessibilityElement }
    }

    private func labels(_ label: LYGlyphTextLabel) -> [String] {
        elements(label).compactMap(\.accessibilityLabel)
    }

    func testVisibleSemanticsExcludeTokenAndHiddenSource() throws {
        let f = try fixture(document("visible words and hidden secret"), width: 110)
        f.label.configuration.numberOfLines = 1
        f.label.layoutIfNeeded()
        let read = labels(f.label).joined()
        XCTAssertFalse(read.isEmpty)
        XCTAssertFalse(read.contains("…"))
        XCTAssertFalse(read.contains("secret"))
        f.window.isHidden = true
    }

    func testLogicalOrderIncludesEmojiRTLAndAlternativeTextOnce() throws {
        let source = "A👨‍👩‍👧‍👦אב\u{FFFC}Z"
        let location = (source as NSString).range(of: "\u{FFFC}").location
        let image = LYGlyphTextAttachment(
            id: "image",
            image: UIImage(),
            size: CGSize(width: 20, height: 20),
            alternativeText: "photo"
        )
        let f = try fixture(document(source, images: [location: image]), width: 380)
        XCTAssertEqual(labels(f.label), ["A👨‍👩‍👧‍👦אב", "photo", "Z"])
        f.window.isHidden = true
    }

    func testInteractiveAttachmentAppearsOnceInActionRange() throws {
        let descriptor = LYGlyphTextViewAttachment(
            id: "v",
            viewID: "button",
            size: CGSize(width: 50, height: 30),
            alternativeText: "native",
            isInteractive: true
        )
        let button = UIButton(type: .system)
        button.setTitle("native", for: .normal)
        let f = try fixture(document("A\u{FFFC}B", views: [1: descriptor]), provider: .init { _ in button })
        let all = try XCTUnwrap(f.label.accessibilityElements)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual((all[0] as? UIAccessibilityElement)?.accessibilityLabel, "A")
        XCTAssertTrue((all[1] as? UIView) === button)
        XCTAssertEqual((all[2] as? UIAccessibilityElement)?.accessibilityLabel, "B")
        f.window.isHidden = true
    }

    func testAccessibilityActivationReadsLatestCallback() throws {
        let f = try fixture(document())
        let element = try XCTUnwrap(elements(f.label).first)
        var first = 0
        var latest: [LYGlyphTextActionEvent] = []
        f.label.onAction = { _ in first += 1 }
        f.label.onAction = { latest.append($0) }
        f.label.resetLayoutMeasurementCounts()
        XCTAssertTrue(element.accessibilityActivate())
        XCTAssertEqual(first, 0)
        XCTAssertEqual(latest.first?.range, NSRange(location: 0, length: 12))
        XCTAssertFalse(try XCTUnwrap(latest.first).visibleRects.isEmpty)
        f.label.onAction = nil
        XCTAssertFalse(element.accessibilityTraits.contains(.button))
        XCTAssertFalse(element.accessibilityActivate())
        f.label.onAction = { latest.append($0) }
        XCTAssertTrue(element.accessibilityTraits.contains(.button))
        XCTAssertTrue(element.accessibilityActivate())
        XCTAssertEqual(latest.count, 2)
        XCTAssertEqual(f.label.layoutMeasurementSnapshot.layoutBuildCount, 0)
        f.window.isHidden = true
    }

    func testOldElementCannotActivateAfterReload() throws {
        let f = try fixture(document())
        let old = try XCTUnwrap(elements(f.label).first)
        var calls = 0
        f.label.onAction = { _ in calls += 1 }
        f.label.reloadAttachments()
        f.label.layoutIfNeeded()
        XCTAssertFalse(old.accessibilityActivate())
        XCTAssertTrue(try XCTUnwrap(elements(f.label).first).accessibilityActivate())
        XCTAssertEqual(calls, 1)
        f.window.isHidden = true
    }

    func testOldElementsInvalidateAcrossLifecycleChanges() throws {
        typealias Mutation = @MainActor (LYGlyphTextLabel) throws -> Void
        let mutations: [Mutation] = [
            { $0.document = try self.document("new") }, { $0.document = nil },
            { $0.bounds.origin.x += 1 }, { $0.bounds.size.height -= 1 },
            { $0.configuration.verticalAlignment = .bottom }, { $0.traitCollectionDidChange(nil) },
            { $0.viewProvider = .init { _ in nil } }, { $0.removeFromSuperview() }, { $0.clearForDismantle() }
        ]
        for mutate in mutations {
            let f = try fixture(document())
            let old = try XCTUnwrap(elements(f.label).first)
            try mutate(f.label)
            f.label.layoutIfNeeded()
            XCTAssertFalse(old.accessibilityActivate())
            XCTAssertTrue(old.accessibilityFrame.isEmpty)
            f.window.isHidden = true
        }
    }

    func testActivationReentrySendsOnce() throws {
        let f = try fixture(document())
        var calls = 0
        f.label.onAction = { _ in
            calls += 1
            if calls == 1 {
                f.label.reloadAttachments()
                f.label.layoutIfNeeded()
                XCTAssertFalse(self.elements(f.label).first?.accessibilityActivate() ?? true)
            }
        }
        XCTAssertTrue(try XCTUnwrap(elements(f.label).first).accessibilityActivate())
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(try XCTUnwrap(elements(f.label).first).accessibilityActivate())
        XCTAssertEqual(calls, 2)
        f.label.onAction = nil
        f.window.isHidden = true
    }

    func testAccessibilityQueryDoesNotMountAttachments() throws {
        var calls = 0
        let descriptor = LYGlyphTextViewAttachment(
            id: "v",
            viewID: "v",
            size: CGSize(width: 30, height: 30),
            alternativeText: "alt"
        )
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        label.document = try document("\u{FFFC}", views: [0: descriptor])
        label.viewProvider = .init { _ in calls += 1
            return UIView()
        }
        label.resetLayoutMeasurementCounts()
        for _ in 0 ..< 3 {
            _ = label.accessibilityElements
        }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(label.layoutMeasurementSnapshot.layoutBuildCount, 0)
        let f = try fixture(document("\u{FFFC}", views: [0: descriptor]), provider: label.viewProvider)
        let before = calls
        f.label.resetLayoutMeasurementCounts()
        for _ in 0 ..< 3 {
            for element in elements(f.label) {
                _ = element.accessibilityFrame
                _ = element.accessibilityPath
            }
        }
        XCTAssertEqual(calls, before)
        XCTAssertEqual(f.label.layoutMeasurementSnapshot.layoutBuildCount, 0)
        f.window.isHidden = true
    }

    func testAccessibilityPathTracksAncestorScroll() throws {
        let f = try fixture(document("first\nsecond"))
        let scroll = UIScrollView(frame: f.window.bounds)
        scroll.contentSize = CGSize(width: 390, height: 2000)
        f.window.addSubview(scroll)
        scroll.addSubview(f.label)
        f.label.layoutIfNeeded()
        let element = try XCTUnwrap(elements(f.label).first)
        let frame = element.accessibilityFrame
        let path = try XCTUnwrap(element.accessibilityPath).bounds
        f.label.resetLayoutMeasurementCounts()
        let beforeView = f.label.convert(f.label.bounds, to: f.window)
        let beforeWindow = f.window.convert(beforeView, to: nil as UIWindow?)
        scroll.contentOffset.y = 40
        let afterWindow = f.window.convert(f.label.convert(f.label.bounds, to: f.window), to: nil as UIWindow?)
        print("A1b UIWindow-specific diagnostic: before=\(beforeWindow), after=\(afterWindow)")
        XCTAssertEqual(afterWindow.minY, beforeWindow.minY - 40, accuracy: 0.01)
        print(
            "A1b coordinate diagnostic: scene=\(String(describing: f.window.windowScene)); UIView before=\(beforeView); UIView after=\(f.label.convert(f.label.bounds, to: f.window)); AX frame before=\(frame); AX frame after=\(element.accessibilityFrame)"
        )
        XCTAssertEqual(element.accessibilityFrame.minY, frame.minY - 40, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(element.accessibilityPath).bounds.minY, path.minY - 40, accuracy: 0.01)
        XCTAssertEqual(f.label.layoutMeasurementSnapshot.layoutBuildCount, 0)
        f.window.isHidden = true
    }

    func testHostAccessibilityOverridesSurviveUpdates() throws {
        let f = try fixture(document())
        XCTAssertFalse(f.label.isAccessibilityElement)
        f.label.isAccessibilityElement = true
        f.label.accessibilityLabel = "host"
        f.label.accessibilityHint = "hint"
        f.label.accessibilityTraits = .header
        f.label.accessibilityElementsHidden = true
        let host = NSObject()
        f.label.accessibilityElements = [host]
        f.label.document = try document("replacement")
        f.label.layoutIfNeeded()
        XCTAssertTrue(f.label.isAccessibilityElement)
        XCTAssertEqual(f.label.accessibilityLabel, "host")
        XCTAssertEqual(f.label.accessibilityHint, "hint")
        XCTAssertEqual(f.label.accessibilityTraits, .header)
        XCTAssertTrue(f.label.accessibilityElementsHidden)
        XCTAssertTrue((f.label.accessibilityElements?.first as? NSObject) === host)
        f.label.accessibilityElements = []
        XCTAssertEqual(f.label.accessibilityElements?.count, 0)
        f.label.accessibilityElements = nil
        XCTAssertEqual(labels(f.label), ["replacement"])
        f.window.isHidden = true
    }

    func testPartiallyClippedNativeButtonAccessibility() throws {
        let descriptor = LYGlyphTextViewAttachment(
            id: "v",
            viewID: "v",
            size: CGSize(width: 80, height: 40),
            alternativeText: "alt",
            isInteractive: true
        )
        let button = UIButton(type: .system)
        button.accessibilityLabel = "native button"
        let f = try fixture(
            document("\u{FFFC}", views: [0: descriptor]),
            width: 40,
            height: 20,
            provider: .init { _ in button }
        )
        XCTAssertEqual(f.label.accessibilityElements?.count, 1)
        XCTAssertTrue((f.label.accessibilityElements?.first as? UIView) === button)
        XCTAssertEqual(button.accessibilityLabel, "native button")
        XCTAssertEqual(button.frame.size, descriptor.size)
        // UIKit 原生子树保留完整声明 frame；任意后代 AX frame 不保证裁到 Label 的可见区。
        print(
            "A1b native partial clip: native frame=\(button.frame), screen AX=\(button.accessibilityFrame), host=\(f.label.bounds)"
        )
        f.label.bounds.size.height = 0
        f.label.layoutIfNeeded()
        XCTAssertEqual(f.label.accessibilityElements?.count, 0)
        f.window.isHidden = true
    }

    func testNativeOnlyDecorationOnlyAndFailedFactoryFallback() throws {
        for alt in [nil, "", "fallback"] as [String?] {
            let d = LYGlyphTextViewAttachment(
                id: "v",
                viewID: "v",
                size: CGSize(width: 40, height: 30),
                alternativeText: alt,
                isInteractive: true
            )
            let button = UIButton(type: .system)
            let native = try fixture(document("\u{FFFC}", views: [0: d]), provider: .init { _ in button })
            XCTAssertTrue(elements(native.label).isEmpty)
            XCTAssertTrue((native.label.accessibilityElements?.first as? UIView) === button)
            native.window.isHidden = true
            let fallback = try fixture(document("\u{FFFC}", views: [0: d]), provider: .init { _ in nil })
            XCTAssertEqual(labels(fallback.label), alt == "fallback" ? ["fallback"] : [])
            fallback.window.isHidden = true
        }
    }

    func testNoninteractiveNativeSubtreeUsesOnlyDeclaredAlternative() throws {
        let d = LYGlyphTextViewAttachment(
            id: "v",
            viewID: "v",
            size: CGSize(width: 40, height: 30),
            alternativeText: "declared"
        )
        let button = UIButton(type: .system)
        button.accessibilityLabel = "unchanged"
        button.accessibilityTraits = .header
        let f = try fixture(document("\u{FFFC}", views: [0: d]), provider: .init { _ in button })
        XCTAssertEqual(labels(f.label), ["declared"])
        XCTAssertFalse(f.label.accessibilityElements?.contains { ($0 as? UIView) === button } ?? true)
        XCTAssertEqual(button.accessibilityLabel, "unchanged")
        XCTAssertEqual(button.accessibilityTraits, .header)
        f.window.isHidden = true
    }

    func testDuplicateActionIDsRemainIndependentAndClearPressBeforeActivation() throws {
        let actions = [
            LYGlyphTextAction(actionID: "same", range: NSRange(location: 0, length: 1)),
            LYGlyphTextAction(actionID: "same", range: NSRange(location: 2, length: 1))
        ]
        let f = try fixture(document("A B", actions: actions))
        let all = elements(f.label).filter { $0.accessibilityTraits.contains(.button) }
        XCTAssertEqual(all.count, 2)
        var ranges: [NSRange] = []
        f.label.onAction = { event in XCTAssertNil(f.label.pressedActionIndex)
            ranges.append(event.range)
        }
        let layout = f.label.measuredLayout(width: f.label.bounds.width)
        let rect = try XCTUnwrap(ActionGeometry(
            layout: layout,
            bounds: f.label.bounds,
            configuration: f.label.configuration
        ).entries.first?.rects.first)
        XCTAssertTrue(f.label.beginActionInteraction(at: CGPoint(x: rect.midX, y: rect.midY), touchedView: f.label))
        for element in all {
            XCTAssertTrue(element.accessibilityActivate())
        }
        XCTAssertEqual(ranges, actions.map(\.range))
        f.label.onAction = nil
        f.window.isHidden = true
    }

    func testNewlineGapsNormalizeButSoftWrapAddsNoSpace() throws {
        for source in ["A\nB", "A\r\nB", "A\n\nB"] {
            let f = try fixture(document(source))
            XCTAssertEqual(labels(f.label), ["A B"])
            f.window.isHidden = true
        }
        let f = try fixture(document("AB"), width: 18)
        f.label.configuration.wrapping = .character
        f.label.layoutIfNeeded()
        XCTAssertEqual(labels(f.label), ["AB"])
        f.window.isHidden = true
    }

    func testPartialGraphemeClippingRetainsWholeEmojiAndClipsGeometry() throws {
        for vertical in [false, true] {
            let f = try fixture(document("👨‍👩‍👧‍👦"), width: 100)
            let layout = f.label.measuredLayout(width: 100)
            let rect = try XCTUnwrap(layout.sourceGeometry?.cells.first?.pieces.first?.rect)
            if vertical { f.label.bounds.size.height = rect.midY }
            else { f.label.bounds.size.width = rect.midX }
            f.label.layoutIfNeeded()
            XCTAssertEqual(labels(f.label), ["👨‍👩‍👧‍👦"])
            let element = try XCTUnwrap(elements(f.label).first)
            let local = f.window.convert(
                f.label.convert(f.label.bounds, to: f.window),
                to: nil as UIWindow?
            )
            XCTAssertTrue(local.contains(element.accessibilityFrame))
            f.window.isHidden = true
        }
    }

    func testVerticalAlignmentNonzeroBoundsAndRTLUseDisplayGeometry() throws {
        for alignment in [LYGlyphTextConfiguration.VerticalAlignment.top, .center, .bottom] {
            let f = try fixture(document("אב👋", actions: []))
            f.label.semanticContentAttribute = .forceRightToLeft
            f.label.configuration.verticalAlignment = alignment
            f.label.bounds.origin = CGPoint(x: 7, y: 11)
            f.label.layoutIfNeeded()
            XCTAssertEqual(labels(f.label), ["אב👋"])
            let element = try XCTUnwrap(elements(f.label).first)
            let clip = f.window.convert(
                f.label.convert(f.label.bounds, to: f.window),
                to: nil as UIWindow?
            )
            XCTAssertTrue(clip.contains(element.accessibilityFrame))
            XCTAssertEqual(element.accessibilityTraits, .staticText)
            f.window.isHidden = true
        }
    }

    func testElementWeakOwnerAndTwoHostsAreIndependent() throws {
        let doc = try document()
        var retained: UIAccessibilityElement?
        weak var weakLabel: LYGlyphTextLabel?
        autoreleasepool {
            let f = fixture(doc)
            weakLabel = f.label
            retained = elements(f.label).first
            f.label.removeFromSuperview()
            f.window.isHidden = true
        }
        XCTAssertNil(weakLabel)
        XCTAssertFalse(retained?.accessibilityActivate() ?? true)
        let first = fixture(doc)
        let second = fixture(doc)
        let old = try XCTUnwrap(elements(first.label).first)
        let live = try XCTUnwrap(elements(second.label).first)
        first.label.reloadAttachments()
        XCTAssertFalse(old.accessibilityActivate())
        XCTAssertTrue(live.accessibilityActivate())
        first.window.isHidden = true
        second.window.isHidden = true
    }

    func testReentrantFactoryDoesNotPublishObsoleteSnapshot() throws {
        let d = LYGlyphTextViewAttachment(
            id: "v",
            viewID: "v",
            size: CGSize(width: 30, height: 30),
            alternativeText: "obsolete"
        )
        let f = try fixture(document("\u{FFFC}", views: [0: d]))
        f.label.viewProvider = .init { [weak label = f.label] _ in
            label?.document = try? self.document("current")
            return UIView()
        }
        f.label.layoutIfNeeded()
        XCTAssertFalse(labels(f.label).contains("obsolete"))
        f.label.layoutIfNeeded()
        XCTAssertEqual(labels(f.label), ["current"])
        f.window.isHidden = true
    }

    func testInvalidationReleasesNativeSnapshotBeforeAnotherLayout() throws {
        typealias Mutation = @MainActor (LYGlyphTextLabel) -> Void
        let mutations: [Mutation] = [
            { $0.document = nil }, { $0.reloadAttachments() }, { $0.viewProvider = nil },
            { $0.removeFromSuperview() }, { $0.clearForDismantle() }
        ]
        let descriptor = LYGlyphTextViewAttachment(
            id: "v",
            viewID: "v",
            size: CGSize(width: 30, height: 30),
            isInteractive: true
        )
        for mutate in mutations {
            weak var native: UIView?
            var retained: Fixture?
            try autoreleasepool {
                let f = try fixture(document("\u{FFFC}", views: [0: descriptor]), provider: .init { _ in
                    let button = UIButton(type: .system)
                    native = button
                    return button
                })
                retained = f
                XCTAssertNotNil(native)
                mutate(f.label)
            }
            XCTAssertNil(native)
            XCTAssertNotNil(retained?.label)
            retained?.window.isHidden = true
        }
    }

    func testWhitespaceAlternativeIsDecorative() throws {
        for alt in [nil, "", " \t\n"] as [String?] {
            let image = LYGlyphTextAttachment(
                id: "i",
                image: UIImage(),
                size: CGSize(width: 20, height: 20),
                alternativeText: alt
            )
            let f = try fixture(document("\u{FFFC}", images: [0: image]))
            XCTAssertTrue(labels(f.label).isEmpty)
            f.window.isHidden = true
        }
    }

    func testHiddenSourceGapSplitsWithoutReadingBody() throws {
        let doc = try document("AsecretB")
        let original = ResolvedText(document: doc, traits: UITraitCollection()).layout(
            width: 300,
            insets: .zero,
            scale: 2,
            numberOfLines: 0
        )
        let line = try XCTUnwrap(original.lines.first)
        let clipped = LYGlyphTextLayout(
            size: original.size,
            lines: [.init(
                text: line.text,
                baseline: line.baseline,
                visibleSourceRanges: [
                    NSRange(location: 0, length: 1),
                    NSRange(location: 7, length: 1)
                ],
                sourceOffset: 0,
                truncationTokenRange: nil
            )],
            source: doc.string,
            actions: doc.actions
        )
        let semantics = TextAccessibility(
            layout: clipped,
            document: doc,
            bounds: CGRect(x: 0, y: 0, width: 300, height: 100),
            configuration: .init(),
            nativeViews: [:]
        )
        XCTAssertEqual(semantics.items.compactMap { item in
            if case let .text(entry) = item { return entry.label }
            return nil
        }, ["A", "B"])
    }

    func testActivationRejectsHiddenAncestorsAndHostOverrides() throws {
        typealias Mutation = @MainActor (LYGlyphTextLabel) -> Void
        let mutations: [Mutation] = [
            { $0.isHidden = true }, { $0.alpha = 0 }, { $0.superview?.isHidden = true },
            { $0.superview?.alpha = 0 }, { $0.superview?.accessibilityElementsHidden = true },
            { $0.isAccessibilityElement = true }, { $0.accessibilityElements = [] },
            { $0.accessibilityElements = [NSObject()] }
        ]
        for mutate in mutations {
            let f = try fixture(document())
            let element = try XCTUnwrap(elements(f.label).first)
            var calls = 0
            f.label.onAction = { _ in calls += 1 }
            mutate(f.label)
            XCTAssertFalse(element.accessibilityActivate())
            XCTAssertEqual(calls, 0)
            f.window.isHidden = true
        }
    }

    func testRetainedElementDoesNotRetainDocumentProviderOrCallbackOwner() throws {
        final class Owner { var calls = 0 }
        weak var weakDocument: LYGlyphTextDocument?
        weak var weakProvider: LYGlyphTextAttachmentViewProvider?
        weak var weakOwner: Owner?
        var element: UIAccessibilityElement?
        try autoreleasepool {
            let doc = try document()
            let provider = LYGlyphTextAttachmentViewProvider { _ in nil }
            let owner = Owner()
            weakDocument = doc
            weakProvider = provider
            weakOwner = owner
            let f = fixture(doc, provider: provider)
            f.label.onAction = { _ in owner.calls += 1 }
            element = elements(f.label).first
            f.label.removeFromSuperview()
            f.window.isHidden = true
        }
        XCTAssertNil(weakDocument)
        XCTAssertNil(weakProvider)
        XCTAssertNil(weakOwner)
        XCTAssertFalse(element?.accessibilityActivate() ?? true)
    }

    func testReentryDuringPressCancellationCannotActivateNewSnapshot() throws {
        final class Timer: ActionGestureTimer {
            var onCancel: (() -> Void)?
            func cancel() {
                let callback = onCancel
                onCancel = nil
                callback?()
            }
        }
        final class Clock: ActionGestureClock {
            let timer = Timer()
            func schedule(
                after _: TimeInterval,
                sequenceID _: UInt64,
                handler _: @escaping @MainActor (UInt64) -> Void
            ) -> ActionGestureTimer {
                timer
            }
        }
        let f = try fixture(document())
        let clock = Clock()
        f.label.actionClock = clock
        let layout = f.label.measuredLayout(width: f.label.bounds.width)
        let rect = try XCTUnwrap(ActionGeometry(
            layout: layout,
            bounds: f.label.bounds,
            configuration: f.label.configuration
        ).entries.first?.rects.first)
        XCTAssertTrue(f.label.beginActionInteraction(at: CGPoint(x: rect.midX, y: rect.midY), touchedView: f.label))
        var calls = 0
        f.label.onAction = { _ in calls += 1 }
        clock.timer.onCancel = {
            f.label.reloadAttachments()
            f.label.layoutIfNeeded()
            XCTAssertFalse(self.elements(f.label).first?.accessibilityActivate() ?? true)
        }
        XCTAssertFalse(try XCTUnwrap(elements(f.label).first).accessibilityActivate())
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(try XCTUnwrap(elements(f.label).first).accessibilityActivate())
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(f.label.beginActionInteraction(at: CGPoint(x: rect.midX, y: rect.midY), touchedView: f.label))
        clock.timer.onCancel = { f.label.isHidden = true }
        XCTAssertFalse(try XCTUnwrap(elements(f.label).first).accessibilityActivate())
        XCTAssertEqual(calls, 1)
        f.window.isHidden = true
    }

    func testRejectedFactoryFallsBackToVisibleAlternative() throws {
        let descriptor = LYGlyphTextViewAttachment(
            id: "v",
            viewID: "v",
            size: CGSize(width: 30, height: 30),
            alternativeText: "fallback",
            isInteractive: true
        )
        let occupied = UIView()
        let button = UIButton(type: .system)
        occupied.addSubview(button)
        let f = try fixture(document("\u{FFFC}", views: [0: descriptor]), provider: .init { _ in button })
        XCTAssertEqual(labels(f.label), ["fallback"])
        XCTAssertTrue(button.superview === occupied)
        XCTAssertTrue(try XCTUnwrap(elements(f.label).first).accessibilityActivate())
        f.window.isHidden = true
    }

    func testFactoryMutationsNeverPublishOrMountAnObsoleteCandidate() throws {
        typealias Mutation = @MainActor (LYGlyphTextLabel) throws -> Void
        let mutations: [Mutation] = [
            { $0.document = try self.document("current") }, { $0.viewProvider = nil },
            { $0.reloadAttachments() }, { $0.removeFromSuperview() }
        ]
        let descriptor = LYGlyphTextViewAttachment(
            id: "v",
            viewID: "v",
            size: CGSize(width: 30, height: 30),
            alternativeText: "old",
            isInteractive: true
        )
        for mutate in mutations {
            let f = try fixture(document("\u{FFFC}", views: [0: descriptor]))
            let old = try XCTUnwrap(elements(f.label).first)
            let candidate = UIView()
            var factoryCalls = 0
            f.label.viewProvider = .init { [weak label = f.label] _ in
                factoryCalls += 1
                if let label {
                    try? mutate(label)
                    label.layoutIfNeeded()
                    XCTAssertFalse(old.accessibilityActivate())
                    XCTAssertFalse(label.accessibilityElements?.contains { ($0 as? UIView) === candidate } ?? true)
                }
                return candidate
            }
            f.label.layoutIfNeeded()
            XCTAssertNil(candidate.superview)
            XCTAssertFalse(f.label.accessibilityElements?.contains { ($0 as? UIView) === candidate } ?? true)
            let before = factoryCalls
            _ = f.label.accessibilityElements
            XCTAssertEqual(factoryCalls, before)
            XCTAssertFalse(old.accessibilityActivate())
            f.window.isHidden = true
        }
    }

    func testHeightCompressionAndContentInsetsExcludeFullyHiddenSource() throws {
        let f = try fixture(document("visible\nhidden"), height: 24)
        f.label.configuration.textContainerInset = UIEdgeInsets(top: 2, left: 3, bottom: 2, right: 3)
        f.label.layoutIfNeeded()
        XCTAssertEqual(labels(f.label), ["visible"])
        let element = try XCTUnwrap(elements(f.label).first)
        let local = CGRect(x: 3, y: 2, width: 254, height: 20)
        let clip = f.window.convert(f.label.convert(local, to: f.window), to: nil as UIWindow?)
        XCTAssertTrue(clip.contains(element.accessibilityFrame))
        XCTAssertTrue(try clip.contains(XCTUnwrap(element.accessibilityPath).bounds))
        f.window.isHidden = true
    }
}
