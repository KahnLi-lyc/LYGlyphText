@testable import LYGlyphText
@testable import LYGlyphTextDemo
import SwiftUI
import UIKit
import XCTest

@MainActor
final class EnvironmentDemoHostTests: XCTestCase {
    func testSharedDocumentUsesDynamicBodySemanticColorsAndIndependentActions() throws {
        let samples = try EnvironmentSamples()
        XCTAssertTrue(samples.document.styleRuns.allSatisfy { $0.font == nil })
        XCTAssertEqual(samples.document.actions.map(\.actionID), ["environment-text", "environment-attachment"])
        XCTAssertEqual(samples.document.attachments.values.first?.alternativeText, "向右箭头，左上白点")
        XCTAssertEqual(samples.document.viewAttachments.values.first?.isInteractive, true)
        let first = EnvironmentEventState()
        let second = EnvironmentEventState()
        let descriptor = try XCTUnwrap(samples.document.viewAttachments.values.first)
        let firstButton = try XCTUnwrap(first.provider.makeView(descriptor) as? UIButton)
        let secondButton = try XCTUnwrap(second.provider.makeView(descriptor) as? UIButton)
        XCTAssertFalse(firstButton === secondButton)
        firstButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(first.buttonCount, 1)
        XCTAssertEqual(second.buttonCount, 0)
        XCTAssertEqual(first.actionCount, 0)
    }

    func testNavigationHostDarkPreferenceReachesLabel() throws {
        let samples = try EnvironmentSamples()
        var selection = EnvironmentSelection()
        selection.isDark = true
        let host = UIHostingController(rootView: SwiftUIEnvironmentView(samples: samples, selection: selection))
        let navigation = EnvironmentTestNavigationController(rootViewController: host)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        waitForAppearance(navigation)
        defer { window.isHidden = true }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        var label: LYGlyphTextLabel?
        repeat {
            navigation.view.layoutIfNeeded()
            label = findLabels(in: host.view).first { $0.document === samples.document && $0.window != nil }
            if label?.traitCollection.userInterfaceStyle == .dark { break }
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        } while ProcessInfo.processInfo.systemUptime < deadline
        let current = try XCTUnwrap(label)
        print(
            "A1c navigation scheme: selection=Dark;nav=\(navigation.traitCollection.userInterfaceStyle.rawValue);host=\(host.traitCollection.userInterfaceStyle.rawValue);Label=\(current.traitCollection.userInterfaceStyle.rawValue);resolvedLabel=\(UIColor.label.resolvedColor(with: current.traitCollection))"
        )
        XCTAssertEqual(current.traitCollection.userInterfaceStyle, .dark)
    }

    func testRealDemoHostsPropagateEnvironmentAndMatchHeightWithinOnePixel() throws {
        let samples = try EnvironmentSamples()
        for size in 0 ..< 3 {
            for dark in [false, true] {
                for rtl in [false, true] {
                    for width in [160, 320] {
                        for single in [false, true] {
                            var selection = EnvironmentSelection()
                            selection.sizeIndex = size
                            selection.isDark = dark
                            selection.isRTL = rtl
                            selection.width = width
                            selection.isSingleLine = single
                            try compareHosts(samples: samples, selection: selection)
                        }
                    }
                }
            }
        }
    }

