import XCTest
@testable import CloudStorePos

final class PinSignInLogicTests: XCTestCase {
    func testMaskedPin() {
        XCTAssertEqual(PinSignInLogic.maskedPin(""), "")
        XCTAssertEqual(PinSignInLogic.maskedPin("8930"), "••••")
    }

    func testAppendPinDigit() {
        XCTAssertEqual(PinSignInLogic.appendPinDigit(current: "", digit: "8"), "8")
        XCTAssertEqual(PinSignInLogic.appendPinDigit(current: "89", digit: "3"), "893")
        XCTAssertEqual(PinSignInLogic.appendPinDigit(current: "12345678", digit: "9"), "12345678")
        XCTAssertEqual(PinSignInLogic.appendPinDigit(current: "12", digit: "a"), "12")
    }

    func testBackspacePin() {
        XCTAssertEqual(PinSignInLogic.backspacePin("893"), "89")
        XCTAssertEqual(PinSignInLogic.backspacePin(""), "")
    }
}
