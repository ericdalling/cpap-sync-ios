import XCTest

final class LaunchTests: XCTestCase {
    func testSyncHomeLaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["testConnectionButton"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["syncStatus"].exists)

        // SwiftUI List lazily creates offscreen rows. Scroll before searching
        // for the sync/export/version controls rather than assuming .exists.
        XCTAssertTrue(findAfterScrolling(app.buttons["syncButton"], in: app))
        XCTAssertTrue(findAfterScrolling(app.buttons["exportButton"], in: app))
        XCTAssertFalse(app.buttons["exportButton"].isEnabled)
        XCTAssertTrue(findAfterScrolling(app.staticTexts["appVersion"], in: app))
    }

    private func findAfterScrolling(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.exists { return true }
        for _ in 0..<6 {
            app.swipeUp()
            if element.exists { return true }
        }
        return false
    }
}
