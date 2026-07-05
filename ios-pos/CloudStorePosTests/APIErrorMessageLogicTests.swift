import XCTest
@testable import CloudStorePos

final class APIErrorMessageLogicTests: XCTestCase {
    func testParsesJsonErrorField() {
        XCTAssertEqual(
            APIErrorMessageLogic.message(fromBody: #"{"error":"Cart is empty"}"#),
            "Cart is empty"
        )
    }

    func testHttpErrorMessagePrefersJsonError() {
        XCTAssertEqual(
            APIErrorMessageLogic.httpErrorMessage(
                statusCode: 400,
                body: #"{"error":"checkoutTotal must match register total 10.60"}"#
            ),
            "checkoutTotal must match register total 10.60"
        )
    }

    func testHttpErrorMessageFallsBackToStatus() {
        XCTAssertEqual(
            APIErrorMessageLogic.httpErrorMessage(statusCode: 502, body: nil),
            "Server error (502)"
        )
    }

    func testMessageIncludesMaxOrderable() {
        XCTAssertEqual(
            APIErrorMessageLogic.message(
                fromBody: #"{"error":"Insufficient stock for Beans (only 3 available)","maxOrderable":3}"#
            ),
            "Insufficient stock for Beans (only 3 available) (max 3 can be ordered)"
        )
    }
}
