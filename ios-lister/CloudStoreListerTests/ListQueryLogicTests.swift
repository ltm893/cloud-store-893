import XCTest
@testable import CloudStoreLister

final class ListQueryLogicTests: XCTestCase {
    func testResultListNameDefaultSuffix() {
        XCTAssertEqual(
            ListQueryLogic.resultListName(sourceName: "Walk", customName: ""),
            "Walk-BQ"
        )
    }

    func testResultListNameUsesCustomName() {
        XCTAssertEqual(
            ListQueryLogic.resultListName(sourceName: "Walk", customName: "  Fresh Pull  "),
            "Fresh Pull"
        )
    }

    func testRefreshedItemPreservesPullCount() throws {
        let product = try sampleProduct(id: 99, name: "Updated", qty: 12)
        let source = InventoryListItem(
            productId: 99,
            barcode: nil,
            name: "Old",
            productType: "Retail",
            manufacturer: nil,
            priceLabel: "$1.00",
            stockLabel: "1",
            stockEmphasis: false,
            pullCount: 4
        )

        let refreshed = source.refreshed(from: product)

        XCTAssertEqual(refreshed.pullCount, 4)
        XCTAssertEqual(refreshed.name, "Updated")
        XCTAssertEqual(refreshed.stockLabel, "12")
    }

    func testLookupFailureKeepsIdentityAndPullCount() {
        let source = InventoryListItem(
            productId: 7,
            barcode: "123",
            name: "Widget",
            productType: nil,
            manufacturer: nil,
            priceLabel: "$5.00",
            stockLabel: "3",
            stockEmphasis: false,
            pullCount: 2
        )

        let failed = source.withLookupFailure("Not found")

        XCTAssertEqual(failed.id, source.id)
        XCTAssertEqual(failed.productId, 7)
        XCTAssertEqual(failed.pullCount, 2)
        XCTAssertEqual(failed.stockLabel, "Not found")
        XCTAssertTrue(failed.stockEmphasis)
    }

    private func sampleProduct(id: Int, name: String, qty: Int) throws -> InventoryProduct {
        let json = """
        {"id":\(id),"name":"\(name)","regularPrice":9.99,"onSale":false,"trackInventory":true,"quantityOnHand":\(qty),"inStock":true,"lowStock":false}
        """
        return try JSONDecoder().decode(InventoryProduct.self, from: Data(json.utf8))
    }
}
