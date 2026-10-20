import XCTest

@MainActor
final class ActionDemoUITests: XCTestCase {
    func testUIKitActionPageUsesRealTapLongPressDragAndAttachmentPriority() throws {
        let app = launchAndOpen("openUIKitActions")
        let preview = app.otherElements["actionPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))

        try coordinate(named: "single", in: preview).tap()
        assertStatus(app, contains: ["events=1", "callback=A", "kind=tap", "id=single"])

        try coordinate(named: "cross.1", in: preview).press(forDuration: 0.65)
        assertStatus(app, contains: ["events=2", "callback=A", "kind=longPress", "id=cross"])

        let beforeDrag = preview.frame.minY
        try coordinate(named: "single", in: preview).press(
            forDuration: 0.05,
            thenDragTo: preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -1.0))
        )
        assertStatus(app, contains: ["events=2"])
        XCTAssertLessThan(preview.frame.minY, beforeDrag)

        let button = app.buttons["actionAttachmentButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertEqual(app.staticTexts["actionButtonStatus"].label, "button=1")
        assertStatus(app, contains: ["events=2"])

        let callback = app.segmentedControls["actionCallbackControl"]
        callback.buttons["无"].tap()
        try coordinate(named: "single", in: preview).tap()
        assertStatus(app, contains: ["events=2"])
        callback.buttons["A"].tap()
        try coordinate(named: "single", in: preview).tap()
        assertStatus(app, contains: ["events=3", "callback=A", "kind=tap", "id=single"])
    }

