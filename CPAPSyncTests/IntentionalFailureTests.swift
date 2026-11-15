import XCTest

final class IntentionalFailureTests: XCTestCase {
    func testIntentionalFailureForCIGate() {
        XCTFail("Intentional failure: verify CI rejects failed tests; never merge this branch")
    }
}
