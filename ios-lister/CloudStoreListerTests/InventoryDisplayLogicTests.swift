import XCTest
@testable import CloudStoreLister

final class InventoryDisplayLogicTests: XCTestCase {
    func testStockLabelNotTracked() {
        XCTAssertEqual(
            InventoryDisplayLogic.stockLabel(trackInventory: false, quantityOnHand: 5, inStock: true, lowStock: false),
            "Not tracked"
        )
    }

    func testStockLabelLow() {
        XCTAssertEqual(
            InventoryDisplayLogic.stockLabel(trackInventory: true, quantityOnHand: 2, inStock: true, lowStock: true),
            "2 (low)"
        )
    }

    func testStockLabelOutOfStock() {
        XCTAssertEqual(
            InventoryDisplayLogic.stockLabel(trackInventory: true, quantityOnHand: 0, inStock: false, lowStock: true),
            "Out of stock"
        )
    }

    func testPriceDetailSale() {
        let text = InventoryDisplayLogic.priceDetail(regularPrice: 9.99, onSale: true, salePrice: 7.99)
        XCTAssertTrue(text.contains("7.99"))
        XCTAssertTrue(text.contains("9.99"))
    }
}
