@testable import LYGlyphText
@testable import LYGlyphTextDemo
import UIKit
import XCTest

@MainActor
final class PerformanceBehaviorTests: XCTestCase {
    func testNineInputsHaveExactUTF16LengthsAttachmentLocationsAndFixedMetadata() throws {
        let samples = PerformanceSamples()
        XCTAssertEqual(samples.samples.count, 9)
        XCTAssertEqual(Set(samples.samples.map(\.metadata.id)).count, 9)
        for length in [100, 1000, 5000] {
            for count in [0, 3, 10] {
                let sample = try XCTUnwrap(samples.samples.first {
                    $0.metadata.utf16Length == length && $0.metadata.attachmentCount == count
                })
                let metadata = sample.metadata
                XCTAssertEqual(sample.attributedText.length, length)
                XCTAssertEqual(sample.attributedText.string.utf16.count, length)
                XCTAssertEqual(metadata.fontPointSize, 20)
                XCTAssertEqual(metadata.width, 320)
                XCTAssertEqual(metadata.attachmentSide, 24)
                XCTAssertEqual(metadata.numberOfLines, 0)
                XCTAssertEqual(metadata.wrapping, "word")
                XCTAssertEqual(metadata.verticalAlignment, "top")
                XCTAssertEqual(metadata.textContainerInsets, [0, 0, 0, 0])
                XCTAssertEqual(sample.configuration, LYGlyphTextConfiguration())
                XCTAssertEqual(metadata.imageLocations.count, count == 3 ? 2 : count / 2)
                XCTAssertEqual(metadata.viewLocations.count, count == 3 ? 1 : count / 2)
                XCTAssertEqual(metadata.scripts, ["Chinese", "emoji", "Arabic", "Latin"])
                let locations = metadata.imageLocations + metadata.viewLocations
                let source = sample.attributedText.string as NSString
                XCTAssertEqual(Set(locations).count, count)
                XCTAssertEqual(
                    (0 ..< source.length).filter { source.character(at: $0) == 0xFFFC }.sorted(),
                    locations.sorted()
                )
                for location in locations {
                    XCTAssertEqual(
                        source.rangeOfComposedCharacterSequence(at: location),
                        NSRange(location: location, length: 1)
                    )
                }
                for token in ["中文", "😀", "مرحبا", "Latin"] {
                    XCTAssertTrue(source.contains(token), metadata.id)
                }
                sample.attributedText.enumerateAttribute(.font, in: NSRange(location: 0, length: length)) {
                    value, _, _ in
                    XCTAssertEqual((value as? UIFont)?.pointSize, 20)
                }
                let document = try sample.makeDocument()
                let ids = document.attachments.values.map(\.id) + document.viewAttachments.values.map(\.id)
                XCTAssertEqual(Set(ids).count, count)
                XCTAssertEqual(Set(document.attachments.keys), Set(metadata.imageLocations))
                XCTAssertEqual(Set(document.viewAttachments.keys), Set(metadata.viewLocations))
                XCTAssertTrue(document.attachments.values.allSatisfy { $0.size == CGSize(width: 24, height: 24) })
                XCTAssertTrue(document.viewAttachments.values.allSatisfy {
                    $0.size == CGSize(width: 24, height: 24) && $0.isInteractive
                })
            }
        }
    }

    func testReconstructionCreatesIndependentSnapshotsAndPrefixActionsRemainVisibleAtThreeLines() throws {
        for sample in PerformanceSamples().samples {
            let first = try sample.makeDocument()
            let second = try sample.makeDocument()
            XCTAssertFalse(first === second)
            XCTAssertEqual(first.string, second.string)
            XCTAssertEqual(first.string, sample.attributedText.string)
            XCTAssertEqual(first.attachments.keys.sorted(), second.attachments.keys.sorted())
            XCTAssertEqual(first.viewAttachments.keys.sorted(), second.viewAttachments.keys.sorted())
            XCTAssertEqual(first.actions.map(\.range), second.actions.map(\.range))
            let label = LYGlyphTextLabel(frame: .zero)
            label.document = first
            label.configuration.numberOfLines = 3
            let layout = label.measuredLayout(width: 320)
            XCTAssertFalse(layout.actionIndex.isEmpty, sample.metadata.id)
            XCTAssertFalse(layout.actionIndex[0].rects.isEmpty, sample.metadata.id)
            XCTAssertEqual(layout.viewAttachments.count, sample.metadata.viewLocations.count, sample.metadata.id)
            XCTAssertEqual(layout.attachments.count, sample.metadata.imageLocations.count, sample.metadata.id)
        }
    }

