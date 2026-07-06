import XCTest
@testable import CloudStoreLister

final class BarcodeNormalizeLogicTests: XCTestCase {
    func testEan13CheckDigitForCrystalSpringWater() {
        XCTAssertEqual(BarcodeNormalizeLogic.ean13CheckDigit("872000000402"), "1")
    }

    func testScannedEan13IncludesCatalogBarcode() {
        let candidates = BarcodeNormalizeLogic.lookupCandidates("8720000004021")
        XCTAssertTrue(candidates.contains("8720000004021"))
        XCTAssertTrue(candidates.contains("872000000402"))
    }

    func testCatalogBarcodeIncludesScannedEan13() {
        let candidates = BarcodeNormalizeLogic.lookupCandidates("872000000402")
        XCTAssertTrue(candidates.contains("872000000402"))
        XCTAssertTrue(candidates.contains("8720000004021"))
    }
}
