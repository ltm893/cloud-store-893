import XCTest
@testable import CloudStoreLister

final class ProductBarcodeTests: XCTestCase {
    func testUpcWinsOverTheCode128OnTheSameBottle() {
        let selection = ProductBarcode.preferred(from: [
            .init(symbology: .code128, value: "00000432500170"),
            .init(symbology: .ean13, value: "0080432500170")
        ])
        XCTAssertEqual(selection?.symbology, .upcA)
        XCTAssertEqual(selection?.value, "080432500170")
        XCTAssertEqual(selection?.ignored.map(\.value), ["00000432500170"])
    }

    func testRealEan13KeepsAll13Digits() {
        let selection = ProductBarcode.preferred(from: [
            .init(symbology: .ean13, value: "8008385000068")
        ])
        XCTAssertEqual(selection?.symbology, .ean13)
        XCTAssertEqual(selection?.value, "8008385000068")
    }

    func testCode128IsKeptWhenItIsTheOnlyCode() {
        let selection = ProductBarcode.preferred(from: [
            .init(symbology: .code128, value: "00000432500170")
        ])
        XCTAssertEqual(selection?.symbology, .code128)
        XCTAssertEqual(selection?.value, "00000432500170")
    }

    func testLeadingApostropheIsNotPartOfTheUpc() {
        let value = ProductBarcode.catalogValue(symbology: .ean13, raw: "'080432500170")
        XCTAssertEqual(value, "080432500170")
    }

    func testUpcIsAcceptedOnTheFirstFrame() {
        let now = Date(timeIntervalSince1970: 1_000)
        let decision = ProductBarcode.decide(symbology: .upcA, pendingSince: nil, now: now)
        XCTAssertEqual(decision, .accept)
    }

    func testCode128WaitsForAUpcThenIsAccepted() {
        let start = Date(timeIntervalSince1970: 1_000)
        let tooSoon = ProductBarcode.decide(symbology: .code128, pendingSince: nil, now: start)
        let stillWaiting = ProductBarcode.decide(
            symbology: .code128,
            pendingSince: start,
            now: start.addingTimeInterval(0.2)
        )
        let accepted = ProductBarcode.decide(
            symbology: .code128,
            pendingSince: start,
            now: start.addingTimeInterval(ProductBarcode.nonRetailHold)
        )
        XCTAssertEqual(tooSoon, .wait)
        XCTAssertEqual(stillWaiting, .wait)
        XCTAssertEqual(accepted, .accept)
    }

    func testBlankReadsAreIgnored() {
        let selection = ProductBarcode.preferred(from: [
            .init(symbology: .ean13, value: "   ")
        ])
        XCTAssertNil(selection)
    }
}
