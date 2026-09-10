import XCTest

@MainActor
final class WhaleCalUITests: XCTestCase {
    func testDeadlineChecklistAndLocalFilters() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-concurrency", "--ui-test-deadlines"]
        app.launch()
        app.segmentedControls.buttons["Deadlines"].tap()
        XCTAssertTrue(app.otherElements["Deadline checklist"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Deadline details old-due"].exists, "Overdue deadlines don't age out")
        XCTAssertFalse(app.buttons["Deadline details done-due"].exists)
        snapshot("deadline-checklist", app)
        app.buttons["Deadline details today-due"].tap()
        XCTAssertTrue(app.staticTexts["No time specified"].waitForExistence(timeout: 5))
        snapshot("deadline-readable-details", app)
        app.navigationBars["Details"].buttons["Done"].tap()
        app.buttons["Select"].tap()
        app.buttons["Select shown"].tap()
        XCTAssertTrue(app.staticTexts["3 selected"].exists)
        app.segmentedControls["Deadline filter"].buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Completed")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["0 selected"].exists, "Changing filter clears bulk selection")
        XCTAssertTrue(app.buttons["Deadline details done-due"].exists)
        app.buttons["Cancel selection"].tap()
        app.segmentedControls["Deadline filter"].buttons["All"].tap()
        openOption("Calendars", app)
        let group = app.buttons["Calendar group fixture-group"]
        if group.value as? String == "Collapsed" { group.tap() }
        let work = app.buttons["Calendar visibility work"]
        XCTAssertEqual(work.value as? String, "Selected")
        work.tap()
        XCTAssertEqual(work.value as? String, "Not selected", "Local filters work offline")
        app.buttons["Close calendars"].tap()
        XCTAssertFalse(app.buttons["Deadline details old-due"].exists)
        XCTAssertTrue(app.buttons["Deadline details today-due"].exists)
        openOption("Calendars", app)
        app.buttons["Calendar visibility work"].tap()
        app.buttons["Close calendars"].tap()
        XCTAssertTrue(app.buttons["Deadline details old-due"].exists, "Showing a calendar restores its cached deadlines without a server write")
    }

    func testConcurrentEventsAndDetails() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-concurrency"]
        app.launch()
        XCTAssertTrue(app.otherElements["Day timeline"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Timeline event fixture-0"].exists)
        XCTAssertTrue(app.buttons["Timeline event fixture-1"].exists)
        XCTAssertFalse(app.staticTexts["Earlier today"].exists)
        snapshot("concurrent-day", app)
        app.buttons["Timeline event fixture-0"].tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        snapshot("concurrent-details", app)
        let focus = app.descendants(matching: .any).matching(identifier: "Event details fixture-0").firstMatch
        XCTAssertTrue(focus.staticTexts["At the same time"].exists)
        XCTAssertTrue(focus.staticTexts["Delivery window"].exists)
        XCTAssertFalse(focus.staticTexts["Planning session"].exists, "Transitive overlap isn't a direct overlap")
        focus.staticTexts["Delivery window"].tap()
        let delivery = app.descendants(matching: .any).matching(identifier: "Event details fixture-1").firstMatch
        XCTAssertTrue(delivery.staticTexts["Planning session"].waitForExistence(timeout: 5))
        XCTAssertTrue(delivery.staticTexts["Focus session"].exists)
        app.navigationBars["Details"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        XCTAssertFalse(focus.staticTexts["Planning session"].exists)
        app.navigationBars["Details"].buttons["Done"].tap()
        XCTAssertTrue(app.otherElements["Day timeline"].waitForExistence(timeout: 5))
        for _ in 0..<3 {
            if app.buttons["Timeline event fixture-3"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["Timeline event fixture-3"].isHittable, "Completed history stays visible")
        snapshot("completed-history-free-time", app)
    }

    func testDenseTimelineScrollDoesNotOpenDrawer() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-concurrency", "--ui-test-dense"]
        app.launch()
        XCTAssertTrue(app.otherElements["Day timeline"].waitForExistence(timeout: 10))
        let target = app.buttons["Timeline event fixture-1"]
        for _ in 0..<4 {
            if target.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)))
        }
        XCTAssertTrue(target.isHittable, "All parallel lanes remain reachable")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertFalse(app.otherElements["Calendar drawer"].exists, "Rightward timeline scroll must not open the drawer")
        snapshot("dense-parallel-timeline", app)
    }

