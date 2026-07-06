import XCTest
@testable import CloudStoreLister

final class ListSortLogicTests: XCTestCase {
    private func item(
        productId: Int,
        name: String = "Item",
        productType: String? = nil,
        barcode: String? = nil,
        priceLabel: String = "$9.99",
        stockLabel: String = "5 in stock",
        pullCount: Int = 1
    ) -> InventoryListItem {
        InventoryListItem(
            productId: productId,
            barcode: barcode,
            name: name,
            productType: productType,
            manufacturer: nil,
            priceLabel: priceLabel,
            stockLabel: stockLabel,
            stockEmphasis: false,
            pullCount: pullCount
        )
    }

    func testSortByNameAscending() {
        let items = [
            item(productId: 3, name: "Zebra"),
            item(productId: 1, name: "Alpha"),
            item(productId: 2, name: "Mango"),
        ]
        let sorted = ListSortLogic.sorted(items, by: .name, ascending: true)
        XCTAssertEqual(sorted.map(\.name), ["Alpha", "Mango", "Zebra"])
    }

    func testSortByNameDescending() {
        let items = [
            item(productId: 1, name: "Alpha"),
            item(productId: 2, name: "Mango"),
        ]
        let sorted = ListSortLogic.sorted(items, by: .name, ascending: false)
        XCTAssertEqual(sorted.map(\.name), ["Mango", "Alpha"])
    }

    func testSortByProductId() {
        let items = [
            item(productId: 42, name: "B"),
            item(productId: 7, name: "A"),
        ]
        let sorted = ListSortLogic.sorted(items, by: .productId, ascending: true)
        XCTAssertEqual(sorted.map(\.productId), [7, 42])
    }

    func testSortByPullCount() {
        let items = [
            item(productId: 1, pullCount: 5),
            item(productId: 2, pullCount: 1),
            item(productId: 3, pullCount: 3),
        ]
        let sorted = ListSortLogic.sorted(items, by: .pullCount, ascending: true)
        XCTAssertEqual(sorted.map(\.pullCount), [1, 3, 5])
    }

    func testSortListUpdatesSelectedListInPlace() {
        var lists = ListStoreLogic.bootstrapLists(nil)
        lists = ListStoreLogic.addItem(item(productId: 2, name: "B"), toListId: InventoryListDefaults.myListId, in: lists)
        lists = ListStoreLogic.addItem(item(productId: 1, name: "A"), toListId: InventoryListDefaults.myListId, in: lists)

        let updated = ListSortLogic.sortList(
            id: InventoryListDefaults.myListId,
            by: .name,
            ascending: true,
            in: lists
        )!

        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].items.map(\.name), ["A", "B"])
    }

    func testSortListReturnsNilForEmptyList() {
        let lists = ListStoreLogic.bootstrapLists(nil)
        XCTAssertNil(
            ListSortLogic.sortList(id: InventoryListDefaults.myListId, by: .name, ascending: true, in: lists)
        )
    }
}
