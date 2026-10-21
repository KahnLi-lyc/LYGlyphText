@testable import LYGlyphText
@testable import LYGlyphTextDemo
import SwiftUI
import UIKit
import XCTest

@MainActor
final class HostMatrixDemoHostTests: XCTestCase {
    func testSamplesExposeFortyStableRowsAndDeclaredAttachmentRevisions() throws {
        let samples = try HostMatrixSamples()
        XCTAssertEqual(samples.rows.map(\.id), Array(0 ..< 40))
        for row in samples.rows {
            XCTAssertEqual(Set(row.documents.keys), Set(HostMatrixContent.allCases))
            XCTAssertEqual(row.documents[.smallImage]?.attachments.values.first?.size, CGSize(width: 20, height: 20))
            XCTAssertEqual(row.documents[.largeImage]?.attachments.values.first?.size, CGSize(width: 48, height: 64))
            XCTAssertEqual(row.documents[.smallView]?.viewAttachments.values.first?.size, CGSize(width: 44, height: 24))
            XCTAssertEqual(row.documents[.largeView]?.viewAttachments.values.first?.size, CGSize(width: 96, height: 52))
            XCTAssertEqual(row.documents[.action]?.actions.first?.actionID, "host-row-\(row.id)")
        }
    }

    func testTableAndCollectionHostsOwnSizingAndReusePolicies() throws {
        let samples = try HostMatrixSamples()
        let table = HostMatrixTableController(samples: samples)
        table.loadViewIfNeeded()
        XCTAssertEqual(table.tableView.rowHeight, UITableView.automaticDimension)
        XCTAssertEqual(table.tableView.numberOfRows(inSection: 0), 40)
        XCTAssertTrue(table.tableView.dataSource === table)
        XCTAssertTrue(table.tableView.delegate === table)

        let collection = HostMatrixCollectionController(samples: samples)
        collection.loadViewIfNeeded()
        XCTAssertEqual(collection.collectionView.numberOfItems(inSection: 0), 40)
        XCTAssertTrue(collection.collectionView.dataSource === collection)
        XCTAssertTrue(collection.collectionView.delegate === collection)
        let layout = collection.collectionView.collectionViewLayout
        XCTAssertTrue(layout is UICollectionViewCompositionalLayout)

        collection.view.frame = CGRect(x: 0, y: 0, width: 320, height: 844)
        collection.view.setNeedsLayout()
        collection.view.layoutIfNeeded()
        let initialInvalidations = collection.layoutInvalidationCount
        collection.view.frame.size.width = 600
        collection.view.setNeedsLayout()
        collection.view.layoutIfNeeded()
        XCTAssertTrue(collection.collectionView.collectionViewLayout === layout)
        XCTAssertGreaterThan(collection.layoutInvalidationCount, initialInvalidations)

        let stableInvalidations = collection.layoutInvalidationCount
        collection.view.setNeedsLayout()
        collection.view.layoutIfNeeded()
        XCTAssertEqual(collection.layoutInvalidationCount, stableInvalidations)
    }

    func testRowStateProviderUsesIndependentButtonStateAndResetsCallback() throws {
        let samples = try HostMatrixSamples()
        let first = HostMatrixRowState(rowID: 0)
        let second = HostMatrixRowState(rowID: 1)
        let descriptor = try XCTUnwrap(samples.rows[0].documents[.smallView]?.viewAttachments.values.first)
        let firstButton = try XCTUnwrap(first.provider.makeView(descriptor) as? UIButton)
        let secondButton = try XCTUnwrap(second.provider.makeView(descriptor) as? UIButton)
        firstButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(first.buttonCount, 1)
        XCTAssertEqual(second.buttonCount, 0)
        secondButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(second.buttonCount, 1)
        first.selectCallback(.b)
        first.receive(LYGlyphTextActionEvent(
            actionID: "host-row-0",
            range: NSRange(location: 0, length: 1),
            visibleRects: [.zero],
            kind: .tap
        ))
        XCTAssertEqual(first.actionCount, 1)
        XCTAssertEqual(first.lastHandledCallback, .b)
        XCTAssertEqual(first.lastActionID, "host-row-0")
        first.resetForReuse()
        XCTAssertEqual(first.buttonCount, 0)
        XCTAssertEqual(first.actionCount, 0)
        XCTAssertEqual(first.callback, .a)
        XCTAssertNil(first.lastHandledCallback)
        XCTAssertNil(first.lastActionID)
    }

    func testUIKitHostMatrixAppliesWidthContentAndRoutesToExistingListHosts() throws {
        let samples = try HostMatrixSamples()
        let controller = UIKitHostMatrixController(samples: samples)
        let navigation = UINavigationController(rootViewController: controller)
        let window = host(navigation)
        defer { window.isHidden = true }
        let width = try XCTUnwrap(find("hostUIKitWidth", in: controller.view) as? UISegmentedControl)
        let content = try XCTUnwrap(find("hostUIKitContent", in: controller.view) as? UISegmentedControl)
        width.selectedSegmentIndex = 0
        width.sendActions(for: .valueChanged)
        content.selectedSegmentIndex = HostMatrixContent.longText.rawValue
        content.sendActions(for: .valueChanged)
        settle(controller.view)
        XCTAssertEqual(controller.glyphLabel.bounds.width, 160, accuracy: 0.5)
        XCTAssertTrue(controller.glyphLabel.document === samples.rows[0].documents[.longText])

        let table = try XCTUnwrap(find("openHostTable", in: controller.view) as? UIButton)
        table.sendActions(for: .touchUpInside)
        XCTAssertTrue(navigation.topViewController is HostMatrixTableController)
        navigation.popViewController(animated: false)
        let collection = try XCTUnwrap(find("openHostCollection", in: controller.view) as? UIButton)
        collection.sendActions(for: .touchUpInside)
        XCTAssertTrue(navigation.topViewController is HostMatrixCollectionController)
    }

    func testSwiftUIHostMatrixMountsFrameAndUsesIndependentFortyRowStateModel() throws {
        let samples = try HostMatrixSamples()
        let controller = UIHostingController(rootView: SwiftUIHostMatrixView(samples: samples))
        let window = host(controller)
        defer { window.isHidden = true }
        settle(controller.view)
        let label = try XCTUnwrap(allViews(in: controller.view).compactMap { $0 as? LYGlyphTextLabel }.first)
        XCTAssertEqual(label.bounds.width, 240, accuracy: 0.5)
        XCTAssertTrue(label.document === samples.rows[0].documents[.action])
        XCTAssertEqual(samples.rows.count, 40)
        XCTAssertEqual(Set(samples.rows.map(\.id)).count, 40)
    }

    private func host(_ controller: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        settle(controller.view)
        return window
    }

    private func settle(_ view: UIView) {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        view.layoutIfNeeded()
    }

    private func find(_ identifier: String, in view: UIView) -> UIView? {
        allViews(in: view).first { $0.accessibilityIdentifier == identifier }
    }

    private func allViews(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(allViews)
    }
}
