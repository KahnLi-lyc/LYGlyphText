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
}

private extension UIView {
    func viewWithAccessibilityIdentifier(_ identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier { return self }
        return subviews.lazy.compactMap { $0.viewWithAccessibilityIdentifier(identifier) }.first
    }
}
