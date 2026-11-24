import XCTest

final class LaunchTests: XCTestCase {
    func testSyncHomeLaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["testConnectionButton"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["syncButton"].exists)
        XCTAssertTrue(app.staticTexts["syncStatus"].exists)
        XCTAssertTrue(app.staticTexts["appVersion"].exists)
        XCTAssertFalse(app.buttons["exportButton"].isEnabled)
    }
}
