import Combine
@testable import LYGlyphText
import SwiftUI
import UIKit
import XCTest

@MainActor
final class SwiftUIHostTests: XCTestCase {
    private let pixel: CGFloat = 0.5

    func testProposalNilZeroFiniteInfinityAndDisplayHeightArePure() throws {
        let label = LYGlyphTextLabel(frame: CGRect(x: 7, y: 9, width: 31, height: 41))
        let descriptor = LYGlyphTextViewAttachment(
            id: "proposal-view", viewID: "badge", size: CGSize(width: 32, height: 18)
        )
        let source = NSAttributedString(
            string: "Proposal \u{FFFC} 测量需要保持原始视图状态。",
            attributes: [.font: UIFont.systemFont(ofSize: 18)]
        )
        let document = try LYGlyphTextDocument(attributedText: source, viewAttachments: [9: descriptor])
        var factoryCount = 0
        let provider = LYGlyphTextAttachmentViewProvider { _ in
            factoryCount += 1
            return UIView()
        }
        label.document = document
        label.viewProvider = provider
        label.translatesAutoresizingMaskIntoConstraints = false
        let widthConstraint = label.widthAnchor.constraint(equalToConstant: 222)
        let heightConstraint = label.heightAnchor.constraint(greaterThanOrEqualToConstant: 11)
        NSLayoutConstraint.activate([widthConstraint, heightConstraint])
        let originalFrame = label.frame
        let originalBounds = label.bounds
        let originalConstraints = label.constraints.map(ObjectIdentifier.init)
        let originalDocument = label.document
        let originalProvider = label.viewProvider
        let originalNeedsLayout = label.layer.needsLayout()
        let before = label.layoutMeasurementSnapshot

        let ideal = LYGlyphTextView.measuredSize(
            proposal: ProposedViewSize(width: nil, height: 1), displayHeight: nil, label: label
        )
        let infinite = LYGlyphTextView.measuredSize(
            proposal: ProposedViewSize(width: .infinity, height: 0), displayHeight: nil, label: label
        )
        let zero = LYGlyphTextView.measuredSize(
            proposal: ProposedViewSize(width: 0, height: 1), displayHeight: nil, label: label
        )
        let finite = LYGlyphTextView.measuredSize(
            proposal: ProposedViewSize(width: 120, height: 1), displayHeight: nil, label: label
        )
        let displayed = LYGlyphTextView.measuredSize(
            proposal: ProposedViewSize(width: 120, height: 999), displayHeight: 13, label: label
        )
        let invalidDisplay = LYGlyphTextView.measuredSize(
            proposal: ProposedViewSize(width: 120, height: 1), displayHeight: -.infinity, label: label
        )
        let nanWidth = LYGlyphTextView.measuredSize(
            proposal: ProposedViewSize(width: .nan, height: 1), displayHeight: nil, label: label
        )
        let negativeInfiniteWidth = LYGlyphTextView.measuredSize(
            proposal: ProposedViewSize(width: -.infinity, height: 1), displayHeight: nil, label: label
        )
        let negativeWidth = LYGlyphTextView.measuredSize(
            proposal: ProposedViewSize(width: -12, height: 1), displayHeight: nil, label: label
        )
        let zeroDisplay = LYGlyphTextView.measuredSize(
            proposal: ProposedViewSize(width: 120, height: 1), displayHeight: 0, label: label
        )
        let negativeDisplay = LYGlyphTextView.measuredSize(
            proposal: ProposedViewSize(width: 120, height: 1), displayHeight: -1, label: label
        )
        let nanDisplay = LYGlyphTextView.measuredSize(
            proposal: ProposedViewSize(width: 120, height: 1), displayHeight: .nan, label: label
        )
        let infiniteDisplay = LYGlyphTextView.measuredSize(
            proposal: ProposedViewSize(width: 120, height: 1), displayHeight: .infinity, label: label
        )

        XCTAssertEqual(ideal, infinite)
        XCTAssertGreaterThan(ideal.width, 0)
        XCTAssertGreaterThan(ideal.height, 0)
        XCTAssertEqual(zero.width, 0)
        XCTAssertEqual(finite.width, 120)
        XCTAssertGreaterThan(finite.height, 0)
        XCTAssertEqual(displayed, CGSize(width: 120, height: 13))
        XCTAssertEqual(invalidDisplay, finite)
        XCTAssertEqual(nanWidth, ideal)
        XCTAssertEqual(negativeInfiniteWidth, ideal)
        XCTAssertEqual(negativeWidth, zero)
        XCTAssertEqual(zeroDisplay, CGSize(width: 120, height: 0))
        XCTAssertEqual(negativeDisplay, finite)
        XCTAssertEqual(nanDisplay, finite)
        XCTAssertEqual(infiniteDisplay, finite)
        XCTAssertEqual(label.frame, originalFrame)
        XCTAssertEqual(label.bounds, originalBounds)
        XCTAssertEqual(label.constraints.map(ObjectIdentifier.init), originalConstraints)
        XCTAssertTrue(label.document === originalDocument)
        XCTAssertTrue(label.viewProvider === originalProvider)
        XCTAssertEqual(label.layer.needsLayout(), originalNeedsLayout)
        XCTAssertEqual(label.layoutMeasurementSnapshot.intrinsicInvalidationCount, before.intrinsicInvalidationCount)
        XCTAssertEqual(factoryCount, 0)
        XCTAssertTrue(label.subviews.isEmpty)
        XCTAssertNil(label.superview)
    }

