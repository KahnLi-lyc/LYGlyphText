import XCTest

@MainActor
final class DemoUITests: XCTestCase {
    func testUIKitSampleAndWidthChanges() {
        verifyPage("openUIKit", name: "UIKit")
    }

    func testSwiftUISampleAndWidthChanges() {
        verifyPage("openSwiftUI", name: "SwiftUI")
    }

    private func verifyPage(_ identifier: String, name: String) {
        let app = XCUIApplication()
        app.launch()
        let entry = app.cells[identifier]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let sampleControl = app.segmentedControls["sampleControl"]
        XCTAssertTrue(sampleControl.waitForExistence(timeout: 5))
        sampleControl.buttons["多行"].tap()
        app.segmentedControls["widthControl"].buttons["160"].tap()
        assertStatus(app, expected: "多行 · 宽度 160")
        capture(app, name: "\(name)-multiline-160")
        sampleControl.buttons["混合样式"].tap()
        app.segmentedControls["widthControl"].buttons["320"].tap()
        assertStatus(app, expected: "混合样式 · 宽度 320")
        capture(app, name: "\(name)-mixed-320")
        sampleControl.buttons["短文"].tap()
        app.segmentedControls["widthControl"].buttons["240"].tap()
        assertStatus(app, expected: "短文 · 宽度 240")
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