    func testEveryOfflineMeasurementKeepsFactoryFrameConstraintsPrioritiesAndSubviewsUnchanged() throws {
        for sample in PerformanceSamples().samples {
            let label = LYGlyphTextLabel(frame: CGRect(x: 7, y: 11, width: 123, height: 160))
            label.document = try sample.makeDocument()
            let ledger = AttachmentLedger()
            label.viewProvider = ledger.provider
            label.setContentHuggingPriority(.init(251), for: .horizontal)
            label.setContentHuggingPriority(.init(252), for: .vertical)
            label.setContentCompressionResistancePriority(.init(751), for: .horizontal)
            label.setContentCompressionResistancePriority(.init(752), for: .vertical)
            let width = label.widthAnchor.constraint(equalToConstant: 123)
            let height = label.heightAnchor.constraint(equalToConstant: 160)
            NSLayoutConstraint.activate([width, height])
            let child = UIView()
            label.addSubview(child)
            let frame = label.frame
            let bounds = label.bounds
            let constraintIDs = label.constraints.map(ObjectIdentifier.init)
            for value in [CGFloat(0), 320] {
                let fitted = label.sizeThatFits(CGSize(width: value, height: 1))
                XCTAssertTrue(fitted.width.isFinite && fitted.height.isFinite)
                let required = label.systemLayoutSizeFitting(
                    CGSize(width: value, height: 1), withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .fittingSizeLevel
                )
                XCTAssertTrue(required.width.isFinite && required.height.isFinite)
            }
            _ = label.intrinsicContentSize
            _ = label.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            XCTAssertEqual(ledger.records.count, 0, sample.metadata.id)
            XCTAssertEqual(ledger.unmounts, 0)
            XCTAssertEqual(label.frame, frame)
            XCTAssertEqual(label.bounds, bounds)
            XCTAssertEqual(label.constraints.map(ObjectIdentifier.init), constraintIDs)
            XCTAssertTrue(width.isActive && height.isActive)
            XCTAssertEqual(width.constant, 123)
            XCTAssertEqual(height.constant, 160)
            XCTAssertEqual(label.subviews.map(ObjectIdentifier.init), [ObjectIdentifier(child)])
            XCTAssertEqual(label.contentHuggingPriority(for: .horizontal).rawValue, 251)
            XCTAssertEqual(label.contentHuggingPriority(for: .vertical).rawValue, 252)
            XCTAssertEqual(label.contentCompressionResistancePriority(for: .horizontal).rawValue, 751)
            XCTAssertEqual(label.contentCompressionResistancePriority(for: .vertical).rawValue, 752)
        }
    }

