import XCTest
@testable import CloudStoreLister

final class ListSearchLogicTests: XCTestCase {
    private func item(
        productId: Int = 100,
        barcode: String? = "012345678905",
        name: String = "Widget",
        productType: String? = "General",
        manufacturer: String? = "Acme",
        priceLabel: String = "$9.99",
        stockLabel: String = "5 in stock",
        pullCount: Int = 2
    ) -> InventoryListItem {
        InventoryListItem(
            productId: productId,
            barcode: barcode,
            name: name,
            productType: productType,
            manufacturer: manufacturer,
            priceLabel: priceLabel,
            stockLabel: stockLabel,
            stockEmphasis: false,
            pullCount: pullCount
        )
    }

    func testEmptyQueryReturnsAll() {
        let items = [item(name: "A"), item(name: "B")]
        XCTAssertEqual(ListSearchLogic.filtered(items, query: "").map(\.name), ["A", "B"])
        XCTAssertEqual(ListSearchLogic.filtered(items, query: "   ").map(\.name), ["A", "B"])
    }

    func testMatchesNameCaseInsensitive() {
        let items = [item(name: "Blue Widget"), item(name: "Red Gadget")]
        XCTAssertEqual(ListSearchLogic.filtered(items, query: "widget").map(\.name), ["Blue Widget"])
    }

    func testMatchesProductIdBarcodeManufacturerTypePriceStockPull() {
        let target = item(
            productId: 4242,
            barcode: "998877",
            name: "Keep",
            productType: "Beverage",
            manufacturer: "Northstar",
            priceLabel: "$12.50",
            stockLabel: "Out of stock",
            pullCount: 7
        )
        let other = item(productId: 1, barcode: "000", name: "Other", productType: "X", manufacturer: "Y")

        XCTAssertEqual(ListSearchLogic.filtered([target, other], query: "4242").map(\.name), ["Keep"])
        XCTAssertEqual(ListSearchLogic.filtered([target, other], query: "998877").map(\.name), ["Keep"])
        XCTAssertEqual(ListSearchLogic.filtered([target, other], query: "north").map(\.name), ["Keep"])
        XCTAssertEqual(ListSearchLogic.filtered([target, other], query: "bever").map(\.name), ["Keep"])
        XCTAssertEqual(ListSearchLogic.filtered([target, other], query: "12.50").map(\.name), ["Keep"])
        XCTAssertEqual(ListSearchLogic.filtered([target, other], query: "out of").map(\.name), ["Keep"])
        XCTAssertEqual(ListSearchLogic.filtered([target, other], query: "7").map(\.name), ["Keep"])
    }

    func testNoMatchesReturnsEmpty() {
        let items = [item(name: "Only")]
        XCTAssertTrue(ListSearchLogic.filtered(items, query: "zzz").isEmpty)
    }
}