    func testFrameHStackVStackUseActualUnderlyingLabelWidthAndMatchUIKitHeight() throws {
        let value = try document("SwiftUI 容器使用实际提议宽度，和 UIKit 共享同一自然高度。第二行用于验证换行。")
        let configuration = LYGlyphTextConfiguration(
            textContainerInset: .init(top: 3, left: 5, bottom: 7, right: 11)
        )
        for kind in ContainerKind.allCases {
            let controller = UIHostingController(rootView: container(
                kind,
                document: value,
                configuration: configuration
            ))
            let window = host(controller, width: 240)
            defer { window.isHidden = true }
            settle(controller.view)
            let label = try XCTUnwrap(findLabel(in: controller.view))
            XCTAssertEqual(label.bounds.width, kind.labelWidth, accuracy: pixel, "\(kind)")
            let uikitLabel = LYGlyphTextLabel(frame: .zero)
            uikitLabel.contentScaleFactor = label.traitCollection.displayScale
            uikitLabel.configuration = configuration
            uikitLabel.document = value
            let expected = uikitLabel.sizeThatFits(
                CGSize(width: label.bounds.width, height: .infinity)
            ).height
            let physicalPixel = 1 / max(1, label.traitCollection.displayScale)
            XCTAssertEqual(label.bounds.height, expected, accuracy: physicalPixel, "\(kind)")
            XCTAssertFalse(label === uikitLabel)
        }
    }

    func testListAndLazyVStackKeepFortyStableRowIDsAndCurrentDocuments() throws {
        for isList in [true, false] {
            let model = try RowModel()
            let controller = UIHostingController(
                rootView: RowFixture(model: model, isList: isList, content: .action)
            )
            let window = host(controller, width: 320, height: 420)
            defer { window.isHidden = true }
            settle(controller.view)
            XCTAssertEqual(model.rows.map(\.id), Array(0 ..< 40))
            assertVisibleRows(in: controller.view, model: model, content: .action)

            let firstActionLabel = try XCTUnwrap(label(for: model.rows[0], content: .action, in: controller.view))
            fireFirstAction(in: firstActionLabel)
            XCTAssertEqual(model.rows[0].state.actionCount, 1)
            XCTAssertNil(firstActionLabel.pressedActionIndex)
            XCTAssertTrue(model.rows.dropFirst().allSatisfy { $0.state.actionCount == 0 })

            let scroll = try XCTUnwrap(primaryScrollView(in: controller.view))
            scrollToBottom(scroll, in: controller.view)
            let visibleActionIDs = visibleRowIDs(in: controller.view, model: model, content: .action)
            XCTAssertFalse(visibleActionIDs.isEmpty)
            XCTAssertFalse(visibleActionIDs.contains(0))
            XCTAssertTrue(visibleActionIDs.allSatisfy { rowID in
                model.rows[rowID].state.actionCount == 0 && model.rows[rowID].state.buttonCount == 0
            })
            scrollToTop(scroll, in: controller.view)
            XCTAssertEqual(model.rows[0].state.actionCount, 1)

            controller.rootView = RowFixture(model: model, isList: isList, content: .view)
            settle(controller.view)
            let firstViewLabel = try XCTUnwrap(label(for: model.rows[0], content: .view, in: controller.view))
            let firstButton = try XCTUnwrap(descendantButton(in: firstViewLabel))
            firstButton.sendActions(for: .touchUpInside)
            XCTAssertEqual(model.rows[0].state.buttonCount, 1)
            XCTAssertTrue(model.rows.dropFirst().allSatisfy { $0.state.buttonCount == 0 })

            let viewScroll = try XCTUnwrap(primaryScrollView(in: controller.view))
            scrollToBottom(viewScroll, in: controller.view)
            let visibleViewIDs = visibleRowIDs(in: controller.view, model: model, content: .view)
            XCTAssertFalse(visibleViewIDs.isEmpty)
            XCTAssertFalse(visibleViewIDs.contains(0))
            XCTAssertTrue(visibleViewIDs.allSatisfy { rowID in
                model.rows[rowID].state.actionCount == 0 && model.rows[rowID].state.buttonCount == 0
            })
            scrollToTop(viewScroll, in: controller.view)
            XCTAssertEqual(model.rows[0].state.actionCount, 1)
            XCTAssertEqual(model.rows[0].state.buttonCount, 1)
        }
    }