    private func compareHosts(samples: EnvironmentSamples, selection: EnvironmentSelection) throws {
        // 每个配置使用独立真实导航宿主；同页动态切换另由 UI 控件测试覆盖。
        let uikit = UIKitEnvironmentController(samples: samples)
        let swift = UIHostingController(rootView: SwiftUIEnvironmentView(samples: samples, selection: selection))
        let uikitNavigation = EnvironmentTestNavigationController(rootViewController: uikit)
        let swiftNavigation = EnvironmentTestNavigationController(rootViewController: swift)
        let uikitWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let swiftWindow = UIWindow(frame: uikitWindow.frame)
        uikitWindow.rootViewController = uikitNavigation
        swiftWindow.rootViewController = swiftNavigation
        uikitWindow.makeKeyAndVisible()
        swiftWindow.makeKeyAndVisible()
        waitForAppearance(uikitNavigation)
        waitForAppearance(swiftNavigation)
        defer {
            uikitWindow.isHidden = true
            swiftWindow.isHidden = true
        }
        setControl("Size", index: selection.sizeIndex, in: uikit.view)
        setControl("Scheme", index: selection.isDark ? 1 : 0, in: uikit.view)
        setControl("Direction", index: selection.isRTL ? 1 : 0, in: uikit.view)
        setControl("Width", index: selection.width == 160 ? 0 : 1, in: uikit.view)
        setControl("Lines", index: selection.isSingleLine ? 0 : 1, in: uikit.view)
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        var actual: LYGlyphTextLabel?
        repeat {
            uikitNavigation.view.setNeedsLayout()
            uikitNavigation.view.layoutIfNeeded()
            swiftNavigation.view.setNeedsLayout()
            swiftNavigation.view.layoutIfNeeded()
            actual = findLabels(in: swift.view).first {
                $0.document === samples.document && $0.window != nil
            }
            if let label = actual, matches(label, selection: selection),
               matches(uikit.glyphLabel, selection: selection),
               abs(label.bounds.height - uikit.glyphLabel.bounds.height) <= 1 / label.contentScaleFactor
            {
                break
            }
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        } while ProcessInfo.processInfo.systemUptime < deadline
        let label = try XCTUnwrap(actual, selection.status)
        XCTAssertTrue(label.document === samples.document)
        XCTAssertTrue(uikit.glyphLabel.document === samples.document)
        XCTAssertTrue(
            matches(label, selection: selection),
            "SwiftUI \(selection.status);traits=\(label.traitCollection)"
        )
        XCTAssertTrue(matches(uikit.glyphLabel, selection: selection), "UIKit \(selection.status)")
        XCTAssertEqual(label.contentScaleFactor, uikit.glyphLabel.contentScaleFactor)
        XCTAssertEqual(label.bounds.width, CGFloat(selection.width), accuracy: 1 / label.contentScaleFactor)
        XCTAssertEqual(
            label.bounds.height,
            uikit.glyphLabel.bounds.height,
            accuracy: 1 / label.contentScaleFactor,
            selection.status
        )
        print(
            "A1c \(selection.status);UIKit=\(uikit.glyphLabel.bounds.height);SwiftUI=\(label.bounds.height);scale=\(label.contentScaleFactor)"
        )
    }

    private func waitForAppearance(_ navigation: EnvironmentTestNavigationController) {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !navigation.hasAppeared, ProcessInfo.processInfo.systemUptime < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        XCTAssertTrue(navigation.hasAppeared, "导航宿主必须完成真实出现再开始断言或关闭窗口")
    }

    private func matches(_ label: LYGlyphTextLabel, selection: EnvironmentSelection) -> Bool {
        label.traitCollection.preferredContentSizeCategory == selection.category &&
            label.traitCollection.userInterfaceStyle == (selection.isDark ? .dark : .light) &&
            label.effectiveUserInterfaceLayoutDirection == (selection.isRTL ? .rightToLeft : .leftToRight) &&
            abs(label.bounds.width - CGFloat(selection.width)) <= 1 / label.contentScaleFactor &&
            label.configuration.numberOfLines == (selection.isSingleLine ? 1 : 0)
    }

    private func setControl(_ name: String, index: Int, in view: UIView) {
        guard let control = find("environment\(name)", in: view) as? UISegmentedControl else {
            XCTFail("缺少控件 \(name)")
            return
        }
        control.selectedSegmentIndex = index
        control.sendActions(for: .valueChanged)
        view.setNeedsLayout()
    }

    private func find(_ identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        return view.subviews.lazy.compactMap { self.find(identifier, in: $0) }.first
    }

    private func findLabels(in view: UIView) -> [LYGlyphTextLabel] {
        if let label = view as? LYGlyphTextLabel { return [label] }
        return view.subviews.flatMap(findLabels)
    }
}

@MainActor
private final class EnvironmentTestNavigationController: UINavigationController {
    private(set) var hasAppeared = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }
}
