import LYGlyphText
@testable import LYGlyphTextDemo
import UIKit
import XCTest

@MainActor
final class DemoHostTests: XCTestCase {
    func testSharedSamplesBuildAndUIKitPageLoads() throws {
        let samples = try DemoSamples()
        XCTAssertEqual(samples.documents.count, SampleKind.allCases.count)
        let controller = UIKitDemoController(samples: samples)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.title, "UIKit")
        XCTAssertNotNil(controller.view.viewWithAccessibilityIdentifier("richTextPreview"))
    }

    func testUIKitLineLimitControlUpdatesPreviewAndRestoresUnlimitedLines() throws {
        let controller = try UIKitDemoController(samples: DemoSamples())
        controller.loadViewIfNeeded()
        let preview = try XCTUnwrap(
            controller.view.viewWithAccessibilityIdentifier("richTextPreview") as? LYGlyphTextLabel
        )
        let samples = try XCTUnwrap(
            controller.view.viewWithAccessibilityIdentifier("sampleControl") as? UISegmentedControl
        )
        let limits = try XCTUnwrap(
            controller.view.viewWithAccessibilityIdentifier("lineLimitControl") as? UISegmentedControl
        )
        XCTAssertEqual(preview.configuration.numberOfLines, 0)
        samples.selectedSegmentIndex = SampleKind.multiline.rawValue
        samples.sendActions(for: .valueChanged)
        let width = CGSize(width: 160, height: CGFloat.greatestFiniteMagnitude)
        let unlimitedHeight = preview.sizeThatFits(width).height
        limits.selectedSegmentIndex = LineLimit.three.rawValue
        limits.sendActions(for: .valueChanged)
        XCTAssertEqual(preview.configuration.numberOfLines, 3)
        XCTAssertLessThan(preview.sizeThatFits(width).height, unlimitedHeight)
        limits.selectedSegmentIndex = LineLimit.unlimited.rawValue
        limits.sendActions(for: .valueChanged)
        XCTAssertEqual(preview.configuration.numberOfLines, 0)
        XCTAssertEqual(preview.sizeThatFits(width).height, unlimitedHeight)
    }

    func testUIKitImageControlsUseSharedDocumentsAndPreserveTextSelection() throws {
        let samples = try DemoSamples()
        let controller = UIKitDemoController(samples: samples)
        controller.loadViewIfNeeded()
        let preview = try XCTUnwrap(
            controller.view.viewWithAccessibilityIdentifier("richTextPreview") as? LYGlyphTextLabel
        )
        let imageControl = try XCTUnwrap(
            controller.view.viewWithAccessibilityIdentifier("imageControl") as? UISegmentedControl
        )
        let alignmentControl = try XCTUnwrap(
            controller.view.viewWithAccessibilityIdentifier("alignmentControl") as? UISegmentedControl
        )
        let sampleControl = try XCTUnwrap(
            controller.view.viewWithAccessibilityIdentifier("sampleControl") as? UISegmentedControl
        )
        XCTAssertFalse(alignmentControl.isEnabled)
        sampleControl.selectedSegmentIndex = SampleKind.mixed.rawValue
        sampleControl.sendActions(for: .valueChanged)
        imageControl.selectedSegmentIndex = 1
        imageControl.sendActions(for: .valueChanged)
        XCTAssertTrue(alignmentControl.isEnabled)
        for alignment in ImageAlignment.allCases {
            alignmentControl.selectedSegmentIndex = alignment.rawValue
            alignmentControl.sendActions(for: .valueChanged)
            XCTAssertTrue(preview.document === samples.document(
                for: .mixed,
                includesImages: true,
                alignment: alignment
            ))
            XCTAssertGreaterThan(preview.sizeThatFits(CGSize(width: 160, height: CGFloat.infinity)).height, 0)
        }
        imageControl.selectedSegmentIndex = 0
        imageControl.sendActions(for: .valueChanged)
        XCTAssertFalse(alignmentControl.isEnabled)
        XCTAssertEqual(sampleControl.selectedSegmentIndex, SampleKind.mixed.rawValue)
        XCTAssertTrue(preview.document === samples.documents[.mixed])
    }

    func testUIViewContentUsesSharedDocumentsAndClearReloadControls() throws {
        let samples = try DemoSamples()
        let controller = UIKitDemoController(samples: samples)
        controller.loadViewIfNeeded()
        let control = try XCTUnwrap(
            controller.view.viewWithAccessibilityIdentifier("imageControl") as? UISegmentedControl
        )
        let label = try XCTUnwrap(
            controller.view.viewWithAccessibilityIdentifier("richTextPreview") as? LYGlyphTextLabel
        )
        control.selectedSegmentIndex = 2
        control.sendActions(for: .valueChanged)
        XCTAssertTrue(label.document === samples.viewDocument(for: .short, alignment: .bottom))
        XCTAssertNotNil(label.viewProvider)
        let provider = label.viewProvider
        let clear = try XCTUnwrap(
            controller.view.viewWithAccessibilityIdentifier("clearAttachments") as? UIButton
        )
        clear.sendActions(for: .touchUpInside)
        XCTAssertNil(label.document)
        XCTAssertTrue(label.viewProvider === provider)
        let reload = try XCTUnwrap(
            controller.view.viewWithAccessibilityIdentifier("reloadAttachments") as? UIButton
        )
        reload.sendActions(for: .touchUpInside)
        XCTAssertTrue(label.document === samples.viewDocument(for: .short, alignment: .bottom))
        XCTAssertTrue(label.viewProvider === provider)
    }

    func testReuseHostClearsBeforeRebindingAndReturnsCurrentRowButton() throws {
        let samples = try DemoSamples()
        let cell = ReuseDemoCell(style: .default, reuseIdentifier: "test")
        cell.bind(document: samples.reuseDocuments[0], row: 0)
        let oldProvider = try XCTUnwrap(cell.glyphLabel.viewProvider)
        XCTAssertTrue(cell.glyphLabel.document === samples.reuseDocuments[0])
        cell.prepareForReuse()
        XCTAssertNil(cell.glyphLabel.document)
        XCTAssertNil(cell.glyphLabel.viewProvider)
        cell.bind(document: samples.reuseDocuments[19], row: 19)
        XCTAssertTrue(cell.glyphLabel.document === samples.reuseDocuments[19])
        XCTAssertFalse(cell.glyphLabel.viewProvider === oldProvider)
        let controller = ReuseDemoController(documents: samples.reuseDocuments)
        controller.loadViewIfNeeded()
        XCTAssertEqual(controller.tableView.numberOfRows(inSection: 0), 80)
    }

    func testReuseCellHeightsContainTextAtActualWidthWhileScrollingAndResizing() throws {
        let samples = try DemoSamples()
        let controller = ReuseDemoController(documents: samples.reuseDocuments)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for width in [CGFloat(390), 320, 600, 390] {
            controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 844)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            for row in [0, 28, 50, 0] {
                controller.tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: false)
                controller.tableView.layoutIfNeeded()
                for case let cell as ReuseDemoCell in controller.tableView.visibleCells {
                    let label = cell.glyphLabel
                    let requiredHeight = label.sizeThatFits(CGSize(width: label.bounds.width, height: CGFloat.infinity))
                        .height
                    XCTAssertGreaterThanOrEqual(
                        label.bounds.height + 0.5, requiredHeight,
                        "\(cell.accessibilityIdentifier ?? "row") · width \(label.bounds.width)"
                    )
                }
            }
        }
    }
}

private extension UIView {
    func viewWithAccessibilityIdentifier(_ identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier { return self }
        return subviews.lazy.compactMap { $0.viewWithAccessibilityIdentifier(identifier) }.first
    }
}
