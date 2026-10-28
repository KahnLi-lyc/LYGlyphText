import XCTest

@MainActor
final class FeatureUITests: XCTestCase {
    private func openFeatures() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        let cell = app.cells["openFeatures"]
        var attempts = 0
        while !cell.isHittable, attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
        cell.tap()
        XCTAssertTrue(app.descendants(matching: .any)["selectableLabel"].waitForExistence(timeout: 5))
        return app
    }

    func testLongPressSelectsWordAndSystemMenuCopies() {
        let app = openFeatures()
        let label = app.descendants(matching: .any)["selectableLabel"]
        label.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.3)).press(forDuration: 1.0)
        let status = app.staticTexts["selectionStatus"]
        XCTAssertTrue(waitForLabel(status, prefix: "已选："), status.label)
        let copy = app.menuItems["Copy"].exists ? app.menuItems["Copy"] : app.menuItems["拷贝"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "selection-menu"
        shot.lifetime = .keepAlways
        add(shot)
        copy.tap()
        XCTAssertTrue(waitForLabel(status, prefix: "已拷贝："), status.label)
        XCTAssertGreaterThan(status.label.count, "已拷贝：".count)
    }

    func testDraggingEndHandleExtendsSelection() {
        let app = openFeatures()
        let label = app.descendants(matching: .any)["selectableLabel"]
        label.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.3)).press(forDuration: 1.0)
        let status = app.staticTexts["selectionStatus"]
        XCTAssertTrue(waitForLabel(status, prefix: "已选："), status.label)
        let before = status.label
        let end = app.descendants(matching: .any)["LYGlyphText.selectionEnd"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        // 编辑菜单可能显示在选区下方并盖住拖柄圆点；拖柄无障碍框又扩展到 44pt 命中区，
        // 所以按拖柄中心 x 与首行文字高度（长按位置）定位竖线部分。
        let start = label.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: end.frame.midX - label.frame.minX, dy: label.frame.height * 0.3
        ))
        let target = label.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.3))
        start.press(forDuration: 0.3, thenDragTo: target)
        let longer = NSPredicate(format: "label BEGINSWITH '已选：' AND label.length > %d", before.count)
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: longer, object: status)], timeout: 5),
            .completed,
            status.label
        )
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "selection-handle-dragged"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTruncationTokenTapExpandsAndRemoteImageLoadsLocally() {
        let app = openFeatures()
        let token = app.descendants(matching: .any)["…展开全文"]
        XCTAssertTrue(token.waitForExistence(timeout: 5))
        token.tap()
        XCTAssertTrue(waitForLabel(app.staticTexts["tokenStatus"], prefix: "已展开"))
        XCTAssertTrue(waitForLabel(app.staticTexts["remoteStatus"], prefix: "已加载 1 张"))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "token-expanded-remote-image"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testWholeLabelTapAndActionStaySeparate() {
        let app = openFeatures()
        let label = app.descendants(matching: .any)["tapLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.25)).tap()
        let status = app.staticTexts["tapStatus"]
        XCTAssertTrue(waitForLabel(status, prefix: "整段点击 1 次"), status.label)
        let action = app.descendants(matching: .any)["作者"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()
        XCTAssertTrue(waitForLabel(status, prefix: "动作：author"), status.label)
    }

    func testTruncationModeSwitchRevealsDocumentEnd() {
        let app = openFeatures()
        let control = app.segmentedControls["truncationModeControl"]
        scrollUntilHittable(control, in: app)
        // 无障碍元素只覆盖可见文字：尾部截断时看不到“全文结束”，头部与中间截断时可见。
        let ending = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '全文结束'"))
        XCTAssertEqual(ending.count, 0)
        control.buttons["head"].tap()
        XCTAssertTrue(ending.firstMatch.waitForExistence(timeout: 5))
        let head = XCTAttachment(screenshot: app.screenshot())
        head.name = "truncation-head"
        head.lifetime = .keepAlways
        add(head)
        control.buttons["middle"].tap()
        let opening = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '开头部分'"))
        XCTAssertTrue(opening.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(ending.firstMatch.waitForExistence(timeout: 5))
        control.buttons["tail"].tap()
        let gone = NSPredicate(format: "count == 0")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: ending)], timeout: 5), .completed
        )
    }

    func testMarkdownLinkTapReportsURLAction() {
        let app = openFeatures()
        let link = app.descendants(matching: .any)["查看文档"]
        scrollUntilHittable(link, in: app)
        link.tap()
        let status = app.staticTexts["markdownStatus"]
        XCTAssertTrue(waitForLabel(status, prefix: "链接："), status.label)
        XCTAssertTrue(status.label.contains("example.invalid/docs"), status.label)
        let debug = app.switches["debugSwitch"]
        scrollUntilHittable(debug, in: app)
        debug.tap()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "markdown-debug-overlay"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        var attempts = 0
        while !element.isHittable, attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable)
    }

    private func waitForLabel(_ element: XCUIElement, prefix: String) -> Bool {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
}
