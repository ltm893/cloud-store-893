import XCTest
@testable import CloudStoreLister

final class RegisterIdLogicTests: XCTestCase {
    func testRegisterIdUsesListerPrefix() {
        XCTAssertEqual(
            RegisterIdLogic.registerId(vendorUUID: "550E8400-E29B-41D4-A716-446655440000"),
            "lister-550E8400-E29B-41D4-A716-446655440000"
        )
    }

    func testRegisterIdUnknownWhenVendorMissing() {
        XCTAssertEqual(RegisterIdLogic.registerId(vendorUUID: nil), "lister-unknown")
        XCTAssertEqual(RegisterIdLogic.registerId(vendorUUID: "   "), "lister-unknown")
    }
}