    func testExactTwoEntryCacheBuildsAndDocumentIdentityInvalidationForAllLoads() throws {
        for sample in PerformanceSamples().samples {
            let label = LYGlyphTextLabel(frame: .zero)
            let document = try sample.makeDocument()
            label.document = document
            label.resetLayoutMeasurementCounts()
            let widths: [CGFloat] = [240, 320, 240, 480, 320, 240, 480]
            let builds = [1, 2, 2, 3, 3, 4, 4]
            for (index, width) in widths.enumerated() {
                _ = label.sizeThatFits(CGSize(width: width, height: CGFloat.infinity))
                XCTAssertEqual(label.layoutMeasurementSnapshot.layoutBuildCount, builds[index], sample.metadata.id)
                XCTAssertEqual(label.layoutMeasurementSnapshot.cachedLayoutCount, min(index + 1, 2))
            }
            let stable = label.layoutMeasurementSnapshot
            label.document = document
            XCTAssertEqual(label.layoutMeasurementSnapshot, stable)
            _ = label.sizeThatFits(CGSize(width: 480, height: CGFloat.infinity))
            XCTAssertEqual(label.layoutMeasurementSnapshot, stable)
            label.document = try sample.makeDocument()
            XCTAssertEqual(label.layoutMeasurementSnapshot.cachedLayoutCount, 0)
            XCTAssertEqual(label.layoutMeasurementSnapshot.layoutBuildCount, stable.layoutBuildCount)
            _ = label.sizeThatFits(CGSize(width: 480, height: CGFloat.infinity))
            XCTAssertEqual(label.layoutMeasurementSnapshot.layoutBuildCount, stable.layoutBuildCount + 1)
            XCTAssertEqual(label.layoutMeasurementSnapshot.cachedLayoutCount, 1)
        }
    }

    func testEachViewLoadSurvives100RealWindowClearReloadAndDetachCyclesWithoutRetainedViews() throws {
        for sample in PerformanceSamples().samples where !sample.metadata.viewLocations.isEmpty {
            let host = WindowHost()
            defer { host.close() }
            let ledger = AttachmentLedger()
            let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
            label.viewProvider = ledger.provider
            let document = try sample.makeDocument()
            var expectedTotal = 0
            for round in 0 ..< 100 {
                let start = ledger.records.count
                let visible = autoreleasepool {
                    label.document = document
                    host.root.view.addSubview(label)
                    display(label)
                    return visibleViewCount(label)
                }
                XCTAssertGreaterThan(visible, 0, "\(sample.metadata.id) round=\(round)")
                expectedTotal += visible
                XCTAssertEqual(ledger.records.count, expectedTotal)
                let stableIDs = ledger.liveIDs
                autoreleasepool { display(label) }
                XCTAssertEqual(ledger.records.count, expectedTotal)
                XCTAssertEqual(ledger.liveIDs, stableIDs)
                let first = Array(ledger.records[start...])
                autoreleasepool { label.reloadAttachments() }
                XCTAssertTrue(first.allSatisfy { $0.view == nil })
                XCTAssertEqual(ledger.unmounts, expectedTotal)
                autoreleasepool { display(label) }
                expectedTotal += visible
                XCTAssertEqual(ledger.records.count, expectedTotal)
                let reloaded = Array(ledger.records.suffix(visible))
                autoreleasepool { label.removeFromSuperview() }
                XCTAssertTrue(reloaded.allSatisfy { $0.view == nil })
                XCTAssertEqual(ledger.unmounts, expectedTotal)
                autoreleasepool { display(label) }
                XCTAssertEqual(ledger.records.count, expectedTotal)
                autoreleasepool {
                    host.root.view.addSubview(label)
                    display(label)
                }
                expectedTotal += visible
                XCTAssertEqual(ledger.records.count, expectedTotal)
                autoreleasepool { label.document = nil }
                XCTAssertEqual(ledger.unmounts, expectedTotal)
                XCTAssertTrue(ledger.records.allSatisfy { $0.view == nil })
                XCTAssertTrue(ledger.liveIDs.isEmpty)
                autoreleasepool {
                    label.document = nil
                    label.removeFromSuperview()
                }
                XCTAssertEqual(ledger.unmounts, expectedTotal)
            }
            XCTAssertEqual(ledger.records.count, expectedTotal)
            XCTAssertEqual(ledger.unmounts, expectedTotal)
            print(
                "P1a lifecycle \(sample.metadata.id);rounds=100;factory=\(ledger.records.count);" +
                    "unmount=\(ledger.unmounts);live=\(ledger.liveIDs.count)"
            )
        }
    }

