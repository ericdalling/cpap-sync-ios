import XCTest
@testable import CPAPSync

final class AppVersionTests: XCTestCase {
    func testDisplay() {
        XCTAssertEqual(AppVersion(version: "0.0.1", build: "42").display, "Version 0.0.1 (42)")
    }
    func testUnknownValues() {
        XCTAssertEqual(AppVersion(version: "Unknown", build: "Unknown").display, "Version Unknown (Unknown)")
    }
}