    func testSameDocumentCallbackAndProviderUpdatesPreserveLayoutWhileUsingLatestInputs() throws {
        let descriptor = LYGlyphTextViewAttachment(
            id: "view", viewID: "button", size: CGSize(width: 48, height: 24), isInteractive: true
        )
        let source = NSMutableAttributedString(string: "动作 ")
        let location = source.length
        source.append(NSAttributedString(string: "点击\u{FFFC}"))
        let document = try LYGlyphTextDocument(
            attributedText: source,
            viewAttachments: [source.length - 1: descriptor],
            actions: [.init(actionID: "latest", range: NSRange(location: location, length: 2))]
        )
        var first = 0
        var second = 0
        var firstBuilds = 0
        let firstProvider = LYGlyphTextAttachmentViewProvider { _ in
            firstBuilds += 1
            return UIButton(type: .system)
        }
        var secondBuilds = 0
        let secondProvider = LYGlyphTextAttachmentViewProvider { _ in
            secondBuilds += 1
            return UIButton(type: .system)
        }
        let controller = UIHostingController(rootView: LYGlyphTextView(
            document: document, viewProvider: firstProvider, onAction: { _ in first += 1 }
        ).frame(width: 240))
        let window = host(controller, width: 320)
        defer { window.isHidden = true }
        settle(controller.view)
        let label = try XCTUnwrap(findLabel(in: controller.view))
        label.layoutIfNeeded()
        let before = label.layoutMeasurementSnapshot
        XCTAssertEqual(firstBuilds, 1)

        controller.rootView = LYGlyphTextView(
            document: document, viewProvider: firstProvider, onAction: { _ in second += 1 }
        ).frame(width: 240)
        settle(controller.view)
        XCTAssertEqual(firstBuilds, 1)
        XCTAssertEqual(label.layoutMeasurementSnapshot, before)
        fireFirstAction(in: label)
        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 1)

