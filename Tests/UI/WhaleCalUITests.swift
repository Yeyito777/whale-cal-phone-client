import XCTest

@MainActor
final class WhaleCalUITests: XCTestCase {
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
        snapshot("04-day", app)
        app.buttons["Done"].tap()
        app.buttons["New event"].tap()
        XCTAssertTrue(app.navigationBars["New item"].waitForExistence(timeout: 5))
        snapshot("05-editor", app)
        app.buttons["Cancel"].tap()
        openOption("Calendars", app)
        XCTAssertTrue(app.navigationBars["Calendars"].waitForExistence(timeout: 5))
        snapshot("06-calendars", app)
        app.buttons["Done"].tap()
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
