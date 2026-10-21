import XCTest

@MainActor
final class HostMatrixUITests: XCTestCase {
    func testUIKitStackWidthsTableAndCollectionReuse() throws {
        let app = XCUIApplication()
        app.launch()
        open("openUIKitHostMatrix", in: app)
        let width = app.segmentedControls["hostUIKitWidth"]
        XCTAssertTrue(width.waitForExistence(timeout: 5))
        width.buttons["160"].tap()
        capture(app, name: "host-uikit-narrow-160")
        width.buttons["320"].tap()
        capture(app, name: "host-uikit-wide-320")
        width.buttons["160"].tap()
        XCTAssertTrue(app.staticTexts["hostUIKitCurrentRow"].label.contains("width=160"))
        app.segmentedControls["hostUIKitCallback"].buttons["B"].tap()

        try exerciseUIKitList(.table, content: .action, app: app, captureScreenshots: true)
        try exerciseUIKitList(.table, content: .button, app: app, captureScreenshots: false)
        try exerciseUIKitList(.collection, content: .action, app: app, captureScreenshots: true)
        try exerciseUIKitList(.collection, content: .button, app: app, captureScreenshots: false)
    }

    func testSwiftUIFrameStacksListAndLazyReuse() throws {
        let app = XCUIApplication()
        app.launch()
        open("openSwiftUIHostMatrix", in: app)
        let width = app.segmentedControls["hostSwiftUIWidth"]
        let containers = app.segmentedControls["hostSwiftUIContainer"]
        XCTAssertTrue(width.waitForExistence(timeout: 5))
        let naturalHeight = app.staticTexts["hostSwiftUINaturalHeight"]
        XCTAssertTrue(naturalHeight.waitForExistence(timeout: 5))
        XCTAssertTrue(naturalHeight.label.hasPrefix("natural="))
        XCTAssertTrue(
            naturalHeight.waitForNonzeroNaturalHeight(timeout: 5),
            "SwiftUI 自然高度未更新：\(naturalHeight.label)"
        )
        width.buttons["160"].tap()
        let frameGeometry = try geometry(in: app, expectedContainer: "Frame")
        capture(app, name: "host-swiftui-narrow-160")
        width.buttons["320"].tap()
        capture(app, name: "host-swiftui-wide-320")
        width.buttons["160"].tap()
        containers.buttons["HStack"].tap()
        let hStackGeometry = try geometry(in: app, expectedContainer: "HStack")
        XCTAssertEqual(hStackGeometry.width, frameGeometry.width + 20, accuracy: 1)
        containers.buttons["VStack"].tap()
        let vStackGeometry = try geometry(in: app, expectedContainer: "VStack")
        XCTAssertEqual(vStackGeometry.width, frameGeometry.width, accuracy: 1)
        XCTAssertEqual(vStackGeometry.height, frameGeometry.height + 8, accuracy: 1)

        app.segmentedControls["hostSwiftUICallback"].buttons["B"].tap()
        XCTAssertEqual(
            app.staticTexts["hostSwiftUIEvent"].label,
            "event=0;callback=B;handled=none;id=none"
        )
        containers.buttons["List"].tap()
        let list = app.collectionViews["hostSwiftUIList"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let firstGlyphs = app.otherElements.matching(identifier: "hostSwiftUIGlyph0")
        XCTAssertGreaterThan(firstGlyphs.count, 0)
        let firstAction = app.otherElements["hostSwiftUIAction0"]
        XCTAssertTrue(firstAction.waitForExistence(timeout: 5))
        try coordinate(named: "host-row-0", in: firstAction).tap()
        XCTAssertTrue(
            app.staticTexts["hostSwiftUIRowStatus0"].label.contains(
                "event=1;button=0;callback=B;handled=B;id=host-row-0"
            )
        )
        XCTAssertEqual(
            app.staticTexts["hostSwiftUIEvent"].label,
            "event=1;callback=B;handled=B;id=host-row-0"
        )
        XCTAssertTrue(naturalHeight.waitForNonzeroNaturalHeight(timeout: 5))
        scrollUntilOffscreen(app.staticTexts["hostSwiftUIRowStatus0"], in: list)
        let visibleListStatus = try visibleStatus(prefix: "hostSwiftUIRowStatus", excludingRow: 0, app: app)
        let visibleListRow = try rowID(identifier: visibleListStatus.identifier, prefix: "hostSwiftUIRowStatus")
        XCTAssertTrue(
            visibleListStatus.label.contains("row=\(visibleListRow);event=0;button=0;callback=B")
        )
        capture(app, name: "host-swiftui-list-scrolled")
        scrollUntilVisible(app.staticTexts["hostSwiftUIRowStatus0"], in: list)
        XCTAssertEqual(
            app.staticTexts["hostSwiftUIEvent"].label,
            "event=1;callback=B;handled=B;id=host-row-0"
        )
        capture(app, name: "host-swiftui-list-return")

        app.segmentedControls["hostSwiftUIContent"].buttons["小视"].tap()
        containers.buttons["LazyVStack"].tap()
        let lazy = app.scrollViews["hostSwiftUILazy"]
        XCTAssertTrue(lazy.waitForExistence(timeout: 5))
        let firstButton = app.buttons["hostSwiftUIAttachmentButton0"]
        XCTAssertTrue(firstButton.waitForExistence(timeout: 5))
        firstButton.tap()
        XCTAssertTrue(
            app.staticTexts["hostSwiftUIRowStatus0"].label.contains(
                "event=1;button=1;callback=B;handled=B;id=host-row-0"
            )
        )
        XCTAssertEqual(app.staticTexts["hostSwiftUIButtonStatus"].label, "button=1")
        XCTAssertTrue(naturalHeight.waitForNonzeroNaturalHeight(timeout: 5))
        scrollUntilOffscreen(app.staticTexts["hostSwiftUIRowStatus0"], in: lazy)
        let visibleLazyStatus = try visibleStatus(prefix: "hostSwiftUIRowStatus", excludingRow: 0, app: app)
        let visibleLazyRow = try rowID(identifier: visibleLazyStatus.identifier, prefix: "hostSwiftUIRowStatus")
        XCTAssertTrue(
            visibleLazyStatus.label.contains("row=\(visibleLazyRow);event=0;button=0;callback=B")
        )
        capture(app, name: "host-swiftui-lazy-scrolled")
        scrollUntilVisible(app.staticTexts["hostSwiftUIRowStatus0"], in: lazy)
        XCTAssertEqual(app.staticTexts["hostSwiftUIButtonStatus"].label, "button=1")
        capture(app, name: "host-swiftui-lazy-return")
    }

    func testBothHostsUseNativeButtonAndLatestCallbackB() throws {
        let app = XCUIApplication()
        app.launch()
        open("openUIKitHostMatrix", in: app)
        app.segmentedControls["hostUIKitCallback"].buttons["B"].tap()
        XCTAssertEqual(
            app.staticTexts["hostUIKitEvent"].label,
            "event=0;callback=B;handled=none;id=none"
        )
        let uikitPreview = app.otherElements["actionPreview"]
        XCTAssertTrue(uikitPreview.waitForExistence(timeout: 5))
        try coordinate(named: "host-row-0", in: uikitPreview).tap()
        XCTAssertEqual(
            app.staticTexts["hostUIKitEvent"].label,
            "event=1;callback=B;handled=B;id=host-row-0"
        )
        app.segmentedControls["hostUIKitContent"].buttons["小视图"].tap()
        let uikitButton = app.buttons["hostUIKitAttachmentButton"]
        XCTAssertTrue(uikitButton.waitForExistence(timeout: 5))
        uikitButton.tap()
        XCTAssertEqual(uikitButton.label, "0 · 1")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        open("openSwiftUIHostMatrix", in: app)
        app.segmentedControls["hostSwiftUICallback"].buttons["B"].tap()
        XCTAssertEqual(
            app.staticTexts["hostSwiftUIEvent"].label,
            "event=0;callback=B;handled=none;id=none"
        )
        let swiftPreview = app.otherElements["hostSwiftUIAction0"]
        XCTAssertTrue(swiftPreview.waitForExistence(timeout: 5))
        try coordinate(named: "host-row-0", in: swiftPreview).tap()
        XCTAssertEqual(
            app.staticTexts["hostSwiftUIEvent"].label,
            "event=1;callback=B;handled=B;id=host-row-0"
        )
        app.segmentedControls["hostSwiftUIContent"].buttons["小视"].tap()
        let swiftButton = app.buttons["hostSwiftUIAttachmentButton0"]
        XCTAssertTrue(swiftButton.waitForExistence(timeout: 5))
        swiftButton.tap()
        XCTAssertEqual(app.staticTexts["hostSwiftUIButtonStatus"].label, "button=1")
    }

    private func open(_ identifier: String, in app: XCUIApplication) {
        let cell = app.cells[identifier]
        let table = app.tables.firstMatch
        var attempts = 0
        while !cell.exists, attempts < 6 {
            table.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
    }

    private func scrollTo(_ element: XCUIElement, in scroll: XCUIElement) {
        var attempts = 0
        while !element.isHittable, attempts < 6 {
            scroll.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable)
    }

    private enum UIKitList {
        case table
        case collection

        var routeIdentifier: String {
            switch self {
            case .table: "openHostTable"
            case .collection: "openHostCollection"
            }
        }

        var containerIdentifier: String {
            switch self {
            case .table: "hostMatrixTable"
            case .collection: "hostMatrixCollection"
            }
        }

        var statusPrefix: String {
            switch self {
            case .table: "hostTableRowStatus"
            case .collection: "hostCollectionRowStatus"
            }
        }

        var actionPrefix: String {
            switch self {
            case .table: "hostTableAction"
            case .collection: "hostCollectionAction"
            }
        }

        var buttonPrefix: String {
            "hostRowAttachmentButton"
        }

        var screenshotName: String {
            switch self {
            case .table: "table"
            case .collection: "collection"
            }
        }
    }

    private enum UIKitListContent: Equatable {
        case action
        case button
    }

    private func exerciseUIKitList(
        _ kind: UIKitList,
        content: UIKitListContent,
        app: XCUIApplication,
        captureScreenshots: Bool
    ) throws {
        let contentControl = app.segmentedControls["hostUIKitContent"]
        contentControl.buttons[content == .action ? "动作" : "小视图"].tap()
        let route = app.buttons[kind.routeIdentifier]
        scrollTo(route, in: app.scrollViews["hostUIKitScroll"])
        route.tap()

        let scroll: XCUIElement = switch kind {
        case .table: app.tables[kind.containerIdentifier]
        case .collection: app.collectionViews[kind.containerIdentifier]
        }
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let firstStatus = app.staticTexts["\(kind.statusPrefix)0"]
        XCTAssertTrue(firstStatus.waitForExistence(timeout: 5))
        switch content {
        case .action:
            let action = app.otherElements["\(kind.actionPrefix)0"]
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            try coordinate(named: "host-row-0", in: action).tap()
            XCTAssertTrue(firstStatus.label.contains("row=0;event=1;button=0;callback=B;pressed=0"))
        case .button:
            let button = app.buttons["\(kind.buttonPrefix)0"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
            XCTAssertTrue(firstStatus.label.contains("row=0;event=0;button=1;callback=B;pressed=0"))
        }

        scrollUntilOffscreen(firstStatus, in: scroll)
        let reusedStatus = try visibleStatus(prefix: kind.statusPrefix, excludingRow: 0, app: app)
        let rowID = try rowID(identifier: reusedStatus.identifier, prefix: kind.statusPrefix)
        XCTAssertTrue(
            reusedStatus.label.contains("row=\(rowID);event=0;button=0;callback=B;pressed=0"),
            "复用状态与标识不一致：id=\(reusedStatus.identifier), label=\(reusedStatus.label)"
        )
        if captureScreenshots {
            capture(app, name: "host-uikit-\(kind.screenshotName)-scrolled")
        }
        scrollUntilVisible(firstStatus, in: scroll)
        let expected = content == .action
            ? "row=0;event=1;button=0;callback=B;pressed=0"
            : "row=0;event=0;button=1;callback=B;pressed=0"
        XCTAssertTrue(firstStatus.label.contains(expected))
        if captureScreenshots {
            capture(app, name: "host-uikit-\(kind.screenshotName)-return")
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func visibleStatus(
        prefix: String,
        excludingRow: Int,
        app: XCUIApplication
    ) throws -> XCUIElement {
        let query = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        let identifiers = Set(query.allElementsBoundByIndex.map(\.identifier))
        return try XCTUnwrap(identifiers.sorted().compactMap { identifier -> XCUIElement? in
            guard identifier != "\(prefix)\(excludingRow)" else { return nil }
            let candidate = app.staticTexts[identifier]
            return candidate.exists && candidate.isHittable ? candidate : nil
        }.first, "缺少滚动后可见的复用行状态")
    }

    private func rowID(identifier: String, prefix: String) throws -> Int {
        try XCTUnwrap(Int(identifier.dropFirst(prefix.count)), "无法从 \(identifier) 解析 rowID")
    }

    private func scrollUntilOffscreen(_ element: XCUIElement, in scroll: XCUIElement) {
        var attempts = 0
        while element.isHittable, attempts < 12 {
            scroll.swipeUp()
            attempts += 1
        }
        XCTAssertFalse(element.isHittable, "首行在 \(attempts) 次上滑后仍可点击")
    }

    private func scrollUntilVisible(_ element: XCUIElement, in scroll: XCUIElement) {
        var attempts = 0
        while !element.isHittable, attempts < 12 {
            scroll.swipeDown()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable, "首行在 \(attempts) 次下滑后仍未返回")
    }

    private func geometry(in app: XCUIApplication, expectedContainer: String) throws -> CGRect {
        let probe = app.otherElements["hostSwiftUIContainerGeometry"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        let expectedPrefix = "container=\(expectedContainer);"
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement, let value = element.value as? String else { return false }
            return value.hasPrefix(expectedPrefix)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
        let value = try XCTUnwrap(probe.value as? String)
        let entries: [String: CGFloat] = Dictionary(
            uniqueKeysWithValues: value.split(separator: ";").compactMap { entry in
                let pair = entry.split(separator: "=", maxSplits: 1)
                guard pair.count == 2, let number = Double(pair[1]) else { return nil }
                return (String(pair[0]), CGFloat(number))
            }
        )
        return try CGRect(
            x: XCTUnwrap(entries["x"], value),
            y: XCTUnwrap(entries["y"], value),
            width: XCTUnwrap(entries["width"], value),
            height: XCTUnwrap(entries["height"], value)
        )
    }

    private func coordinate(named name: String, in element: XCUIElement) throws -> XCUICoordinate {
        let value = element.value as? String ?? ""
        var entries: [String: CGPoint] = [:]
        for entry in value.split(separator: ";") {
            let pair = entry.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            let values = pair[1].split(separator: ",").compactMap { Double($0) }
            guard values.count == 2 else { continue }
            entries[pair[0]] = CGPoint(x: values[0], y: values[1])
        }
        let point = try XCTUnwrap(entries[name], "缺少动作坐标 \(name)：\(value)")
        return element.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(
            CGVector(dx: point.x - element.frame.minX, dy: point.y - element.frame.minY)
        )
    }

    private func coordinate(named name: String, in query: XCUIElementQuery) throws -> XCUICoordinate {
        let element = try XCTUnwrap(query.allElementsBoundByIndex.first {
            ($0.value as? String)?.contains("\(name)=") == true
        }, "缺少携带动作坐标 \(name) 的元素")
        return try coordinate(named: name, in: element)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    func waitForNonzeroNaturalHeight(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement,
                  element.label.hasPrefix("natural="),
                  let value = Double(element.label.dropFirst("natural=".count))
            else { return false }
            return value > 0
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