        controller.rootView = LYGlyphTextView(
            document: document, viewProvider: secondProvider, onAction: { _ in second += 1 }
        ).frame(width: 240)
        settle(controller.view)
        XCTAssertEqual(firstBuilds, 1)
        XCTAssertEqual(secondBuilds, 1)
        XCTAssertEqual(label.layoutMeasurementSnapshot, before)
    }

    func testClearReplaceAndDismantleReleasePressedAttachmentAndCallbackState() throws {
        let descriptor = LYGlyphTextViewAttachment(
            id: "view", viewID: "badge", size: CGSize(width: 40, height: 20)
        )
        let source = NSAttributedString(string: "A\u{FFFC}")
        let first = try LYGlyphTextDocument(
            attributedText: source,
            viewAttachments: [1: descriptor],
            actions: [.init(actionID: "all", range: NSRange(location: 0, length: 2))]
        )
        let replacement = try document("replacement")
        let provider = LYGlyphTextAttachmentViewProvider { _ in UIView() }
        let label = LYGlyphTextLabel(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        label.onAction = { _ in }
        label.document = first
        label.viewProvider = provider
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        window.addSubview(label)
        window.isHidden = false
        label.layoutIfNeeded()
        fireFirstAction(in: label, end: false)
        XCTAssertNotNil(label.pressedActionIndex)
        XCTAssertFalse(label.subviews.isEmpty)

        label.document = replacement
        XCTAssertNil(label.pressedActionIndex)
        XCTAssertTrue(label.subviews.isEmpty)
        label.document = nil
        LYGlyphTextView.dismantleUIView(label, coordinator: ())
        XCTAssertNil(label.document)
        XCTAssertNil(label.viewProvider)
        XCTAssertNil(label.onAction)
        XCTAssertNil(label.pressedActionIndex)
        XCTAssertTrue(label.subviews.isEmpty)
        window.isHidden = true
    }

    private enum ContainerKind: CaseIterable, CustomStringConvertible {
        case frame, hStack, vStack

        var labelWidth: CGFloat {
            switch self {
            case .frame, .vStack: 160
            case .hStack: 140
            }
        }

        var description: String {
            switch self {
            case .frame: "frame"
            case .hStack: "HStack"
            case .vStack: "VStack"
            }
        }
    }

    private struct RowValue: Identifiable {
        let id: Int
        let actionDocument: LYGlyphTextDocument
        let viewDocument: LYGlyphTextDocument
        let state: RowState
    }

    private enum RowContent: Equatable {
        case action
        case view
    }

    @MainActor
    private final class RowState: ObservableObject {
        let rowID: Int
        @Published private(set) var actionCount = 0
        @Published private(set) var buttonCount = 0
        lazy var provider = LYGlyphTextAttachmentViewProvider { [weak self] _ in
            let button = UIButton(type: .system)
            button.addAction(UIAction { [weak self] _ in self?.buttonCount += 1 }, for: .touchUpInside)
            return button
        }

        init(rowID: Int) {
            self.rowID = rowID
        }

        func receive(_: LYGlyphTextActionEvent) {
            actionCount += 1
        }
    }

    @MainActor
    private final class RowModel {
        let rows: [RowValue]

        init() throws {
            rows = try (0 ..< 40).map { index in
                let actionSource = NSMutableAttributedString(
                    string: "row \(index) action",
                    attributes: [.font: UIFont.systemFont(ofSize: 18)]
                )
                let actionRange = (actionSource.string as NSString).range(of: "action")
                let actionDocument = try LYGlyphTextDocument(
                    attributedText: actionSource,
                    actions: [.init(actionID: "row-action-\(index)", range: actionRange)]
                )
                let viewSource = NSAttributedString(
                    string: "row \(index) \u{FFFC}",
                    attributes: [.font: UIFont.systemFont(ofSize: 18)]
                )
                let viewDocument = try LYGlyphTextDocument(
                    attributedText: viewSource,
                    viewAttachments: [viewSource.length - 1: .init(
                        id: "row-view-\(index)", viewID: "button", size: CGSize(width: 44, height: 24),
                        isInteractive: true
                    )]
                )
                return RowValue(
                    id: index,
                    actionDocument: actionDocument,
                    viewDocument: viewDocument,
                    state: RowState(rowID: index)
                )
            }
        }
    }

    private struct RowFixture: View {
        let model: RowModel
        let isList: Bool
        let content: RowContent

        var body: some View {
            Group {
                if isList {
                    List(model.rows) { row in
                        RowFixtureContent(row: row, content: content)
                    }
                } else {
                    ScrollView {
                        LazyVStack {
                            ForEach(model.rows) { row in
                                RowFixtureContent(row: row, content: content)
                            }
                        }
                    }
                }
            }
        }
    }

    private struct RowFixtureContent: View {
        let row: RowValue
        let content: RowContent
        @ObservedObject private var state: RowState

        init(row: RowValue, content: RowContent) {
            self.row = row
            self.content = content
            _state = ObservedObject(wrappedValue: row.state)
        }

        var body: some View {
            let document = content == .action ? row.actionDocument : row.viewDocument
            VStack(alignment: .leading) {
                LYGlyphTextView(
                    document: document,
                    viewProvider: state.provider,
                    onAction: state.receive
                )
                Text("row=\(state.rowID);event=\(state.actionCount);button=\(state.buttonCount)")
            }
            .id(row.id)
        }
    }

    @ViewBuilder
    private func container(
        _ kind: ContainerKind,
        document: LYGlyphTextDocument,
        configuration: LYGlyphTextConfiguration
    ) -> some View {
        switch kind {
        case .frame:
            LYGlyphTextView(document: document, configuration: configuration).frame(width: 160)
        case .hStack:
            HStack(spacing: 0) {
                Color.clear.frame(width: 100)
                LYGlyphTextView(document: document, configuration: configuration)
            }
        case .vStack:
            VStack(spacing: 0) {
                LYGlyphTextView(document: document, configuration: configuration).frame(width: 160)
                Color.clear.frame(height: 10)
            }
        }
    }

    private static func document(_ value: String) throws -> LYGlyphTextDocument {
        try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: value,
            attributes: [.font: UIFont.systemFont(ofSize: 18)]
        ))
    }

    private func document(_ value: String) throws -> LYGlyphTextDocument {
        try Self.document(value)
    }

    private func host(_ controller: UIViewController, width: CGFloat, height: CGFloat = 500) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        settle(controller.view)
        return window
    }

    private func settle(_ view: UIView) {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        view.layoutIfNeeded()
    }

    private func findLabel(in view: UIView) -> LYGlyphTextLabel? {
        if let label = view as? LYGlyphTextLabel { return label }
        return view.subviews.lazy.compactMap(findLabel).first
    }

    private func allLabels(in view: UIView) -> [LYGlyphTextLabel] {
        (view as? LYGlyphTextLabel).map { [$0] } ?? view.subviews.flatMap(allLabels)
    }

    private func label(for row: RowValue, content: RowContent, in view: UIView) -> LYGlyphTextLabel? {
        let document = content == .action ? row.actionDocument : row.viewDocument
        return allLabels(in: view).first { $0.document === document }
    }

    private func visibleRowIDs(in view: UIView, model: RowModel, content: RowContent) -> Set<Int> {
        Set(allLabels(in: view).filter(isVisible).compactMap { label in
            model.rows.first { row in
                let document = content == .action ? row.actionDocument : row.viewDocument
                return label.document === document
            }?.id
        })
    }

    private func assertVisibleRows(in view: UIView, model: RowModel, content: RowContent) {
        let labels = allLabels(in: view)
        XCTAssertFalse(labels.isEmpty)
        for label in labels {
            let matches = model.rows.filter { row in
                let document = content == .action ? row.actionDocument : row.viewDocument
                return label.document === document
            }
            XCTAssertEqual(matches.count, 1)
            XCTAssertEqual(matches.first?.state.rowID, matches.first?.id)
        }
    }

    private func primaryScrollView(in view: UIView) -> UIScrollView? {
        ([view] + view.subviews.flatMap(allViews)).compactMap { $0 as? UIScrollView }.max {
            $0.contentSize.height < $1.contentSize.height
        }
    }

    private func allViews(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(allViews)
    }

    private func scrollToBottom(_ scroll: UIScrollView, in view: UIView) {
        let y = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.scrollRectToVisible(CGRect(x: 0, y: y, width: 1, height: 1), animated: false)
        settle(view)
        settle(view)
    }

    private func scrollToTop(_ scroll: UIScrollView, in view: UIView) {
        scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
        scroll.layoutIfNeeded()
        settle(view)
        settle(view)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        settle(view)
    }

    private func isVisible(_ view: UIView?) -> Bool {
        guard let view, let window = view.window, !view.isHidden, view.alpha > 0 else { return false }
        return view.convert(view.bounds, to: window).intersects(window.bounds)
    }

    private func descendantButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton { return button }
        return view.subviews.lazy.compactMap(descendantButton).first
    }

    private func fireFirstAction(in label: LYGlyphTextLabel, end: Bool = true) {
        let layout = label.measuredLayout(width: label.bounds.width)
        guard let entry = ActionGeometry(
            layout: layout, bounds: label.bounds, configuration: label.configuration
        ).entries.first, let rect = entry.rects.first else {
            XCTFail("缺少动作几何")
            return
        }
        let point = CGPoint(x: rect.midX, y: rect.midY)
        XCTAssertTrue(label.beginActionInteraction(at: point, touchedView: label))
        if end { label.endActionInteraction(at: point) }
    }
}
