import XCTest

final class LaunchTests: XCTestCase {
    func testHelloWorldLaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["helloMessage"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["helloMessage"].label, "Hello, CPAP Sync!")
        XCTAssertTrue(app.staticTexts["appVersion"].exists)
    }
}
