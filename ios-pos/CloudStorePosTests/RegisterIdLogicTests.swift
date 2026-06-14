import XCTest
@testable import CloudStorePos

final class RegisterIdLogicTests: XCTestCase {
    func testRegisterIdUsesTabletPrefix() {
        XCTAssertEqual(
            RegisterIdLogic.registerId(vendorUUID: "550E8400-E29B-41D4-A716-446655440000"),
            "tablet-550E8400-E29B-41D4-A716-446655440000"
        )
    }

    func testRegisterIdUnknownWhenVendorMissing() {
        XCTAssertEqual(RegisterIdLogic.registerId(vendorUUID: nil), "tablet-unknown")
        XCTAssertEqual(RegisterIdLogic.registerId(vendorUUID: "   "), "tablet-unknown")
    }
}
