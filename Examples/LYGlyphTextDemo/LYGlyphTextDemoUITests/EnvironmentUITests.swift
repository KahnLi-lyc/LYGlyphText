import XCTest

@MainActor
final class EnvironmentUITests: XCTestCase {
    func testUIKitEnvironmentControlsAndAutomaticAccessibility() throws {
        try exercise(host: "UIKit")
    }

    func testSwiftUIEnvironmentControlsAndAutomaticAccessibility() throws {
        try exercise(host: "SwiftUI")
    }

    private func exercise(host: String) throws {
        let app = XCUIApplication()
        app.launch()
        let cell = app.cells["open\(host)Environment"]
        let table = app.tables.firstMatch
        var attempts = 0
        while !cell.isHittable, attempts < 8 {
            table.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(cell.isHittable, "首页底部入口必须可点击")
        cell.tap()
        let selection = app.staticTexts["environmentSelection"]
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        expect(selection, contains: "size=L;Light;LTR;width=320;lines=all;callback=A")
        let action = app.buttons["执行文字动作"]
        let native = app.buttons["environmentNativeButton"]
        XCTAssertTrue(action.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(native.exists, app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "environmentNativeButton").count, 1)
        capture(app, name: "environment-\(host)-light-default")
        action.tap()
        expect(app.staticTexts["environmentEvents"], contains: "event=1;button=0;handled=A;id=environment-text")
        choose("Callback", "B", app: app)
        action.tap()
        expect(app.staticTexts["environmentEvents"], contains: "event=2;button=0;handled=B;id=environment-text")
        native.tap()
        expect(app.staticTexts["environmentEvents"], contains: "event=2;button=1;handled=B;id=environment-text")
        choose("Callback", "A", app: app)
        choose("Callback", "B", app: app)
        choose("Width", "160", app: app)
        choose("Lines", "1", app: app)
        expect(selection, contains: "width=160;lines=1;callback=B")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "末尾可见性标记")).firstMatch.exists)
        XCTAssertFalse(action.exists, "一行截断不得暴露隐藏文字动作")
        XCTAssertFalse(native.exists, "一行截断不得暴露隐藏原生按钮")
        choose("Lines", "不限", app: app)
        choose("Width", "320", app: app)
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "末尾可见性标记")).firstMatch.exists)
        XCTAssertTrue(native.exists)
        choose("Size", "XXXL", app: app)
        expect(selection, contains: "size=XXXL")
        choose("Scheme", "Dark", app: app)
        capture(app, name: "environment-\(host)-dark-xxxl")
        choose("Size", "AX5", app: app)
        expect(selection, contains: "size=AX5;Dark")
        // 最大字号下通过真实滚动查看尾部，再回到控件，不以静态存在替代可操作性。
        let scroll = app.scrollViews["environmentScroll"].firstMatch
        let tail = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "末尾可见性标记")).firstMatch
        attempts = 0
        while !tail.isHittable || tail.frame.maxY > scroll.frame.maxY - 12, attempts < 12 {
            scroll.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(tail.isHittable)
        XCTAssertLessThanOrEqual(tail.frame.maxY, scroll.frame.maxY - 12, "尾标记必须真正滚入可见区域")
        capture(app, name: "environment-\(host)-ax5-scrolled")
        attempts = 0
        while !app.segmentedControls["environmentSize"].isHittable, attempts < 12 {
            scroll.swipeDown()
            attempts += 1
        }
        choose("Size", "L", app: app)
        choose("Scheme", "Light", app: app)
        choose("Direction", "RTL", app: app)
        expect(selection, contains: "size=L;Light;RTL;width=320;lines=all;callback=B")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "向右箭头，左上白点")).firstMatch.exists)
        action.tap()
        expect(app.staticTexts["environmentEvents"], contains: "event=3;button=1;handled=B;id=environment-text")
        capture(app, name: "environment-\(host)-rtl")
        choose("Direction", "LTR", app: app)
    }

    private func choose(_ control: String, _ value: String, app: XCUIApplication) {
        let button = app.segmentedControls["environment\(control)"].buttons[value]
        XCTAssertTrue(button.isHittable, "控件 \(control) / \(value) 必须可操作")
        button.tap()
    }

    private func expect(_ element: XCUIElement, contains value: String) {
        let predicate = NSPredicate(format: "label CONTAINS %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, element.label)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
