import XCTest

@MainActor
final class DemoUITests: XCTestCase {
    func testUIKitSampleAndWidthChanges() {
        verifyPage("openUIKit", name: "UIKit")
    }

    func testSwiftUISampleAndWidthChanges() {
        verifyPage("openSwiftUI", name: "SwiftUI")
    }

    func testUIKitImageAlignmentWidthsAndTruncation() {
        verifyImages("openUIKit", name: "UIKit")
    }

    func testSwiftUIImageAlignmentWidthsAndTruncation() {
        verifyImages("openSwiftUI", name: "SwiftUI")
    }

    private func verifyImages(_ identifier: String, name: String) {
        let app = XCUIApplication()
        app.launch()
        let entry = app.cells[identifier]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let imageControl = app.segmentedControls["imageControl"]
        XCTAssertTrue(imageControl.waitForExistence(timeout: 5))
        imageControl.buttons["图片混排"].tap()
        let alignments = app.segmentedControls["alignmentControl"]
        let widths = app.segmentedControls["widthControl"]
        let limits = app.segmentedControls["lineLimitControl"]
        let samples = app.segmentedControls["sampleControl"]
        assertStatus(app, expected: "短文 · 宽度 240 · 无限行 · 图片混排 · 底部")
        for (alignment, width, suffix) in [("顶部", "160", "top"), ("居中", "240", "center"), ("底部", "320", "bottom")] {
            alignments.buttons[alignment].tap()
            widths.buttons[width].tap()
            assertStatus(app, expected: "短文 · 宽度 \(width) · 无限行 · 图片混排 · \(alignment)")
            capture(app, name: "\(name)-images-\(width)-\(suffix)-unlimited")
        }
        samples.buttons["多行"].tap()
        widths.buttons["160"].tap()
        limits.buttons["1 行"].tap()
        assertStatus(app, expected: "多行 · 宽度 160 · 1 行 · 图片混排 · 底部")
        capture(app, name: "\(name)-images-160-bottom-one-line")
        widths.buttons["240"].tap()
        limits.buttons["2 行"].tap()
        assertStatus(app, expected: "多行 · 宽度 240 · 2 行 · 图片混排 · 底部")
        capture(app, name: "\(name)-images-240-bottom-two-lines")
        samples.buttons["混合样式"].tap()
        alignments.buttons["居中"].tap()
        widths.buttons["320"].tap()
        limits.buttons["3 行"].tap()
        assertStatus(app, expected: "混合样式 · 宽度 320 · 3 行 · 图片混排 · 居中")
        capture(app, name: "\(name)-images-mixed-320-center-three-lines")
        limits.buttons["无限行"].tap()
        imageControl.buttons["文字"].tap()
        assertStatus(app, expected: "混合样式 · 宽度 320 · 无限行")
    }

    private func verifyPage(_ identifier: String, name: String) {
        let app = XCUIApplication()
        app.launch()
        let entry = app.cells[identifier]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let sampleControl = app.segmentedControls["sampleControl"]
        XCTAssertTrue(sampleControl.waitForExistence(timeout: 5))
        let lineLimitControl = app.segmentedControls["lineLimitControl"]
        XCTAssertTrue(lineLimitControl.waitForExistence(timeout: 5))
        assertStatus(app, expected: "短文 · 宽度 240 · 无限行")
        sampleControl.buttons["多行"].tap()
        app.segmentedControls["widthControl"].buttons["160"].tap()
        assertStatus(app, expected: "多行 · 宽度 160 · 无限行")
        capture(app, name: "\(name)-multiline-160-unlimited")
        lineLimitControl.buttons["3 行"].tap()
        assertStatus(app, expected: "多行 · 宽度 160 · 3 行")
        capture(app, name: "\(name)-multiline-160-three-lines")
        sampleControl.buttons["混合样式"].tap()
        app.segmentedControls["widthControl"].buttons["320"].tap()
        assertStatus(app, expected: "混合样式 · 宽度 320 · 3 行")
        lineLimitControl.buttons["1 行"].tap()
        assertStatus(app, expected: "混合样式 · 宽度 320 · 1 行")
        capture(app, name: "\(name)-mixed-320-one-line")
        sampleControl.buttons["显式换行"].tap()
        lineLimitControl.buttons["2 行"].tap()
        assertStatus(app, expected: "显式换行 · 宽度 320 · 2 行")
        capture(app, name: "\(name)-explicit-newlines-two-lines")
        lineLimitControl.buttons["无限行"].tap()
        assertStatus(app, expected: "显式换行 · 宽度 320 · 无限行")
        sampleControl.buttons["短文"].tap()
        app.segmentedControls["widthControl"].buttons["240"].tap()
        assertStatus(app, expected: "短文 · 宽度 240 · 无限行")
    }

    private func assertStatus(_ app: XCUIApplication, expected: String) {
        let status = app.staticTexts["sampleStatus"]
        let predicate = NSPredicate(format: "label == %@", expected)
        expectation(for: predicate, evaluatedWith: status)
        waitForExpectations(timeout: 5)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
