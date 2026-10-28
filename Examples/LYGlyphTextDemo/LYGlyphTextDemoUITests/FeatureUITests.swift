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

    private func waitForLabel(_ element: XCUIElement, prefix: String) -> Bool {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
}
