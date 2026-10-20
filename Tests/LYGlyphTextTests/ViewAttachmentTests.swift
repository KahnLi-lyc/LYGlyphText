import CoreText
@testable import LYGlyphText
import SwiftUI
import UIKit
import XCTest

@MainActor
final class ViewAttachmentTests: XCTestCase {
    private let font = UIFont.systemFont(ofSize: 20)

    private func descriptor(
        id: String = "view", size: CGSize = CGSize(width: 40, height: 30),
        alignment: LYGlyphTextAttachmentAlignment = .bottom, interactive: Bool = false
    ) -> LYGlyphTextViewAttachment {
        LYGlyphTextViewAttachment(
            id: id, viewID: "badge", size: size, alignment: alignment, isInteractive: interactive
        )
    }

    private func document(_ value: LYGlyphTextViewAttachment? = nil) throws -> LYGlyphTextDocument {
        try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "A\u{FFFC}B", attributes: [.font: font]),
            viewAttachments: [1: value ?? descriptor()]
        )
    }

    func testDescriptorDefaultsAndDocumentGeometry() throws {
        let attachment = descriptor()
        XCTAssertEqual(attachment.id, "view")
        XCTAssertEqual(attachment.viewID, "badge")
        XCTAssertEqual(attachment.alignment, .bottom)
        XCTAssertNil(attachment.alternativeText)
        XCTAssertFalse(attachment.isInteractive)
        let label = LYGlyphTextLabel(frame: .zero)
        label.document = try document(attachment)
        XCTAssertEqual(label.measuredLayout(width: 200).viewAttachments.first?.rect.size, attachment.size)
    }

    private func fixture(
        document: LYGlyphTextDocument, provider: LYGlyphTextAttachmentViewProvider,
        size: CGSize = CGSize(width: 240, height: 150)
    ) -> (UIWindow, LYGlyphTextLabel) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        let label = LYGlyphTextLabel(frame: CGRect(origin: .zero, size: size))
        label.document = document
        label.viewProvider = provider
        root.view.addSubview(label)
        label.setNeedsLayout()
        label.layoutIfNeeded()
        return (window, label)
    }

    private func display(_ label: LYGlyphTextLabel) {
        label.setNeedsLayout()
        label.layoutIfNeeded()
    }

    func testSharedValidationCollisionIDsUTF16AndSnapshot() throws {
        let image = LYGlyphTextAttachment(id: "same", image: UIImage(), size: CGSize(width: 10, height: 10))
        let input = NSMutableAttributedString(string: "😀\u{FFFC}\u{FFFC}", attributes: [.font: font])
        XCTAssertThrowsError(try LYGlyphTextDocument(
            attributedText: input, attachments: [2: image], viewAttachments: [2: descriptor()]
        )) { XCTAssertEqual($0 as? LYGlyphTextDocumentError, .conflictingAttachmentLocation(location: 2)) }
        XCTAssertThrowsError(try LYGlyphTextDocument(
            attributedText: input, attachments: [2: image], viewAttachments: [3: descriptor(id: "same")]
        )) { XCTAssertEqual($0 as? LYGlyphTextDocumentError, .duplicateAttachmentID(id: "same")) }
        let snapshot = try LYGlyphTextDocument(
            attributedText: input, attachments: [2: image], viewAttachments: [3: descriptor()]
        )
        input.mutableString.setString("changed")
        XCTAssertEqual(snapshot.string, "😀\u{FFFC}\u{FFFC}")
        let layout = ResolvedText(document: snapshot, traits: .init()).layout(width: 300, insets: .zero, scale: 2)
        XCTAssertEqual(layout.attachments.first?.sourceLocation, 2)
        XCTAssertEqual(layout.viewAttachments.first?.sourceLocation, 3)
    }

    func testInvalidViewLocationsSizesAndOrphans() {
        let text = NSAttributedString(string: "A\u{FFFC}")
        for location in [-1, 0, 2, Int.max] {
            XCTAssertThrowsError(try LYGlyphTextDocument(
                attributedText: text, viewAttachments: [location: descriptor()]
            )) { XCTAssertEqual($0 as? LYGlyphTextDocumentError, .invalidAttachmentLocation(location: location)) }
        }
        for size in [
            CGSize(width: 0, height: 1), CGSize(width: 1, height: -1),
            CGSize(width: CGFloat.infinity, height: 1), CGSize(width: 1, height: CGFloat.nan)
        ] {
            XCTAssertThrowsError(try document(descriptor(size: size))) {
                XCTAssertEqual($0 as? LYGlyphTextDocumentError, .invalidAttachmentSize(id: "view"))
            }
        }
        XCTAssertThrowsError(try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "\u{FFFC}\u{301}"), viewAttachments: [0: descriptor()]
        )) { XCTAssertEqual($0 as? LYGlyphTextDocumentError, .invalidAttachmentLocation(location: 0)) }
        XCTAssertThrowsError(try LYGlyphTextDocument(attributedText: text)) {
            XCTAssertEqual($0 as? LYGlyphTextDocumentError, .unsupportedObjectReplacementCharacter(location: 1))
        }
        XCTAssertThrowsError(try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "\u{FFFC}", attributes: [.attachment: NSTextAttachment()]),
            viewAttachments: [0: descriptor()]
        )) { XCTAssertEqual(
            $0 as? LYGlyphTextDocumentError,
            .unsupportedAttachment(range: NSRange(location: 0, length: 1))
        ) }
        XCTAssertThrowsError(try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "\u{FFFC}\u{FFFC}"),
            viewAttachments: [0: descriptor(), 1: descriptor()]
        )) { XCTAssertEqual($0 as? LYGlyphTextDocumentError, .duplicateAttachmentID(id: "view")) }
    }

    func testViewAndImageUseIdenticalMixedFontAlignmentAndRTLGeometry() throws {
        for direction in [NSWritingDirection.leftToRight, .rightToLeft] {
            for alignment in [LYGlyphTextAttachmentAlignment.top, .center, .bottom] {
                let paragraph = NSMutableParagraphStyle()
                paragraph.baseWritingDirection = direction
                let text = NSMutableAttributedString(
                    string: "אב\u{FFFC}CD", attributes: [
                        .font: UIFont.systemFont(ofSize: 44),
                        .paragraphStyle: paragraph
                    ]
                )
                text.addAttribute(.font, value: font, range: NSRange(location: 2, length: 1))
                let value = descriptor(alignment: alignment)
                let viewDocument = try LYGlyphTextDocument(attributedText: text, viewAttachments: [2: value])
                let imageDocument = try LYGlyphTextDocument(attributedText: text, attachments: [
                    2: LYGlyphTextAttachment(id: "image", image: UIImage(), size: value.size, alignment: alignment)
                ])
                let viewLayout = ResolvedText(document: viewDocument, traits: .init()).layout(
                    width: 250, insets: .zero, scale: 2
                )
                let imageLayout = ResolvedText(document: imageDocument, traits: .init()).layout(
                    width: 250, insets: .zero, scale: 2
                )
                let rect = try XCTUnwrap(viewLayout.viewAttachments.first).rect
                XCTAssertEqual(rect, imageLayout.attachments.first?.rect)
                XCTAssertEqual(viewLayout.size, imageLayout.size)
                let baseline = try XCTUnwrap(viewLayout.lines.first).baseline.y
                switch alignment {
                case .top: XCTAssertEqual(rect.minY, baseline - font.ascender, accuracy: 0.01)
                case .center:
                    XCTAssertEqual(rect.midY, baseline - (font.ascender + font.descender) / 2, accuracy: 0.01)
                case .bottom: XCTAssertEqual(rect.maxY, baseline - font.descender, accuracy: 0.01)
                }
            }
        }
    }

    func testTruncationOnlyRetainsFinalVisibleViewRuns() throws {
        let doc = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "A\u{FFFC} long long long long long \u{FFFC} end", attributes: [.font: font]
        ), viewAttachments: [1: descriptor(id: "first"), 28: descriptor(id: "last")])
        let label = LYGlyphTextLabel(frame: .zero)
        label.document = doc
        XCTAssertEqual(label.measuredLayout(width: 150).viewAttachments.count, 2)
        label.configuration.numberOfLines = 1
        XCTAssertEqual(label.measuredLayout(width: 150).viewAttachments.map(\.attachment.id), ["first"])
        label.configuration.numberOfLines = 0
        XCTAssertEqual(label.measuredLayout(width: 150).viewAttachments.count, 2)
    }

    func testAllMeasurementAndOfflineLayoutPathsNeverCallFactory() throws {
        var calls = 0
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        label.document = try document()
        label.viewProvider = .init { _ in calls += 1
            return UIView()
        }
        _ = label.intrinsicContentSize
        _ = label.sizeThatFits(CGSize(width: 100, height: 1))
        _ = label.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        _ = label.systemLayoutSizeFitting(
            CGSize(width: 100, height: 1), withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        _ = label.measuredLayout(width: 100)
        display(label)
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(label.subviews.isEmpty)
    }

    func testWindowMountReusesAndUsesDeclaredFrameWithInsetsAndBoundsOrigin() throws {
        var calls = 0
        weak var mounted: UIView?
        let provider = LYGlyphTextAttachmentViewProvider { _ in
            calls += 1
            let result = UILabel(frame: CGRect(x: 0, y: 0, width: 999, height: 999))
            result.text = "long intrinsic size cannot change layout"
            mounted = result
            return result
        }
        let (window, label) = try fixture(document: document(), provider: provider)
        defer { window.isHidden = true }
        XCTAssertEqual(calls, 1)
        let first = try XCTUnwrap(mounted)
        label.configuration.textContainerInset = UIEdgeInsets(top: 5, left: 9, bottom: 7, right: 11)
        label.bounds.origin = CGPoint(x: 13, y: 17)
        display(label)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(mounted === first)
        let placement = try XCTUnwrap(label.measuredLayout(width: label.bounds.width).viewAttachments.first)
        let actual = first.convert(first.bounds, to: label)
        XCTAssertEqual(actual, placement.rect.offsetBy(dx: label.bounds.minX, dy: label.bounds.minY))
        XCTAssertEqual(first.frame.size, descriptor().size)
        XCTAssertEqual(first.superview?.frame, CGRect(x: 22, y: 22, width: 220, height: 138))
        XCTAssertEqual(first.superview?.clipsToBounds, true)
        XCTAssertFalse(first.isUserInteractionEnabled)
        XCTAssertTrue(label.hitTest(CGPoint(x: actual.midX, y: actual.midY), with: nil) === label)
        for width in [CGFloat(180), 240, 180] {
            label.bounds.size.width = width
            display(label)
            XCTAssertEqual(calls, 1)
            XCTAssertTrue(mounted === first)
        }
    }

    func testHeightClippingUnloadsReleasesAndReappearanceRecreates() throws {
        var calls = 0
        var unmounts = 0
        weak var mounted: UIView?
        let provider = LYGlyphTextAttachmentViewProvider(makeView: { _ in
            calls += 1
            let result = UIView()
            mounted = result
            return result
        }, onUnmount: { _, view in
            unmounts += 1
            XCTAssertNil(view.superview)
        })
        let doc = try document()
        let (window, label) = autoreleasepool { fixture(document: doc, provider: provider) }
        defer { window.isHidden = true }
        XCTAssertNotNil(mounted)
        autoreleasepool {
            label.bounds.size.height = 0
            display(label)
        }
        XCTAssertEqual(unmounts, 1)
        XCTAssertNil(mounted)
        autoreleasepool {
            label.bounds.size.height = 150
            display(label)
        }
        XCTAssertEqual(calls, 2)
        autoreleasepool { label.document = nil }
        XCTAssertEqual(unmounts, 2)
        XCTAssertNil(mounted)
        XCTAssertTrue(label.viewProvider === provider)
    }

    func testNativeInteractiveButtonHitAndContainerPassThroughAndClip() throws {
        let button = UIButton(type: .system)
        let (window, label) = try fixture(
            document: document(descriptor(interactive: true)), provider: .init { _ in button }
        )
        defer { window.isHidden = true }
        let rect = button.convert(button.bounds, to: label)
        XCTAssertTrue(label.hitTest(CGPoint(x: rect.midX, y: rect.midY), with: nil) === button)
        XCTAssertTrue(label.hitTest(CGPoint(x: 200, y: 120), with: nil) === label)
        label.configuration.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 215)
        display(label)
        let container = try XCTUnwrap(button.superview)
        XCTAssertNil(container.hitTest(CGPoint(x: container.bounds.maxX + 1, y: 5), with: nil))
    }

    func testNilFailureCachedUntilHiddenReloadDocumentProviderOrDetach() throws {
        var calls = 0
        let provider = LYGlyphTextAttachmentViewProvider { _ in calls += 1
            return nil
        }
        let doc = try document()
        let (window, label) = fixture(document: doc, provider: provider)
        defer { window.isHidden = true }
        for _ in 0 ..< 3 {
            display(label)
        }
        XCTAssertEqual(calls, 1)
        label.bounds.size.height = 0
        display(label)
        label.bounds.size.height = 150
        display(label)
        XCTAssertEqual(calls, 2)
        label.reloadAttachments()
        display(label)
        XCTAssertEqual(calls, 3)
        label.document = try document()
        display(label)
        XCTAssertEqual(calls, 4)
        label.removeFromSuperview()
        window.rootViewController?.view.addSubview(label)
        display(label)
        XCTAssertEqual(calls, 5)
        label.viewProvider = .init { _ in calls += 1
            return nil
        }
        display(label)
        XCTAssertEqual(calls, 6)
    }

    func testRejectsOwnedSelfAncestorAndDuplicateInstanceWithoutStealing() throws {
        let owner = UIView()
        let child = UIView()
        owner.addSubview(child)
        var rejectedUnmounts = 0
        let (window, label) = try fixture(document: document(), provider: .init(
            makeView: { _ in child }, onUnmount: { _, _ in rejectedUnmounts += 1 }
        ))
        defer { window.isHidden = true }
        XCTAssertTrue(child.superview === owner)
        label.viewProvider = .init { [weak label] _ in label }
        display(label)
        XCTAssertTrue(label.superview === window.rootViewController?.view)
        let root = try XCTUnwrap(window.rootViewController?.view)
        label.viewProvider = .init { _ in root }
        display(label)
        XCTAssertNotNil(root.superview)
        XCTAssertEqual(rejectedUnmounts, 0)
        let shared = UIView()
        let doc = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "\u{FFFC}\u{FFFC}"),
            viewAttachments: [
                0: descriptor(id: "a"), 1: descriptor(id: "b")
            ]
        )
        var calls = 0
        label.document = doc
        label.viewProvider = .init { _ in calls += 1
            return shared
        }
        display(label)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(shared.superview?.subviews.count, 1)
        display(label)
        XCTAssertEqual(calls, 2)
    }

    func testProviderIdentityDocumentIdentityReloadAndDetachHaveExactUnmounts() throws {
        var created = 0
        var originalUnmounts = 0
        var newUnmounts = 0
        let provider = LYGlyphTextAttachmentViewProvider(makeView: { _ in created += 1
            return UIView()
        }, onUnmount: {
            _, _ in originalUnmounts += 1
        })
        let doc = try document()
        let (window, label) = fixture(document: doc, provider: provider)
        defer { window.isHidden = true }
        label.document = doc
        label.viewProvider = provider
        display(label)
        XCTAssertEqual(created, 1)
        label.document = try document()
        XCTAssertEqual(originalUnmounts, 1)
        display(label)
        XCTAssertEqual(created, 2)
        label.reloadAttachments()
        XCTAssertEqual(originalUnmounts, 2)
        display(label)
        label.viewProvider = .init(makeView: { _ in UIView() }, onUnmount: { _, _ in newUnmounts += 1 })
        XCTAssertEqual(originalUnmounts, 3)
        display(label)
        label.removeFromSuperview()
        XCTAssertEqual(newUnmounts, 1)
        label.removeFromSuperview()
        XCTAssertEqual(newUnmounts, 1)
        window.rootViewController?.view.addSubview(label)
        display(label)
        label.document = nil
        XCTAssertEqual(newUnmounts, 2)
    }

    func testFactoryReentrancyDiscardsStaleResultsWithoutUnmountCallback() throws {
        for operation in 0 ..< 4 {
            let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 240, height: 150))
            var calls = 0
            var unmounts = 0
            weak var discarded: UIView?
            label.document = try document()
            label.viewProvider = .init(makeView: { [weak label] _ in
                calls += 1
                let view = UIView()
                if calls == 1 {
                    discarded = view
                    switch operation {
                    case 0: label?.document = nil
                    case 1: label?.viewProvider = nil
                    case 2: label?.reloadAttachments()
                    default: label?.removeFromSuperview()
                    }
                }
                return view
            }, onUnmount: { _, _ in unmounts += 1 })
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = UIViewController()
            window.makeKeyAndVisible()
            window.rootViewController?.view.addSubview(label)
            display(label)
            XCTAssertEqual(unmounts, 0)
            XCTAssertNil(discarded)
            if operation != 2 { XCTAssertTrue(label.subviews.isEmpty) }
            window.isHidden = true
        }
    }

    func testUnmountReentrancyDoesNotDoubleUnmountOrMountStaleGeneration() throws {
        for operation in 0 ..< 4 {
            var events: [String] = []
            weak var weakLabel: LYGlyphTextLabel?
            let replacement = try document(descriptor(id: "replacement"))
            let provider = LYGlyphTextAttachmentViewProvider(makeView: { descriptor in
                events.append("make:" + descriptor.id)
                return UIView()
            }, onUnmount: { descriptor, view in
                XCTAssertNil(view.superview)
                events.append("unmount:" + descriptor.id)
                switch operation {
                case 0: weakLabel?.document = replacement
                case 1: weakLabel?.viewProvider = nil
                case 2: weakLabel?.reloadAttachments()
                default: weakLabel?.removeFromSuperview()
                }
            })
            let (window, label) = try fixture(document: document(), provider: provider)
            weakLabel = label
            label.bounds.size.height = 0
            display(label)
            XCTAssertEqual(events, ["make:view", "unmount:view"])
            display(label)
            XCTAssertEqual(events, ["make:view", "unmount:view"])
            label.bounds.size.height = 150
            display(label)
            if operation == 0 { XCTAssertEqual(events.last, "make:replacement") }
            if operation == 2 { XCTAssertEqual(events.last, "make:view") }
            weakLabel = nil
            label.document = nil
            window.isHidden = true
        }
    }

    func testSwiftUIProviderIdentityUpdateAndDismantleRelease() throws {
        var firstCalls = 0
        var unmounts = 0
        let first = LYGlyphTextAttachmentViewProvider(makeView: { _ in firstCalls += 1
            return UIView()
        }, onUnmount: {
            _, _ in unmounts += 1
        })
        var secondCalls = 0
        let second = LYGlyphTextAttachmentViewProvider { _ in secondCalls += 1
            return UIView()
        }
        let doc = try document()
        let host = UIHostingController(rootView: LYGlyphTextView(document: doc, viewProvider: first).frame(width: 240))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        let label = try XCTUnwrap(findLabel(host.view))
        display(label)
        XCTAssertEqual(firstCalls, 1)
        host.rootView = LYGlyphTextView(document: doc, viewProvider: first).frame(width: 240)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        display(label)
        XCTAssertEqual(firstCalls, 1)
        host.rootView = LYGlyphTextView(document: doc, viewProvider: second).frame(width: 240)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        display(label)
        XCTAssertTrue(label.viewProvider === second)
        XCTAssertEqual(firstCalls, 1)
        XCTAssertEqual(secondCalls, 1)
        XCTAssertEqual(unmounts, 1)
        LYGlyphTextView.dismantleUIView(label, coordinator: ())
        LYGlyphTextView.dismantleUIView(label, coordinator: ())
        XCTAssertNil(label.document)
        XCTAssertNil(label.viewProvider)
        XCTAssertTrue(label.subviews.isEmpty)
        window.isHidden = true
    }

    func testDocumentReplacementInvalidatesGeometryBeforeReentrantUnmountLayout() throws {
        var ids: [String] = []
        weak var host: LYGlyphTextLabel?
        var didReenter = false
        let provider = LYGlyphTextAttachmentViewProvider(makeView: { value in
            ids.append(value.id)
            return UIView()
        }, onUnmount: { _, _ in
            guard !didReenter else { return }
            didReenter = true
            host?.setNeedsLayout()
            host?.layoutIfNeeded()
        })
        let (window, label) = try fixture(document: document(), provider: provider)
        defer { window.isHidden = true }
        host = label
        label.document = try document(descriptor(id: "new"))
        display(label)
        XCTAssertEqual(ids, ["view", "new"])
        host = nil
        label.document = nil
    }

    func testMountedViewHierarchyCallbackMaySynchronouslyClearDocument() throws {
        weak var host: LYGlyphTextLabel?
        var unmounts = 0
        let provider = LYGlyphTextAttachmentViewProvider(makeView: { _ in
            let result = HierarchyCallbackView()
            result.onMount = { host?.document = nil }
            return result
        }, onUnmount: { _, view in
            XCTAssertNil(view.superview)
            unmounts += 1
        })
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 240, height: 150))
        host = label
        label.document = try document()
        label.viewProvider = provider
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        window.rootViewController?.view.addSubview(label)
        display(label)
        XCTAssertNil(label.document)
        XCTAssertEqual(unmounts, 1)
        XCTAssertTrue(label.subviews.isEmpty)
        display(label)
        XCTAssertEqual(unmounts, 1)
        window.isHidden = true
    }

    func testTwoLabelsShareDocumentButOwnDifferentInstancesAndRefuseSharedInstance() throws {
        let doc = try document()
        var calls = 0
        let provider = LYGlyphTextAttachmentViewProvider { _ in calls += 1
            return UIView()
        }
        let (window, first) = fixture(document: doc, provider: provider)
        defer { window.isHidden = true }
        let second = LYGlyphTextLabel(frame: CGRect(x: 0, y: 200, width: 240, height: 150))
        second.document = doc
        second.viewProvider = provider
        window.rootViewController?.view.addSubview(second)
        display(second)
        XCTAssertEqual(calls, 2)
        let firstView = try XCTUnwrap(first.subviews.first?.subviews.first)
        let secondView = try XCTUnwrap(second.subviews.first?.subviews.first)
        XCTAssertFalse(firstView === secondView)
        second.viewProvider = .init { _ in firstView }
        display(second)
        XCTAssertTrue(firstView.isDescendant(of: first))
        XCTAssertTrue(second.subviews.isEmpty)
    }

    func testOldProviderAndCapturedObjectsReleaseAfterReplacement() throws {
        weak var oldProvider: LYGlyphTextAttachmentViewProvider?
        weak var oldView: UIView?
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 240, height: 150))
        label.document = try document()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        window.rootViewController?.view.addSubview(label)
        autoreleasepool {
            let provider = LYGlyphTextAttachmentViewProvider { _ in
                let result = UIView()
                oldView = result
                return result
            }
            oldProvider = provider
            label.viewProvider = provider
            display(label)
        }
        XCTAssertNotNil(oldProvider)
        XCTAssertNotNil(oldView)
        autoreleasepool { label.viewProvider = .init { _ in nil } }
        XCTAssertNil(oldProvider)
        XCTAssertNil(oldView)
        window.isHidden = true
    }

    func testSwiftUIDismantleIsAtomicWhenUnmountCallbackRestoresInputsAndLayouts() throws {
        let replacement = try document(descriptor(id: "replacement"))
        let replacementProvider = LYGlyphTextAttachmentViewProvider { _ in
            XCTFail("拆卸回调不能恢复挂载")
            return UIView()
        }
        weak var host: LYGlyphTextLabel?
        var unmounts = 0
        let provider = LYGlyphTextAttachmentViewProvider(makeView: { _ in UIView() }, onUnmount: { _, _ in
            unmounts += 1
            host?.document = replacement
            host?.viewProvider = replacementProvider
            host?.reloadAttachments()
            host?.setNeedsLayout()
            host?.layoutIfNeeded()
        })
        let (window, label) = try fixture(document: document(), provider: provider)
        defer { window.isHidden = true }
        host = label
        LYGlyphTextView.dismantleUIView(label, coordinator: ())
        LYGlyphTextView.dismantleUIView(label, coordinator: ())
        XCTAssertEqual(unmounts, 1)
        XCTAssertNil(label.document)
        XCTAssertNil(label.viewProvider)
        XCTAssertTrue(label.subviews.isEmpty)
        XCTAssertTrue(label.measuredLayout(width: 200).viewAttachments.isEmpty)
    }

    func testMountedTruncationUnloadsOnlyHiddenViewsAndRestoresThem() throws {
        let doc = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: "A\u{FFFC} long long long long long \u{FFFC} end", attributes: [.font: font]
        ), viewAttachments: [1: descriptor(id: "first"), 28: descriptor(id: "last")])
        var made: [String] = []
        var removed: [String] = []
        let provider = LYGlyphTextAttachmentViewProvider(makeView: { value in
            made.append(value.id)
            return UIView()
        }, onUnmount: { value, _ in removed.append(value.id) })
        let (window, label) = fixture(document: doc, provider: provider, size: CGSize(width: 150, height: 400))
        defer { window.isHidden = true }
        XCTAssertEqual(made, ["first", "last"])
        label.configuration.numberOfLines = 1
        display(label)
        XCTAssertEqual(removed, ["last"])
        XCTAssertEqual(made, ["first", "last"])
        label.configuration.numberOfLines = 0
        display(label)
        XCTAssertEqual(made, ["first", "last", "last"])
        XCTAssertEqual(removed, ["last"])
    }

    func testPartiallyVisibleInteractiveViewRetainsInstanceAndClipsAtBoundsOrigin() throws {
        let button = UIButton(type: .system)
        var calls = 0
        let (window, label) = try fixture(document: document(descriptor(interactive: true)), provider: .init { _ in
            calls += 1
            return button
        })
        defer { window.isHidden = true }
        label.bounds.origin = CGPoint(x: 13, y: 17)
        label.bounds.size.height = 15
        display(label)
        XCTAssertEqual(calls, 1)
        let rect = button.convert(button.bounds, to: label)
        let visible = rect.intersection(label.bounds)
        XCTAssertGreaterThan(visible.height, 0)
        XCTAssertLessThan(visible.height, rect.height)
        XCTAssertTrue(label.hitTest(CGPoint(x: visible.midX, y: visible.midY), with: nil) === button)
        XCTAssertNil(label.hitTest(CGPoint(x: rect.midX, y: label.bounds.maxY + 1), with: nil))
    }

    func testContainerDetachHierarchyReentrancyKeepsReplacementContainerTracked() throws {
        let replacement = try document(descriptor(id: "new"))
        weak var host: LYGlyphTextLabel?
        weak var currentView: UIView?
        var reentered = false
        var made: [String] = []
        var removed: [String] = []
        let provider = LYGlyphTextAttachmentViewProvider(makeView: { value in
            made.append(value.id)
            if value.id == "view" {
                let result = WindowRemovalCallbackView()
                result.onWindowRemoval = {
                    guard !reentered else { return }
                    reentered = true
                    host?.document = replacement
                    host?.setNeedsLayout()
                    host?.layoutIfNeeded()
                }
                return result
            }
            let result = UIView()
            currentView = result
            return result
        }, onUnmount: { value, _ in removed.append(value.id) })
        let (window, label) = try fixture(document: document(), provider: provider)
        defer { window.isHidden = true }
        host = label
        label.reloadAttachments()
        display(label)
        XCTAssertEqual(made, ["view", "new"])
        XCTAssertEqual(removed, ["view"])
        XCTAssertEqual(label.subviews.count, 1)
        label.configuration.textContainerInset = UIEdgeInsets(top: 10, left: 4, bottom: 5, right: 6)
        display(label)
        XCTAssertEqual(currentView?.superview?.frame, CGRect(x: 4, y: 10, width: 230, height: 135))
        host = nil
    }

    func testCleanupBatchDefersFactoriesUntilEveryOldUnmountCallbackCompletes() throws {
        let oldDocument = try LYGlyphTextDocument(
            attributedText: NSAttributedString(string: "\u{FFFC}\u{FFFC}"),
            viewAttachments: [0: descriptor(id: "a"), 1: descriptor(id: "b")]
        )
        let newDocument = try document(descriptor(id: "new"))
        let views = ["a": UIView(), "b": UIView()]
        var completed: Set<String> = []
        var didReplace = false
        var pendingView: UIView?
        var newFactoryCalls = 0
        weak var host: LYGlyphTextLabel?
        let replacementProvider = LYGlyphTextAttachmentViewProvider { _ in
            newFactoryCalls += 1
            XCTAssertEqual(completed, ["a", "b"])
            return pendingView
        }
        let provider = LYGlyphTextAttachmentViewProvider(makeView: { views[$0.id] }, onUnmount: { value, view in
            XCTAssertNil(view.superview)
            if !didReplace {
                didReplace = true
                pendingView = views.first { $0.key != value.id }?.value
                host?.document = newDocument
                host?.viewProvider = replacementProvider
                host?.setNeedsLayout()
                host?.layoutIfNeeded()
                XCTAssertEqual(newFactoryCalls, 0)
            }
            completed.insert(value.id)
        })
        let (window, label) = fixture(document: oldDocument, provider: provider)
        defer { window.isHidden = true }
        host = label
        label.reloadAttachments()
        display(label)
        XCTAssertEqual(completed, ["a", "b"])
        XCTAssertEqual(newFactoryCalls, 1)
        XCTAssertTrue(pendingView?.isDescendant(of: label) == true)
        label.document = nil
        XCTAssertNil(pendingView?.superview)
        host = nil
    }

    private func findLabel(_ view: UIView) -> LYGlyphTextLabel? {
        if let label = view as? LYGlyphTextLabel { return label }
        return view.subviews.lazy.compactMap { self.findLabel($0) }.first
    }
}

@MainActor
private final class HierarchyCallbackView: UIView {
    var onMount: (() -> Void)?

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview != nil { onMount?() }
    }
}

@MainActor
private final class WindowRemovalCallbackView: UIView {
    var onWindowRemoval: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { onWindowRemoval?() }
    }
}
