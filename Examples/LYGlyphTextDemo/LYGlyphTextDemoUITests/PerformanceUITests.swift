import XCTest

@MainActor
final class PerformanceUITests: XCTestCase {
    func testRealTextButtonAndReuseKeepRowStateThenStopReleasesViews() throws {
        let app = XCUIApplication()
        app.launch()
        let home = app.tables.firstMatch
        let route = app.cells["openPerformance"]
        for _ in 0 ..< 8 where !route.isHittable {
            home.swipeUp()
        }
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        route.tap()
        let table = app.tables["performanceTable"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        let row0 = app.cells["performanceRow0"]
        let row1 = app.cells["performanceRow1"]
        let action0 = row0.buttons["执行"]
        XCTAssertTrue(action0.waitForExistence(timeout: 5))
        action0.tap()
        XCTAssertEqual(app.staticTexts["performanceRowStatus0"].label, "row=0;action=1;button=0")
        let button1 = row1.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "performanceButton1-"))
            .firstMatch
        XCTAssertTrue(button1.waitForExistence(timeout: 5))
        button1.tap()
        XCTAssertEqual(app.staticTexts["performanceRowStatus1"].label, "row=1;action=0;button=1")
        capture(app, name: "performance-actions-native-button")
        let firstStatus = app.staticTexts["performanceRowStatus0"]
        for _ in 0 ..< 6 where firstStatus.isHittable {
            table.swipeUp()
        }
        XCTAssertFalse(firstStatus.isHittable)
        let visible = try XCTUnwrap(app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "performanceRowStatus")
        ).allElementsBoundByIndex.first { $0.isHittable })
        let visibleID = try XCTUnwrap(Int(visible.identifier.dropFirst("performanceRowStatus".count)))
        XCTAssertGreaterThan(visibleID, 1)
        XCTAssertEqual(visible.label, "row=\(visibleID);action=0;button=0")
        capture(app, name: "performance-reused-scrolled")
        for _ in 0 ..< 10 where !firstStatus.isHittable {
            table.swipeDown()
        }
        XCTAssertTrue(firstStatus.isHittable)
        XCTAssertEqual(firstStatus.label, "row=0;action=1;button=0")
        XCTAssertEqual(app.staticTexts["performanceRowStatus1"].label, "row=1;action=0;button=1")
        row0.buttons["执行"].tap()
        XCTAssertEqual(firstStatus.label, "row=0;action=2;button=0")
        row1.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "performanceButton1-")).firstMatch.tap()
        XCTAssertEqual(app.staticTexts["performanceRowStatus1"].label, "row=1;action=0;button=2")
        capture(app, name: "performance-return-state")
        app.buttons["performanceStop"].tap()
        let status = app.staticTexts["performanceStatus"]
        let stopped = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return element.label.contains("live=0;") && element.label.contains("stopped=1")
        }
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: stopped, object: status)], timeout: 5),
            .completed
        )
        let statusAttachment = XCTAttachment(string: status.label)
        statusAttachment.name = "performance-stop-weak-counts"
        statusAttachment.lifetime = .keepAlways
        add(statusAttachment)
        let fields = status.label.components(separatedBy: "\n").last?.components(separatedBy: ";") ?? []
        let values = Dictionary(uniqueKeysWithValues: fields.compactMap { field -> (String, Int)? in
            let pair = field.split(separator: "=")
            guard pair.count == 2, let value = Int(pair[1]) else { return nil }
            return (String(pair[0]), value)
        })
        XCTAssertGreaterThan(try XCTUnwrap(values["factory"]), 0)
        XCTAssertEqual(values["factory"], values["unmount"])
        XCTAssertEqual(values["action"], 2)
        XCTAssertEqual(values["button"], 2)
        capture(app, name: "performance-stopped-cleared")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
