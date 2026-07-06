import XCTest
@testable import CloudStoreLister

final class ListStoreLogicTests: XCTestCase {
    func testBootstrapCreatesMyListWhenEmpty() {
        let lists = ListStoreLogic.bootstrapLists(nil)
        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists[0].name, InventoryListDefaults.myListName)
        XCTAssertTrue(lists[0].isDefault)
        XCTAssertEqual(lists[0].id, InventoryListDefaults.myListId)
    }

    func testDefaultListCannotBeRenamed() {
        let lists = ListStoreLogic.bootstrapLists(nil)
        XCTAssertNil(ListStoreLogic.renameList(id: InventoryListDefaults.myListId, to: "Other", in: lists))
    }

    func testDefaultListDeleteClearsItemsOnly() {
        var lists = ListStoreLogic.bootstrapLists(nil)
        let item = sampleItem(productId: 1)
        lists = ListStoreLogic.addItem(item, toListId: InventoryListDefaults.myListId, in: lists)

        lists = ListStoreLogic.deleteList(id: InventoryListDefaults.myListId, in: lists)

        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists[0].name, InventoryListDefaults.myListName)
        XCTAssertTrue(lists[0].items.isEmpty)
    }

    func testNonDefaultListCanBeDeleted() {
        var lists = ListStoreLogic.bootstrapLists(nil)
        let (updated, newId) = ListStoreLogic.createList(name: "Pull", in: lists)
        lists = updated

        lists = ListStoreLogic.deleteList(id: newId, in: lists)

        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists[0].name, InventoryListDefaults.myListName)
    }

    func testAddItemIncrementsDuplicateProduct() {
        var lists = ListStoreLogic.bootstrapLists(nil)
        lists = ListStoreLogic.addItem(sampleItem(productId: 42), toListId: InventoryListDefaults.myListId, in: lists)
        lists = ListStoreLogic.addItem(sampleItem(productId: 42), toListId: InventoryListDefaults.myListId, in: lists)

        XCTAssertEqual(lists[0].items.count, 1)
        XCTAssertEqual(lists[0].items[0].pullCount, 2)
    }

    func testUniqueListName() {
        var lists = ListStoreLogic.bootstrapLists(nil)
        (lists, _) = ListStoreLogic.createList(name: "Pull", in: lists)
        (lists, _) = ListStoreLogic.createList(name: "Pull", in: lists)

        let names = Set(lists.map(\.name))
        XCTAssertTrue(names.contains("Pull"))
        XCTAssertTrue(names.contains("Pull-2"))
    }

    private func sampleItem(productId: Int) -> InventoryListItem {
        InventoryListItem(
            productId: productId,
            barcode: nil,
            name: "Sample",
            productType: "Retail",
            manufacturer: nil,
            priceLabel: "$9.99",
            stockLabel: "5",
            stockEmphasis: false
        )
    }
}