    func testSwiftUIUsesLatestCallbackAndPreservesActionRanges() throws {
        let app = launchAndOpen("openSwiftUIActions")
        let preview = app.otherElements["actionPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))

        try coordinate(named: "single", in: preview).tap()
        assertStatus(app, contains: ["events=1", "callback=A", "kind=tap", "id=single"])
        app.segmentedControls["actionCallbackControl"].buttons["B"].tap()
        try coordinate(named: "duplicate#0", in: preview).tap()
        assertStatus(app, contains: ["events=2", "callback=B", "kind=tap", "id=duplicate"])
        let firstRange = try status(app).rangeValue

        try coordinate(named: "duplicate#1", in: preview).tap()
        assertStatus(app, contains: ["events=3", "callback=B", "kind=tap", "id=duplicate"])
        XCTAssertNotEqual(try status(app).rangeValue, firstRange)

        try coordinate(named: "cross.0", in: preview).press(forDuration: 0.65)
        assertStatus(app, contains: ["events=4", "callback=B", "kind=longPress", "id=cross"])

        app.segmentedControls["actionCallbackControl"].buttons["无"].tap()
        try coordinate(named: "single", in: preview).tap()
        assertStatus(app, contains: ["events=4"])
        app.segmentedControls["actionCallbackControl"].buttons["A"].tap()
        try coordinate(named: "single", in: preview).tap()
        assertStatus(app, contains: ["events=5", "callback=A", "kind=tap", "id=single"])

        let beforeDrag = preview.frame.minY
        try coordinate(named: "single", in: preview).press(
            forDuration: 0.05,
            thenDragTo: preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -1.0))
        )
        assertStatus(app, contains: ["events=5"])
        XCTAssertLessThan(preview.frame.minY, beforeDrag)
    }

    func testUIKitComplexGeometryTruncationClippingAndScreenshots() throws {
        try verifyComplexGeometry("openUIKitActions", name: "UIKit-actions")
    }

    func testSwiftUIComplexGeometryTruncationClippingAndScreenshots() throws {
        try verifyComplexGeometry("openSwiftUIActions", name: "SwiftUI-actions")
    }

    func testSelectableActionListSeparatesActionsFromBlankSpace() throws {
        let app = launchAndOpen("openActionList")
        let row = app.otherElements["actionListLabel0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        try coordinate(named: "single", in: row).tap()
        assertListStatus(app, contains: ["selection=0", "events=1", "id=single"])
        try coordinate(named: "cross.1", in: row).press(forDuration: 0.65)
        assertListStatus(app, contains: ["selection=0", "events=2", "id=cross"])
        try coordinate(named: "plain", in: row).tap()
        assertListStatus(app, contains: ["selection=1", "last=0", "events=2"])
        try coordinate(named: "lineEnd", in: row).tap()
        assertListStatus(app, contains: ["selection=2", "last=0", "events=2"])
        try coordinate(named: "lineGap", in: row).tap()
        assertListStatus(app, contains: ["selection=3", "last=0", "events=2"])
        try coordinate(named: "inset", in: row).tap()
        assertListStatus(app, contains: ["selection=4", "last=0", "events=2"])
        try coordinate(named: "alignment", in: row).tap()
        assertListStatus(app, contains: ["selection=5", "last=0", "events=2"])
    }

    func testActionListActionDragCancelsWithoutBlockingScroll() throws {
        let app = launchAndOpen("openActionList")
        let table = app.tables["actionSelectionList"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        let row = app.otherElements["actionListLabel0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        let firstFrame = row.frame
        try coordinate(named: "single", in: row).press(
            forDuration: 0.05,
            thenDragTo: table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        )
        XCTAssertNotEqual(row.frame, firstFrame)
        assertListStatus(app, contains: ["events=0"])
    }

    func testActionListPlainTextDragAllowsScroll() throws {
        let app = launchAndOpen("openActionList")
        let table = app.tables["actionSelectionList"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        let row = app.otherElements["actionListLabel0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        let firstFrame = row.frame
        try coordinate(named: "plain", in: row).press(
            forDuration: 0.05,
            thenDragTo: table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        )
        XCTAssertNotEqual(row.frame, firstFrame)
        assertListStatus(app, contains: ["events=0"])
    }

    func testActionListLineGapDragAllowsScroll() throws {
        let app = launchAndOpen("openActionList")
        let table = app.tables["actionSelectionList"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        let row = app.otherElements["actionListLabel0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        let firstFrame = row.frame
        try coordinate(named: "lineGap", in: row).press(
            forDuration: 0.05,
            thenDragTo: table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        )
        XCTAssertNotEqual(row.frame, firstFrame)
        assertListStatus(app, contains: ["events=0"])
    }

    func testActionListReuseAndNilCallbackFallback() throws {
        let app = launchAndOpen("openActionList")
        let table = app.tables["actionSelectionList"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))

        let reused = app.otherElements["actionListLabel10"]
        scroll(reused, fullyInto: table, direction: .up)
        try coordinate(named: "single", in: reused).tap()
        assertListStatus(app, contains: ["events=1", "row=10", "id=single", "range=13:5"])

        let row = app.otherElements["actionListLabel0"]
        scroll(row, fullyInto: table, direction: .down)
        try coordinate(named: "single", in: row).tap()
        assertListStatus(app, contains: ["events=2", "row=0", "id=single", "range=11:2"])

        app.buttons["actionListCallbackToggle"].tap()
        try coordinate(named: "single", in: row).tap()
        assertListStatus(app, contains: ["selection=1", "last=0", "events=2", "callback=nil"])
    }

    private func verifyComplexGeometry(_ identifier: String, name: String) throws {
        let app = launchAndOpen(identifier)
        let preview = app.otherElements["actionPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        var count = 0
        for (key, id, range) in [
            ("rtl.left", "rtl", "47:5"), ("rtl.right", "rtl", "47:5"),
            ("emoji.left", "emoji", "59:11"), ("emoji.right", "emoji", "59:11"),
            ("fi.left", "fi", "76:6"), ("fi.right", "fi", "76:6"),
            ("decorative-image", "decorative-image", "88:1"),
            ("decorative-view", "decorative-view", "93:1")
        ] {
            try coordinate(named: key, in: preview).tap()
            count += 1
            assertStatus(app, contains: ["events=\(count)", "kind=tap", "id=\(id)", "range=\(range)"])
        }
        let button = app.buttons["actionAttachmentButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertEqual(app.staticTexts["actionButtonStatus"].label, "button=1")
        assertStatus(app, contains: ["events=\(count)"])

        app.segmentedControls["actionCallbackControl"].buttons["B"].tap()
        try coordinate(named: "single", in: preview).tap()
        count += 1
        assertStatus(app, contains: ["events=\(count)", "callback=B", "id=single"])
        capture(app, name: "\(name)-event-state")

        let display = app.segmentedControls["actionDisplayControl"]
        display.buttons["截断"].tap()
        waitForDiagnostic("token", in: preview)
        try coordinate(named: "token", in: preview).tap()
        assertStatus(app, contains: ["events=\(count)"])
        try coordinate(named: "truncated", in: preview).tap()
        count += 1
        assertStatus(app, contains: ["events=\(count)", "id=truncated", "range=103:30"])
        capture(app, name: "\(name)-truncated-inset")

        display.buttons["裁切"].tap()
        waitForDiagnostic("clipped.visible", in: preview)
        try coordinate(named: "clipped.visible", in: preview).tap()
        count += 1
        assertStatus(app, contains: ["events=\(count)", "id=cross", "range=19:11"])
        try coordinate(named: "clipped.hidden", in: preview).tap()
        assertStatus(app, contains: ["events=\(count)"])
        capture(app, name: "\(name)-short-height-clipping")
        app.terminate()
    }

    private func launchAndOpen(_ identifier: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        let entry = app.cells[identifier]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        return app
    }

    private func coordinate(named name: String, in element: XCUIElement) throws -> XCUICoordinate {
        let points = try DiagnosticPoints(value: element.value as? String ?? "")
        let point = try XCTUnwrap(points[name], "缺少 \(name) 的真实布局诊断点：\(element.value ?? "nil")")
        let frame = element.frame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        return element.coordinate(withNormalizedOffset: CGVector(
            dx: (point.x - frame.minX) / frame.width,
            dy: (point.y - frame.minY) / frame.height
        ))
    }

    private func assertStatus(_ app: XCUIApplication, contains parts: [String]) {
        let element = app.staticTexts["actionEventStatus"]
        let predicate = NSPredicate { object, _ in
            guard let value = (object as? XCUIElement)?.label else { return false }
            return parts.allSatisfy(value.contains)
        }
        expectation(for: predicate, evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }

    private func assertListStatus(_ app: XCUIApplication, contains parts: [String]) {
        let element = app.staticTexts["actionListStatus"]
        let predicate = NSPredicate { object, _ in
            guard let value = (object as? XCUIElement)?.label else { return false }
            return parts.allSatisfy(value.contains)
        }
        expectation(for: predicate, evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }

    private func waitForDiagnostic(_ name: String, in element: XCUIElement) {
        let predicate = NSPredicate(format: "value CONTAINS %@", "\(name)=")
        expectation(for: predicate, evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }

    private func scroll(_ element: XCUIElement, fullyInto container: XCUIElement, direction: ScrollDirection) {
        let visibleFrame = container.frame.insetBy(dx: 2, dy: 2)
        for _ in 0 ..< 12 {
            if element.exists, element.isHittable, visibleFrame.contains(element.frame) {
                return
            }
            switch direction {
            case .up:
                container.swipeUp()
            case .down:
                container.swipeDown()
            }
        }
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(visibleFrame.contains(element.frame), "目标元素未完整进入列表可见区域：\(element.frame)")
    }

    private func status(_ app: XCUIApplication) throws -> ActionStatus {
        try ActionStatus(app.staticTexts["actionEventStatus"].label)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private enum ScrollDirection {
    case up
    case down
}

private struct DiagnosticPoints {
    private var storage: [String: CGPoint] = [:]

    init(value: String) throws {
        for component in value.split(separator: ";") {
            let pair = component.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let coordinates = pair[1].split(separator: ",")
            guard coordinates.count == 2,
                  let x = Double(coordinates[0]),
                  let y = Double(coordinates[1]) else { continue }
            storage[String(pair[0])] = CGPoint(x: x, y: y)
        }
        if storage.isEmpty {
            throw NSError(domain: "ActionDemoUITests", code: 1, userInfo: [NSLocalizedDescriptionKey: value])
        }
    }

    subscript(name: String) -> CGPoint? {
        storage[name]
    }
}

private struct ActionStatus {
    let rangeValue: String

    init(_ value: String) throws {
        guard let range = value.split(separator: " ").first(where: { $0.hasPrefix("range=") }) else {
            throw NSError(domain: "ActionDemoUITests", code: 2, userInfo: [NSLocalizedDescriptionKey: value])
        }
        rangeValue = String(range.dropFirst("range=".count))
    }
}
