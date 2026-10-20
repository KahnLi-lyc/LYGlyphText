import LYGlyphText
@testable import LYGlyphTextDemo
import SwiftUI
import UIKit
import XCTest

@MainActor
final class StyleDemoHostTests: XCTestCase {
    private func labels(in view: UIView) -> [LYGlyphTextLabel] {
        if let label = view as? LYGlyphTextLabel { return [label] }
        return view.subviews.flatMap { self.labels(in: $0) }
    }

    private func findControl(_ identifier: String, in view: UIView) -> UISegmentedControl? {
        if view.accessibilityIdentifier == identifier, let control = view as? UISegmentedControl { return control }
        for child in view.subviews {
            if let found = findControl(identifier, in: child) { return found }
        }
        return nil
    }

    private func settle(_ view: UIView) {
        for _ in 0 ..< 4 {
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    func testSharedStylePagesKeepActualNaturalHeightEqualAtSameWidthAndAddExactlySixtyDisplayPoints() throws {
        let samples = try DemoSamples()
        let uiKit = UIKitStyleDemoController(samples: samples.styles)
        let model = StyleDemoModel(samples: samples.styles)
        let swiftUI = UIHostingController(rootView: SwiftUIStyleDemoView(model: model))
        let uiWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let swiftWindow = UIWindow(frame: uiWindow.frame)
        uiWindow.rootViewController = uiKit
        swiftWindow.rootViewController = swiftUI
        uiWindow.makeKeyAndVisible()
        swiftWindow.makeKeyAndVisible()
        defer { uiWindow.isHidden = true
            swiftWindow.isHidden = true
        }
        settle(uiKit.view)
        settle(swiftUI.view)
        let uiLabels = labels(in: uiKit.view)
        let swiftLabels = labels(in: swiftUI.view)
        XCTAssertEqual(uiLabels.count, 2)
        XCTAssertEqual(swiftLabels.count, 2)
        let uiNatural = try XCTUnwrap(uiLabels.first)
        let uiExpanded = try XCTUnwrap(uiLabels.last)
        let swiftNatural = try XCTUnwrap(swiftLabels.first)
        let swiftExpanded = try XCTUnwrap(swiftLabels.last)
        let originalProvider = swiftExpanded.viewProvider
        let scale = max(swiftUI.traitCollection.displayScale, 1)
        for (sample, wrapping, vertical, width, limit):
            (StyleSample, StyleWrapping, StyleVerticalAlignment, Int, LineLimit) in [
                (.decorations, .word, .top, 240, .two),
                (.decorations, .character, .center, 160, .one),
                (.paragraphs, .word, .bottom, 320, .unlimited),
                (.paragraphs, .character, .center, 240, .three),
                (.decorations, .word, .bottom, 160, .two),
                (.decorations, .word, .top, 240, .two)
            ]
        {
            for (identifier, index) in [
                ("styleSampleControl", sample.rawValue), ("styleWrappingControl", wrapping.rawValue),
                ("styleVerticalControl", vertical.rawValue),
                ("styleWidthControl", [160, 240, 320].firstIndex(of: width) ?? 0),
                ("styleLineLimitControl", LineLimit.allCases.firstIndex(of: limit) ?? 0)
            ] {
                let control = try XCTUnwrap(findControl(identifier, in: uiKit.view))
                control.selectedSegmentIndex = index
                control.sendActions(for: .valueChanged)
            }
            model.sample = sample
            model.wrapping = wrapping
            model.verticalAlignment = vertical
            model.width = width
            model.lineLimit = limit
            swiftUI.rootView = SwiftUIStyleDemoView(model: model)
            settle(uiKit.view)
            settle(swiftUI.view)
            let context = "\(sample.title) · \(wrapping.title) · \(vertical.title) · \(width) · \(limit.title)"
            XCTAssertTrue(labels(in: swiftUI.view).first === swiftNatural, context)
            XCTAssertTrue(labels(in: swiftUI.view).last === swiftExpanded, context)
            XCTAssertTrue(swiftExpanded.viewProvider === originalProvider, context)
            for label in [uiNatural, uiExpanded, swiftNatural, swiftExpanded] {
                XCTAssertTrue(label.document === samples.styles.documents[sample], context)
                XCTAssertEqual(label.configuration, model.configuration, context)
                XCTAssertEqual(label.bounds.width, CGFloat(width), accuracy: 0.01, context)
            }
            let uiRaw = uiNatural.sizeThatFits(CGSize(width: CGFloat(width), height: 1)).height
            let swiftRaw = swiftNatural.sizeThatFits(CGSize(width: CGFloat(width), height: 1)).height
            XCTAssertEqual(uiRaw, swiftRaw, accuracy: 1 / scale, context)
            XCTAssertEqual(uiNatural.bounds.height, uiRaw, accuracy: 1 / scale, context)
            XCTAssertEqual(swiftNatural.bounds.height, swiftRaw, accuracy: 1 / scale, context)
            XCTAssertEqual(uiNatural.bounds.height, swiftNatural.bounds.height, accuracy: 1 / scale, context)
            XCTAssertEqual(uiExpanded.bounds.height, uiRaw + 60, accuracy: 1 / scale, context)
            XCTAssertEqual(swiftExpanded.bounds.height, swiftRaw + 60, accuracy: 1 / scale, context)
        }
    }
}