    func testCalendarDrawerGestures() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Month heading"].waitForExistence(timeout: 20))
        assertLive(app)
        let drawer = app.otherElements.matching(identifier: "Calendar drawer").firstMatch
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45)))
        XCTAssertTrue(drawer.waitForExistence(timeout: 5), "Swipe right opens calendar drawer")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Calendar visibility ")).firstMatch.exists)
        snapshot("drawer-open", app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.65))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)))
        XCTAssertTrue(drawer.exists, "Vertical calendar-list scrolling must not dismiss the drawer")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(drawer.waitForNonExistence(timeout: 5), "Outside tap dismisses")
        openOption("Calendars", app)
        XCTAssertTrue(drawer.waitForExistence(timeout: 5), "Overflow menu opens the same drawer")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.45)))
        XCTAssertTrue(drawer.waitForNonExistence(timeout: 5), "Swipe left dismisses")
        openOption("Calendars", app)
        app.buttons["Manage calendars"].tap()
        XCTAssertTrue(app.navigationBars["Calendars"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(drawer.waitForNonExistence(timeout: 5))
        app.buttons["Day details"].tap()
        XCTAssertTrue(app.navigationBars["Day schedule"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.65))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.65)))
        XCTAssertTrue(drawer.waitForExistence(timeout: 5), "Drawer also opens over the full day schedule")
        app.buttons["Close calendars"].tap()
        XCTAssertTrue(drawer.waitForNonExistence(timeout: 5))
        app.buttons["Done"].tap()
    }

    func testCalendarGroupCollapseKeepsSchedule() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-concurrency"]
        app.launch()
        XCTAssertTrue(app.otherElements["Day timeline"].waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.4))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4)))
        let group = app.buttons["Calendar group fixture-group"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        if group.value as? String == "Collapsed" { group.tap() }
        XCTAssertTrue(app.buttons["Calendar visibility work"].exists)
        group.tap()
        XCTAssertTrue(app.buttons["Calendar visibility work"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Calendar visibility personal"].exists)
        snapshot("group-collapsed", app)
        app.buttons["Close calendars"].tap()
        XCTAssertTrue(app.buttons["Timeline event fixture-0"].exists, "Collapsing a group must not hide its events")
    }

    func testLiveCalendarNavigation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Month heading"].waitForExistence(timeout: 20))
        assertLive(app)
        XCTAssertFalse(app.staticTexts["WHALE CAL"].exists)
        XCTAssertFalse(app.staticTexts["LIVE"].exists)
        XCTAssertFalse(app.staticTexts["Next Event:"].exists)
        XCTAssertFalse(app.staticTexts["Next Due:"].exists)
        XCTAssertFalse(app.textFields["Search this view"].exists)
        snapshot("01-month", app)
        openOption("Search", app)
        XCTAssertTrue(app.textFields["Search this view"].waitForExistence(timeout: 5))
        app.textFields["Search this view"].tap()
        app.textFields["Search this view"].typeText("NoMatchingCalendarItemXYZ")
        XCTAssertTrue(app.staticTexts["No matching items."].waitForExistence(timeout: 5))
        app.buttons["Close search"].tap()
        XCTAssertFalse(app.textFields["Search this view"].exists)
        app.segmentedControls.buttons["Week"].tap()
        snapshot("02-week", app)
        app.segmentedControls.buttons["Agenda"].tap()
        snapshot("03-agenda", app)
        app.segmentedControls.buttons["Month"].tap()
        app.buttons["Day details"].tap()
        XCTAssertTrue(app.navigationBars["Day schedule"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements.matching(identifier: "Day timeline").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements.matching(identifier: "Day availability").firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Earlier today"].exists)
        snapshot("04-day", app)
        app.buttons["Done"].tap()
        app.buttons["New event"].tap()
        XCTAssertTrue(app.navigationBars["New item"].waitForExistence(timeout: 5))
        snapshot("05-editor", app)
        app.buttons["Cancel"].tap()
        openOption("Calendars", app)
        let drawer = app.otherElements.matching(identifier: "Calendar drawer").firstMatch
        XCTAssertTrue(drawer.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Calendar visibility ")).firstMatch.exists)
        snapshot("06-calendars", app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(drawer.waitForNonExistence(timeout: 5), "Tapping outside dismisses the drawer")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45)))
        XCTAssertTrue(drawer.waitForExistence(timeout: 5), "Right swipe opens the drawer")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.45)))
        XCTAssertTrue(drawer.waitForNonExistence(timeout: 5), "Left swipe closes the drawer")
        openOption("Connection settings", app)
        waitForLiveStatus(app)
        snapshot("07-connection", app)
        app.buttons["Reconnect now"].tap()
        waitForLiveStatus(app)
        app.buttons["Done"].tap()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        assertLive(app)
    }
    private func assertLive(_ app: XCUIApplication) {
        openOption("Connection settings", app)
        XCTAssertTrue(app.navigationBars["Connection"].waitForExistence(timeout: 5))
        waitForLiveStatus(app)
        app.buttons["Done"].tap()
    }
    private func waitForLiveStatus(_ app: XCUIApplication) {
        let status = app.descendants(matching: .any).matching(identifier: "Connection status").firstMatch
        let live = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Live"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [live], timeout: 60), .completed)
    }
    private func openOption(_ option: String, _ app: XCUIApplication) {
        let menu = app.buttons["Calendar options"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        // The first tap can be consumed by SpringBoard's foreground transition.
        if !app.buttons[option].waitForExistence(timeout: 3) { menu.tap() }
        XCTAssertTrue(app.buttons[option].waitForExistence(timeout: 5))
        app.buttons[option].tap()
    }
    private func snapshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