    func testSharedDocumentAndProviderGiveTwoHostsIndependentInstancesAndCleanup() throws {
        for sample in PerformanceSamples().samples where !sample.metadata.viewLocations.isEmpty {
            let host = WindowHost()
            defer { host.close() }
            let document = try sample.makeDocument()
            let ledger = AttachmentLedger()
            let first = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
            let second = LYGlyphTextLabel(frame: CGRect(x: 0, y: 180, width: 320, height: 160))
            autoreleasepool {
                for label in [first, second] {
                    label.document = document
                    label.viewProvider = ledger.provider
                    host.root.view.addSubview(label)
                    display(label)
                }
            }
            let count = visibleViewCount(first)
            XCTAssertGreaterThan(count, 0)
            XCTAssertEqual(visibleViewCount(second), count)
            let firstIDs = ledger.liveIDs(in: first)
            let secondIDs = ledger.liveIDs(in: second)
            XCTAssertEqual(firstIDs.count, count)
            XCTAssertEqual(secondIDs.count, count)
            XCTAssertTrue(firstIDs.isDisjoint(with: secondIDs))
            XCTAssertEqual(ledger.records.count, 2 * count)
            autoreleasepool { first.document = nil }
            XCTAssertEqual(ledger.unmounts, count)
            XCTAssertEqual(ledger.liveIDs, secondIDs)
            XCTAssertEqual(ledger.liveIDs(in: second), secondIDs)
            autoreleasepool { display(second) }
            XCTAssertEqual(ledger.records.count, 2 * count)
            autoreleasepool {
                second.document = nil
                first.removeFromSuperview()
                second.removeFromSuperview()
            }
            XCTAssertEqual(ledger.unmounts, 2 * count)
            XCTAssertTrue(ledger.records.allSatisfy { $0.view == nil })
        }
    }

    private func display(_ label: LYGlyphTextLabel) {
        for _ in 0 ..< 3 {
            label.setNeedsLayout()
            label.layoutIfNeeded()
        }
    }

    private func visibleViewCount(_ label: LYGlyphTextLabel) -> Int {
        label.measuredLayout(width: label.bounds.width).viewAttachments.count(where: {
            $0.rect.intersects(label.bounds)
        })
    }
}

@MainActor
private final class WindowHost {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let root = AppearanceController()

    init() {
        window.rootViewController = root
        window.makeKeyAndVisible()
        XCTAssertTrue(waitUntil { root.hasAppeared }, "真实窗口出现完成后才开始附件事务")
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }

    private func waitUntil(_ predicate: () -> Bool) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !predicate(), ProcessInfo.processInfo.systemUptime < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return predicate()
    }
}

@MainActor
private final class AppearanceController: UIViewController {
    private(set) var hasAppeared = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }
}

@MainActor
private final class WeakAttachment {
    weak var view: UIView?

    init(_ view: UIView) {
        self.view = view
    }
}

@MainActor
private final class AttachmentLedger {
    private(set) var records: [WeakAttachment] = []
    private(set) var unmounts = 0
    private var mountedIDs: Set<ObjectIdentifier> = []
    lazy var provider = LYGlyphTextAttachmentViewProvider(makeView: { [weak self] _ in
        guard let self else { return nil }
        let view = UIButton(type: .custom)
        records.append(WeakAttachment(view))
        XCTAssertTrue(mountedIDs.insert(ObjectIdentifier(view)).inserted)
        return view
    }, onUnmount: { [weak self] _, view in
        guard let self else { return }
        XCTAssertNil(view.superview)
        XCTAssertNotNil(mountedIDs.remove(ObjectIdentifier(view)))
        unmounts += 1
    })

    var liveIDs: Set<ObjectIdentifier> {
        Set(records.compactMap { $0.view.map(ObjectIdentifier.init) })
    }

    func liveIDs(in label: LYGlyphTextLabel) -> Set<ObjectIdentifier> {
        Set(records.compactMap { record in
            guard let view = record.view, view.isDescendant(of: label) else { return nil }
            return ObjectIdentifier(view)
        })
    }
}
