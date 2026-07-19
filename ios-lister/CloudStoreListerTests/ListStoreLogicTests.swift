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

    func testUnionMergesDisjointLists() {
        var lists = ListStoreLogic.bootstrapLists(nil)
        var listA: UUID
        var listB: UUID
        (lists, listA) = ListStoreLogic.createList(name: "A", in: lists)
        (lists, listB) = ListStoreLogic.createList(name: "B", in: lists)
        lists = ListStoreLogic.addItem(sampleItem(productId: 1, name: "One"), toListId: listA, in: lists)
        lists = ListStoreLogic.addItem(sampleItem(productId: 2, name: "Two"), toListId: listB, in: lists)

        let (updated, newId) = ListStoreLogic.unionLists(ids: [listA, listB], into: "Combined", in: lists)!
        let union = updated.first { $0.id == newId }!

        XCTAssertEqual(union.name, "Combined")
        XCTAssertEqual(union.items.count, 2)
        XCTAssertEqual(Set(union.items.map(\.productId)), Set([1, 2]))
    }

    func testUnionSumsPullCountsForDuplicates() {
        var lists = ListStoreLogic.bootstrapLists(nil)
        var listA: UUID
        var listB: UUID
        (lists, listA) = ListStoreLogic.createList(name: "A", in: lists)
        (lists, listB) = ListStoreLogic.createList(name: "B", in: lists)
        var itemA = sampleItem(productId: 42, name: "Shared")
        itemA.pullCount = 2
        var itemB = sampleItem(productId: 42, name: "Shared")
        itemB.pullCount = 3
        lists = ListStoreLogic.addItem(itemA, toListId: listA, in: lists)
        lists = ListStoreLogic.addItem(itemB, toListId: listB, in: lists)

        let (updated, newId) = ListStoreLogic.unionLists(ids: [listA, listB], into: "Union", in: lists)!
        let union = updated.first { $0.id == newId }!

        XCTAssertEqual(union.items.count, 1)
        XCTAssertEqual(union.items[0].pullCount, 5)
    }

    func testUnionRequiresAtLeastTwoLists() {
        let lists = ListStoreLogic.bootstrapLists(nil)
        XCTAssertNil(ListStoreLogic.unionLists(ids: [InventoryListDefaults.myListId], into: "X", in: lists))
    }

    func testDiffPartitionsListsByProductId() {
        var lists = ListStoreLogic.bootstrapLists(nil)
        var listA: UUID
        var listB: UUID
        (lists, listA) = ListStoreLogic.createList(name: "A", in: lists)
        (lists, listB) = ListStoreLogic.createList(name: "B", in: lists)
        lists = ListStoreLogic.addItem(sampleItem(productId: 1, name: "Shared"), toListId: listA, in: lists)
        lists = ListStoreLogic.addItem(sampleItem(productId: 2, name: "Only A"), toListId: listA, in: lists)
        lists = ListStoreLogic.addItem(sampleItem(productId: 1, name: "Shared"), toListId: listB, in: lists)
        lists = ListStoreLogic.addItem(sampleItem(productId: 3, name: "Only B"), toListId: listB, in: lists)

        let result = ListStoreLogic.diffLists(aId: listA, bId: listB, in: lists)!

        XCTAssertEqual(result.listAName, "A")
        XCTAssertEqual(result.listBName, "B")
        XCTAssertEqual(result.common.map(\.productId), [1])
        XCTAssertEqual(Set(result.onlyInA.map(\.productId)), Set([2]))
        XCTAssertEqual(Set(result.onlyInB.map(\.productId)), Set([3]))
    }

    func testDiffReturnsNilForMissingList() {
        let lists = ListStoreLogic.bootstrapLists(nil)
        XCTAssertNil(ListStoreLogic.diffLists(aId: UUID(), bId: UUID(), in: lists))
    }

    func testSplitIntoNumberOfLists() {
        var lists = ListStoreLogic.bootstrapLists(nil)
        for productId in 1...7 {
            lists = ListStoreLogic.addItem(
                sampleItem(productId: productId, name: "Item \(productId)"),
                toListId: InventoryListDefaults.myListId,
                in: lists
            )
        }

        let (updated, lastId) = ListStoreLogic.splitList(
            id: InventoryListDefaults.myListId,
            mode: .byNumberOfLists(3),
            prefix: "Pull",
            in: lists
        )!

        let newLists = updated.filter { $0.name.hasPrefix("Pull-") }
        XCTAssertEqual(newLists.count, 3)
        XCTAssertEqual(newLists.map(\.items.count), [3, 3, 1])
        XCTAssertEqual(updated.first { $0.id == lastId }?.name, "Pull-3")
    }

    func testSplitByItemsPerList() {
        var lists = ListStoreLogic.bootstrapLists(nil)
        for productId in 1...5 {
            lists = ListStoreLogic.addItem(
                sampleItem(productId: productId),
                toListId: InventoryListDefaults.myListId,
                in: lists
            )
        }

        let (updated, _) = ListStoreLogic.splitList(
            id: InventoryListDefaults.myListId,
            mode: .byItemsPerList(2),
            prefix: "",
            in: lists
        )!

        let newLists = updated.filter { $0.name.hasPrefix("\(InventoryListDefaults.myListName)-") }
        XCTAssertEqual(newLists.count, 3)
        XCTAssertEqual(newLists.map(\.items.count), [2, 2, 1])
    }

    func testCopyItemKeepsSourceAndClonesToTarget() {
        var lists = ListStoreLogic.bootstrapLists(nil)
        var targetId: UUID
        (lists, targetId) = ListStoreLogic.createList(name: "Target", in: lists)
        let source = sampleItem(productId: 1, name: "Widget", pullCount: 2)
        lists = ListStoreLogic.addItem(source, toListId: InventoryListDefaults.myListId, in: lists)
        let stored = lists.first { $0.id == InventoryListDefaults.myListId }!.items.first!

        let updated = ListStoreLogic.copyItem(
            stored,
            fromActiveListId: InventoryListDefaults.myListId,
            toListId: targetId,
            in: lists
        )!

        let sourceList = updated.first { $0.id == InventoryListDefaults.myListId }!
        let targetList = updated.first { $0.id == targetId }!
        XCTAssertEqual(sourceList.items.count, 1)
        XCTAssertEqual(targetList.items.count, 1)
        XCTAssertEqual(targetList.items[0].productId, 1)
        XCTAssertNotEqual(targetList.items[0].id, stored.id)
        XCTAssertEqual(targetList.items[0].pullCount, 2)
    }

    func testCopyItemIncrementsPullWhenProductExistsOnTarget() {
        var lists = ListStoreLogic.bootstrapLists(nil)
        var targetId: UUID
        (lists, targetId) = ListStoreLogic.createList(name: "Target", in: lists)
        lists = ListStoreLogic.addItem(sampleItem(productId: 1, pullCount: 1), toListId: InventoryListDefaults.myListId, in: lists)
        lists = ListStoreLogic.addItem(sampleItem(productId: 1, pullCount: 3), toListId: targetId, in: lists)
        let stored = lists.first { $0.id == InventoryListDefaults.myListId }!.items.first!

        let updated = ListStoreLogic.copyItem(
            stored,
            fromActiveListId: InventoryListDefaults.myListId,
            toListId: targetId,
            in: lists
        )!

        let targetList = updated.first { $0.id == targetId }!
        XCTAssertEqual(targetList.items.count, 1)
        XCTAssertEqual(targetList.items[0].pullCount, 4)
    }

    func testCopyItemFailsWhenDestinationIsActiveList() {
        var lists = ListStoreLogic.bootstrapLists(nil)
        lists = ListStoreLogic.addItem(sampleItem(productId: 1), toListId: InventoryListDefaults.myListId, in: lists)
        let stored = lists[0].items.first!

        XCTAssertNil(
            ListStoreLogic.copyItem(
                stored,
                fromActiveListId: InventoryListDefaults.myListId,
                toListId: InventoryListDefaults.myListId,
                in: lists
            )
        )
    }

    func testMoveItemRemovesFromSource() {
        var lists = ListStoreLogic.bootstrapLists(nil)
        var targetId: UUID
        (lists, targetId) = ListStoreLogic.createList(name: "Target", in: lists)
        lists = ListStoreLogic.addItem(sampleItem(productId: 1, name: "Widget"), toListId: InventoryListDefaults.myListId, in: lists)
        let stored = lists.first { $0.id == InventoryListDefaults.myListId }!.items.first!

        let updated = ListStoreLogic.moveItem(
            stored,
            fromActiveListId: InventoryListDefaults.myListId,
            toListId: targetId,
            in: lists
        )!

        let sourceList = updated.first { $0.id == InventoryListDefaults.myListId }!
        let targetList = updated.first { $0.id == targetId }!
        XCTAssertTrue(sourceList.items.isEmpty)
        XCTAssertEqual(targetList.items.count, 1)
        XCTAssertEqual(targetList.items[0].productId, 1)
    }

    func testMoveItemFailsForUnknownDestination() {
        var lists = ListStoreLogic.bootstrapLists(nil)
        lists = ListStoreLogic.addItem(sampleItem(productId: 1), toListId: InventoryListDefaults.myListId, in: lists)
        let stored = lists[0].items.first!

        XCTAssertNil(
            ListStoreLogic.moveItem(
                stored,
                fromActiveListId: InventoryListDefaults.myListId,
                toListId: UUID(),
                in: lists
            )
        )
    }

    private func sampleItem(productId: Int, name: String = "Sample", pullCount: Int = 1) -> InventoryListItem {
        InventoryListItem(
            productId: productId,
            barcode: nil,
            name: name,
            productType: "Retail",
            manufacturer: nil,
            priceLabel: "$9.99",
            stockLabel: "5",
            stockEmphasis: false,
            pullCount: pullCount
        )
    }
}
