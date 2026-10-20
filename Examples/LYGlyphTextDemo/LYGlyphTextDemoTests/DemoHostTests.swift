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
}

private extension UIView {
    func viewWithAccessibilityIdentifier(_ identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier { return self }
        return subviews.lazy.compactMap { $0.viewWithAccessibilityIdentifier(identifier) }.first
    }
}
