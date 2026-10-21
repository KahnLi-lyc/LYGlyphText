@testable import LYGlyphText
import SwiftUI
import UIKit
import XCTest

@MainActor
final class HostLayoutTests: XCTestCase {
    private let pixel: CGFloat = 0.5

    private final class FixedIntrinsicView: UIView {
        private let size: CGSize

        init(size: CGSize) {
            self.size = size
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("Use init(size:)")
        }

        override var intrinsicContentSize: CGSize {
            size
        }
    }

    private final class HostedContent {
        let window: UIWindow
        let root: UIViewController
        let child: UIViewController

        init(size: CGSize = CGSize(width: 390, height: 844), makeVisible: Bool = true) {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
            root = UIViewController()
            child = UIViewController()
            window.rootViewController = root
            root.addChild(child)
            root.view.addSubview(child.view)
            child.view.frame = root.view.bounds
            child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            root.setOverrideTraitCollection(UITraitCollection(displayScale: 2), forChild: child)
            child.didMove(toParent: root)
            if makeVisible { show() }
        }

        func add(_ view: UIView) {
            child.view.addSubview(view)
        }

        func show() {
            window.makeKeyAndVisible()
        }

        func close() {
            window.isHidden = true
        }
    }

    private func document(_ text: String? = nil) throws -> LYGlyphTextDocument {
        try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: text ?? String(repeating: "Stack 自动布局 English 😀 ", count: 10),
            attributes: [.font: UIFont.systemFont(ofSize: 20)]
        ))
    }

    private func viewDocument() throws -> LYGlyphTextDocument {
        try LYGlyphTextDocument(
            attributedText: NSAttributedString(
                string: "A\u{FFFC}B", attributes: [.font: UIFont.systemFont(ofSize: 20)]
            ),
            viewAttachments: [1: LYGlyphTextViewAttachment(
                id: "host-view", viewID: "badge", size: CGSize(width: 30, height: 20)
            )]
        )
    }

    private func label(document: LYGlyphTextDocument? = nil) throws -> LYGlyphTextLabel {
        let label = LYGlyphTextLabel(frame: .zero)
        label.document = try document ?? self.document()
        return label
    }

    private func settle(_ view: UIView) {
        for _ in 0 ..< 4 {
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    private func assertFiniteNonnegative(_ view: UIView, file: StaticString = #filePath, line: UInt = #line) {
        for value in [view.frame.minX, view.frame.minY, view.frame.width, view.frame.height] {
            XCTAssertTrue(value.isFinite, file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(view.frame.width, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(view.frame.height, 0, file: file, line: line)
    }

    private func glyphTextLabel(in view: UIView) -> LYGlyphTextLabel? {
        if let label = view as? LYGlyphTextLabel { return label }
        for subview in view.subviews {
            if let label = glyphTextLabel(in: subview) { return label }
        }
        return nil
    }

    func testHorizontalStackAcceptsPromisedAlignmentsAndDistributions() throws {
        let alignments: [UIStackView.Alignment] = [.fill, .top, .center, .bottom]
        let distributions: [UIStackView.Distribution] = [
            .fill, .fillEqually, .fillProportionally, .equalSpacing, .equalCentering
        ]
        let host = HostedContent()
        defer { host.close() }

        for alignment in alignments {
            for distribution in distributions {
                let label = try label()
                let button = UIButton(type: .system)
                button.setTitle("Button", for: .normal)
                let stack = UIStackView(arrangedSubviews: [label, button])
                stack.axis = .horizontal
                stack.alignment = alignment
                stack.distribution = distribution
                stack.spacing = 8
                label.setContentHuggingPriority(UILayoutPriority(249), for: .horizontal)
                label.setContentCompressionResistancePriority(UILayoutPriority(749), for: .horizontal)
                button.setContentHuggingPriority(UILayoutPriority(251), for: .horizontal)
                button.setContentCompressionResistancePriority(UILayoutPriority(751), for: .horizontal)
                stack.translatesAutoresizingMaskIntoConstraints = false
                host.add(stack)
                NSLayoutConstraint.activate([
                    stack.leadingAnchor.constraint(equalTo: host.child.view.leadingAnchor, constant: 20),
                    stack.topAnchor.constraint(equalTo: host.child.view.topAnchor, constant: 20),
                    stack.widthAnchor.constraint(equalToConstant: 350)
                ])
                settle(host.child.view)

                XCTAssertEqual(label.traitCollection.displayScale, 2)
                XCTAssertFalse(
                    stack.hasAmbiguousLayout,
                    "alignment=\(alignment.rawValue), distribution=\(distribution.rawValue)"
                )
                XCTAssertFalse(label.hasAmbiguousLayout)
                assertFiniteNonnegative(stack)
                assertFiniteNonnegative(label)
                assertFiniteNonnegative(button)
                for arranged in stack.arrangedSubviews {
                    XCTAssertGreaterThanOrEqual(arranged.frame.minX, -pixel)
                    XCTAssertLessThanOrEqual(arranged.frame.maxX, stack.bounds.maxX + pixel)
                }
                XCTAssertGreaterThan(label.bounds.width, 0)
                XCTAssertEqual(
                    label.bounds.height,
                    label.sizeThatFits(CGSize(width: label.bounds.width, height: CGFloat.infinity)).height,
                    accuracy: pixel
                )
                stack.removeFromSuperview()
            }
        }
    }

    func testVerticalStackAcceptsPromisedAlignmentsAndDistributions() throws {
        let alignments: [UIStackView.Alignment] = [.fill, .leading, .center, .trailing]
        let distributions: [UIStackView.Distribution] = [
            .fill, .fillEqually, .fillProportionally, .equalSpacing, .equalCentering
        ]
        let host = HostedContent()
        defer { host.close() }

        for alignment in alignments {
            for distribution in distributions {
                let label = try label()
                let width: CGFloat = 240
                let natural = label.sizeThatFits(CGSize(width: width, height: CGFloat.infinity))
                let peer = FixedIntrinsicView(size: CGSize(width: 80, height: natural.height))
                let stack = UIStackView(arrangedSubviews: [label, peer])
                stack.axis = .vertical
                stack.alignment = alignment
                stack.distribution = distribution
                stack.spacing = 8
                stack.frame = CGRect(x: 20, y: 20, width: width, height: natural.height * 2 + stack.spacing)
                label.widthAnchor.constraint(equalToConstant: width).isActive = true
                host.add(stack)
                settle(stack)

                XCTAssertEqual(label.traitCollection.displayScale, 2)
                XCTAssertFalse(
                    stack.hasAmbiguousLayout,
                    "alignment=\(alignment.rawValue), distribution=\(distribution.rawValue)"
                )
                XCTAssertFalse(label.hasAmbiguousLayout)
                assertFiniteNonnegative(stack)
                assertFiniteNonnegative(label)
                assertFiniteNonnegative(peer)
                for arranged in stack.arrangedSubviews {
                    XCTAssertGreaterThanOrEqual(arranged.frame.minY, -pixel)
                    XCTAssertLessThanOrEqual(arranged.frame.maxY, stack.bounds.maxY + pixel)
                }
                XCTAssertEqual(label.bounds.width, width, accuracy: pixel)
                XCTAssertEqual(
                    label.bounds.height,
                    label.sizeThatFits(CGSize(width: width, height: CGFloat.infinity)).height,
                    accuracy: pixel
                )
                stack.removeFromSuperview()
            }
        }
    }

    func testSiblingButtonAndBothAxisPrioritiesSurviveEveryInputUpdate() throws {
        let host = HostedContent()
        defer { host.close() }
        let label = try label(document: viewDocument())
        label.setContentHuggingPriority(UILayoutPriority(249), for: .horizontal)
        label.setContentCompressionResistancePriority(UILayoutPriority(751), for: .horizontal)
        label.setContentHuggingPriority(UILayoutPriority(260), for: .vertical)
        label.setContentCompressionResistancePriority(UILayoutPriority(752), for: .vertical)
        let button = UIButton(type: .system)
        button.setTitle("Sibling", for: .normal)
        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.frame = CGRect(x: 20, y: 20, width: 350, height: 120)
        host.add(stack)
        let provider = LYGlyphTextAttachmentViewProvider { _ in UIView() }
        let rebound = try viewDocument()

        func assertPriorities() {
            XCTAssertEqual(label.contentHuggingPriority(for: .horizontal).rawValue, 249)
            XCTAssertEqual(label.contentCompressionResistancePriority(for: .horizontal).rawValue, 751)
            XCTAssertEqual(label.contentHuggingPriority(for: .vertical).rawValue, 260)
            XCTAssertEqual(label.contentCompressionResistancePriority(for: .vertical).rawValue, 752)
        }

        assertPriorities()
        label.document = try document("替换文档 " + String(repeating: "内容 ", count: 20))
        assertPriorities()
        label.configuration = LYGlyphTextConfiguration(
            textContainerInset: UIEdgeInsets(top: 3, left: 4, bottom: 5, right: 6)
        )
        assertPriorities()
        label.document = rebound
        label.viewProvider = provider
        settle(stack)
        assertPriorities()
        label.reloadAttachments()
        settle(stack)
        assertPriorities()
        label.onAction = nil
        label.document = nil
        label.viewProvider = nil
        assertPriorities()
        label.document = rebound
        label.viewProvider = provider
        settle(stack)
        assertPriorities()
        XCTAssertFalse(button.frame.intersects(label.frame))
    }

    func testStableBoundsConvergeAndRecentTwoWidthsStayCached() throws {
        let label = try label()
        label.resetLayoutMeasurementCounts()
        let widths: [CGFloat?] = [nil, 160, 240, 160, 320]
        let expectedBuilds = [1, 2, 3, 3, 4]
        for (index, width) in widths.enumerated() {
            _ = label.measuredLayout(width: width)
            let snapshot = label.layoutMeasurementSnapshot
            XCTAssertEqual(snapshot.layoutBuildCount, expectedBuilds[index])
            XCTAssertLessThanOrEqual(snapshot.cachedLayoutCount, 2)
        }

        let host = HostedContent()
        defer { host.close() }
        label.frame = CGRect(x: 20, y: 20, width: 320, height: 300)
        host.add(label)
        settle(label)
        let stable = label.layoutMeasurementSnapshot
        settle(label)
        XCTAssertEqual(label.layoutMeasurementSnapshot, stable)

        let provider = LYGlyphTextAttachmentViewProvider { _ in UIView() }
        label.viewProvider = provider
        label.viewProvider = provider
        label.onAction = { _ in }
        label.onAction = { _ in }
        label.reloadAttachments()
        settle(label)
        XCTAssertEqual(label.layoutMeasurementSnapshot, stable)

        label.resetLayoutMeasurementCounts()
        XCTAssertEqual(label.layoutMeasurementSnapshot.layoutBuildCount, 0)
        XCTAssertEqual(label.layoutMeasurementSnapshot.intrinsicInvalidationCount, 0)
        XCTAssertEqual(label.layoutMeasurementSnapshot.cachedLayoutCount, stable.cachedLayoutCount)
        label.preferredMaxLayoutWidth = 160
        label.preferredMaxLayoutWidth = 160
        XCTAssertEqual(label.layoutMeasurementSnapshot.intrinsicInvalidationCount, 1)
        label.preferredMaxLayoutWidth = .infinity
        XCTAssertEqual(label.layoutMeasurementSnapshot.intrinsicInvalidationCount, 2)

        label.resetLayoutMeasurementCounts()
        label.bounds.size.width = 180
        settle(label)
        XCTAssertEqual(label.layoutMeasurementSnapshot.intrinsicInvalidationCount, 1)
        label.bounds.size.width = 180
        settle(label)
        XCTAssertEqual(label.layoutMeasurementSnapshot.intrinsicInvalidationCount, 1)
        label.bounds.size.width = 280
        settle(label)
        XCTAssertEqual(label.layoutMeasurementSnapshot.intrinsicInvalidationCount, 2)
        label.bounds.origin = CGPoint(x: 7, y: 9)
        settle(label)
        XCTAssertEqual(label.layoutMeasurementSnapshot.intrinsicInvalidationCount, 2)

        label.resetLayoutMeasurementCounts()
        let sameDocument = label.document
        label.document = sameDocument
        XCTAssertEqual(label.layoutMeasurementSnapshot.intrinsicInvalidationCount, 0)
        label.document = try document("新的宿主文档")
        XCTAssertEqual(label.layoutMeasurementSnapshot.intrinsicInvalidationCount, 1)
        let sameConfiguration = label.configuration
        label.configuration = sameConfiguration
        XCTAssertEqual(label.layoutMeasurementSnapshot.intrinsicInvalidationCount, 1)
        label.configuration.numberOfLines = 2
        XCTAssertEqual(label.layoutMeasurementSnapshot.intrinsicInvalidationCount, 2)
    }

    func testZeroPositiveAndNarrowWideNarrowWidthsReturnStableHeights() throws {
        let label = try label()
        let zero = label.sizeThatFits(CGSize(width: 0, height: CGFloat.infinity))
        let firstNarrow = label.sizeThatFits(CGSize(width: 160, height: CGFloat.infinity))
        let wide = label.sizeThatFits(CGSize(width: 280, height: CGFloat.infinity))
        let secondNarrow = label.sizeThatFits(CGSize(width: 160, height: CGFloat.infinity))
        let positiveAfterZero = try self.label().sizeThatFits(CGSize(width: 160, height: CGFloat.infinity))

        for size in [zero, firstNarrow, wide, secondNarrow, positiveAfterZero] {
            XCTAssertTrue(size.width.isFinite)
            XCTAssertTrue(size.height.isFinite)
            XCTAssertGreaterThanOrEqual(size.width, 0)
            XCTAssertGreaterThanOrEqual(size.height, 0)
        }
        XCTAssertEqual(zero.width, 0)
        XCTAssertEqual(firstNarrow.height, positiveAfterZero.height, accuracy: pixel)
        XCTAssertEqual(firstNarrow.height, secondNarrow.height, accuracy: pixel)
        XCTAssertGreaterThan(firstNarrow.height, wide.height)
    }

    func testUIKitAndSwiftUIFiniteWidthHeightsDifferByAtMostOnePixel() throws {
        let document = try document()
        let configuration = LYGlyphTextConfiguration()
        for width: CGFloat in [90, 160, 240, 320] {
            let host = HostedContent(makeVisible: false)
            let label = try label(document: document)
            label.configuration = configuration
            label.frame = CGRect(x: 0, y: 100, width: width, height: 600)
            host.add(label)

            let controller = UIHostingController(rootView: LYGlyphTextView(
                document: document,
                configuration: configuration
            ).frame(width: width))
            host.child.addChild(controller)
            host.add(controller.view)
            controller.view.frame = CGRect(x: 0, y: 100, width: width, height: 600)
            controller.didMove(toParent: host.child)
            controller.loadViewIfNeeded()
            host.show()
            settle(host.child.view)

            defer {
                host.close()
                label.removeFromSuperview()
                controller.willMove(toParent: nil)
                controller.view.removeFromSuperview()
                controller.removeFromParent()
            }

            let swiftUILabel = try XCTUnwrap(glyphTextLabel(in: controller.view))
            XCTAssertEqual(label.traitCollection.displayScale, 2)
            XCTAssertEqual(controller.traitCollection.displayScale, 2)
            XCTAssertEqual(swiftUILabel.traitCollection.displayScale, 2)
            XCTAssertEqual(label.traitCollection.displayScale, swiftUILabel.traitCollection.displayScale)
            let swiftUI = controller.sizeThatFits(in: CGSize(width: width, height: 10000))
            let uiKit = label.sizeThatFits(CGSize(width: width, height: CGFloat.infinity))
            XCTAssertEqual(swiftUI.height, uiKit.height, accuracy: pixel)
        }
    }
}
