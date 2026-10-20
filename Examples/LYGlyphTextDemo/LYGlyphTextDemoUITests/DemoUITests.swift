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

    func testUIKitUIViewAttachmentsNativeActionsClearReloadAndGeometry() {
        verifyViewAttachments("openUIKit", name: "UIKit")
    }

    func testSwiftUIUIViewAttachmentsNativeActionsClearReloadAndGeometry() {
        verifyViewAttachments("openSwiftUI", name: "SwiftUI")
    }

    func testUIKitStylesWrappingVerticalAlignmentAndNativeButtons() {
        verifyStyles("openUIKitStyles", name: "UIKit")
    }

    func testSwiftUIStylesWrappingVerticalAlignmentAndNativeButtons() {
        verifyStyles("openSwiftUIStyles", name: "SwiftUI")
    }

    private func verifyStyles(_ identifier: String, name: String) {
        let app = XCUIApplication()
        app.launch()
        app.cells[identifier].tap()
        let vertical = app.segmentedControls["styleVerticalControl"]
        XCTAssertTrue(vertical.waitForExistence(timeout: 5))
        let buttons = app.buttons.matching(identifier: "attachmentButton")
        XCTAssertEqual(buttons.count, 2)
        let expandedButton = buttons.element(boundBy: 1)
        let top = expandedButton.frame.minY
        for (title, delta) in [("顶部", 0.0), ("居中", 30.0), ("底部", 60.0)] {
            vertical.buttons[title].tap()
            XCTAssertEqual(expandedButton.frame.minY, top + delta, accuracy: 0.5)
            capture(app, name: "\(name)-styles-display-extra60-\(title)")
        }
        for (style, wrapping, alignment, width, limit) in [
            ("装饰混排", "字符", "居中", "160", "1 行"),
            ("混合段落", "单词", "底部", "320", "无限行"),
            ("混合段落", "字符", "顶部", "240", "3 行"),
            ("装饰混排", "单词", "底部", "240", "2 行")
        ] {
            app.segmentedControls["styleSampleControl"].buttons[style].tap()
            app.segmentedControls["styleWrappingControl"].buttons[wrapping].tap()
            vertical.buttons[alignment].tap()
            app.segmentedControls["styleWidthControl"].buttons[width].tap()
            app.segmentedControls["styleLineLimitControl"].buttons[limit].tap()
            let expected = "\(style) · \(wrapping) · \(alignment) · 宽度 \(width) · \(limit)"
            let predicate = NSPredicate(format: "label == %@", expected)
            expectation(for: predicate, evaluatedWith: app.staticTexts["styleStatus"])
            waitForExpectations(timeout: 5)
            capture(app, name: "\(name)-styles-\(style)-\(wrapping)-\(alignment)-\(width)-\(limit)")
        }
        expandedButton.tap()
        XCTAssertEqual(app.staticTexts["styleAttachmentCount"].label, "按钮点击：1")
        app.buttons["styleClear"].tap()
        XCTAssertEqual(buttons.count, 0)
        app.buttons["styleReload"].tap()
        XCTAssertTrue(expandedButton.waitForExistence(timeout: 5))
        expandedButton.tap()
        XCTAssertEqual(app.staticTexts["styleAttachmentCount"].label, "按钮点击：2")
        capture(app, name: "\(name)-styles-native-button-after-reload")
    }

    func testUIViewListScrollReusesWithoutStaleButtonContent() {
        let app = XCUIApplication()
        app.launch()
        app.cells["openReuse"].tap()
        let table = app.tables["attachmentList"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        let first = app.buttons["reuseButton0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        XCTAssertEqual(first.label, "行 0 · 1")
        for _ in 0 ..< 4 {
            table.swipeUp()
        }
        var checkedRows = 0
        for cell in table.cells.allElementsBoundByIndex where cell.isHittable {
            guard cell.identifier.hasPrefix("reuseRow"),
                  let row = Int(cell.identifier.dropFirst("reuseRow".count)) else { continue }
            XCTAssertGreaterThan(row, 0)
            let button = cell.buttons["reuseButton\(row)"]
            XCTAssertTrue(button.exists)
            XCTAssertEqual(button.label, "行 \(row) · 0")
            checkedRows += 1
        }
        XCTAssertGreaterThan(checkedRows, 0)
        capture(app, name: "UIView-list-scrolled-current-rows")
        for _ in 0 ..< 5 {
            table.swipeDown()
        }
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.label, "行 0 · 0")
        first.tap()
        XCTAssertEqual(first.label, "行 0 · 1")
        capture(app, name: "UIView-list-return-rebound-row-zero")
    }

    private func verifyViewAttachments(_ identifier: String, name: String) {
        let app = XCUIApplication()
        app.launch()
        app.cells[identifier].tap()
        let modes = app.segmentedControls["imageControl"]
        XCTAssertTrue(modes.waitForExistence(timeout: 5))
        modes.buttons["UIView"].tap()
        let button = app.buttons["attachmentButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertEqual(app.staticTexts["attachmentCount"].label, "按钮点击：1")
        app.buttons["clearAttachments"].tap()
        XCTAssertFalse(button.exists)
        app.buttons["reloadAttachments"].tap()
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertEqual(app.staticTexts["attachmentCount"].label, "按钮点击：2")
        for (alignment, width, limit) in [("顶部", "160", "1 行"), ("居中", "240", "2 行"), ("底部", "320", "无限行")] {
            app.segmentedControls["alignmentControl"].buttons[alignment].tap()
            app.segmentedControls["widthControl"].buttons[width].tap()
            app.segmentedControls["lineLimitControl"].buttons[limit].tap()
            assertStatus(app, expected: "短文 · 宽度 \(width) · \(limit) · UIView · \(alignment)")
            capture(app, name: "\(name)-UIView-\(width)-\(alignment)-\(limit)")
        }
        XCTAssertTrue(button.exists)
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
