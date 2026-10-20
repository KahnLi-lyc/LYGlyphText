@testable import LYGlyphText
@testable import LYGlyphTextDemo
import UIKit
import XCTest

@MainActor
final class ActionDemoHostTests: XCTestCase {
    func testSharedActionDocumentContainsEveryInteractionFixture() throws {
        let samples = try DemoSamples()
        let ids = samples.actionDocument.actions.map(\.actionID)
        XCTAssertEqual(ids.count(where: { $0 == "duplicate" }), 2)
        for id in [
            "single", "cross", "rtl", "emoji", "fi", "decorative-image", "decorative-view",
            "interactive-button", "truncated"
        ] {
            XCTAssertTrue(ids.contains(id), id)
        }
        XCTAssertEqual(samples.actionDocument.attachments.count, 1)
        XCTAssertEqual(samples.actionDocument.viewAttachments.count, 2)
        XCTAssertEqual(samples.actionListDocuments.count, 40)
        XCTAssertTrue(samples.actionListDocuments[0] === samples.actionDocument)
    }

    func testActionPagesUseSharedDocumentAndSelectableListKeepsSelectionEnabled() throws {
        let samples = try DemoSamples()
        let controller = UIKitActionDemoController(samples: samples)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()

        let list = ActionSelectionDemoController(documents: samples.actionListDocuments)
        list.loadViewIfNeeded()
        let cell = try XCTUnwrap(list.tableView(
            list.tableView,
            cellForRowAt: IndexPath(row: 0, section: 0)
        ) as? ActionSelectionCell)
        XCTAssertNotEqual(cell.selectionStyle, .none)
        XCTAssertTrue(cell.glyphLabel.document === samples.actionDocument)
        XCTAssertNotNil(cell.glyphLabel.onAction)
        cell.setCallbackEnabled(false)
        XCTAssertNil(cell.glyphLabel.onAction)
    }
}
