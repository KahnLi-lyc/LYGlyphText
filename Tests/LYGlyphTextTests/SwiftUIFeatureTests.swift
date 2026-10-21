@testable import LYGlyphText
import SwiftUI
import UIKit
import XCTest

@MainActor
final class SwiftUIFeatureTests: XCTestCase {
    private func label(in controller: UIViewController) -> LYGlyphTextLabel? {
        func find(_ view: UIView) -> LYGlyphTextLabel? {
            (view as? LYGlyphTextLabel) ?? view.subviews.lazy.compactMap(find).first
        }
        return find(controller.view)
    }

    func testSwiftUIPassesSelectionTokenAndReleasesCallbacksOnDismantle() throws {
        let document = try LYGlyphTextDocument(attributedText: NSAttributedString(
            string: String(repeating: "SwiftUI 选择与截断 ", count: 20)
        ))
        var changes: [NSRange?] = []
        var configuration = LYGlyphTextConfiguration(numberOfLines: 2)
        configuration.truncationToken = .init(text: "…更多", actionID: "more")
        let view = LYGlyphTextView(
            document: document, configuration: configuration, isSelectable: true,
            onSelectionChange: { changes.append($0) }
        )
        let controller = UIHostingController(rootView: view.frame(width: 300))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let label = try XCTUnwrap(label(in: controller))
        XCTAssertTrue(label.isSelectable)
        XCTAssertEqual(label.configuration.truncationToken?.text, "…更多")
        XCTAssertEqual(label.measuredLayout(width: 300).truncationToken?.text, "…更多")
        label.selectedRange = NSRange(location: 0, length: 7)
        XCTAssertEqual(changes, [NSRange(location: 0, length: 7)])
        controller.rootView = LYGlyphTextView(document: document, configuration: configuration).frame(width: 300)
        // SwiftUI 在下一次更新周期调用 updateUIView；有限等待真实更新而不是固定延时。
        let deadline = Date().addingTimeInterval(2)
        while label.isSelectable, Date() < deadline {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertFalse(label.isSelectable)
        XCTAssertNil(label.selectedRange)
        label.clearForDismantle()
        XCTAssertNil(label.onSelectionChange)
        withExtendedLifetime(window) {}
    }
}
