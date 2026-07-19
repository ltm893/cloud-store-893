import Foundation

enum ListStoreLogic {
    static func defaultList() -> InventoryNamedList {
        InventoryNamedList(
            id: InventoryListDefaults.myListId,
            name: InventoryListDefaults.myListName,
            items: [],
            isDefault: true
        )
    }

    static func bootstrapLists(_ saved: [InventoryNamedList]?) -> [InventoryNamedList] {
        var lists = saved ?? []
        if lists.isEmpty {
            return [defaultList()]
        }
        if let index = lists.firstIndex(where: { $0.id == InventoryListDefaults.myListId }) {
            lists[index].isDefault = true
            lists[index].name = InventoryListDefaults.myListName
            return lists
        }
        if let index = lists.firstIndex(where: { $0.isDefault || $0.name == InventoryListDefaults.myListName }) {
            let items = lists.remove(at: index).items
            lists.insert(
                InventoryNamedList(
                    id: InventoryListDefaults.myListId,
                    name: InventoryListDefaults.myListName,
                    items: items,
                    isDefault: true
                ),
                at: 0
            )
            return lists
        }
        lists.insert(defaultList(), at: 0)
        return lists
    }

    static func resolveActiveListId(saved: String?, in lists: [InventoryNamedList]) -> UUID {
        if let saved,
           let uuid = UUID(uuidString: saved),
           lists.contains(where: { $0.id == uuid }) {
            return uuid
        }
        return lists.first?.id ?? InventoryListDefaults.myListId
    }

    static func renameList(id: UUID, to name: String, in lists: [InventoryNamedList]) -> [InventoryNamedList]? {
        guard let index = lists.firstIndex(where: { $0.id == id }),
              !lists[index].isDefault else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var updated = lists
        updated[index].name = trimmed
        return updated
    }

    static func deleteList(id: UUID, in lists: [InventoryNamedList]) -> [InventoryNamedList] {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return lists }
        if lists[index].isDefault {
            var updated = lists
            updated[index].items = []
            return updated
        }
        return lists.filter { $0.id != id }
    }

    static func createList(name: String, in lists: [InventoryNamedList]) -> ([InventoryNamedList], UUID) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "New List" : trimmed
        let listName = uniqueListName(base, existing: lists)
        let newList = InventoryNamedList(name: listName, items: [], isDefault: false)
        var updated = lists
        updated.append(newList)
        return (updated, newList.id)
    }

    static func uniqueListName(_ base: String, existing lists: [InventoryNamedList]) -> String {
        let existingNames = Set(lists.map(\.name))
        guard existingNames.contains(base) else { return base }
        var index = 2
        while existingNames.contains("\(base)-\(index)") {
            index += 1
        }
        return "\(base)-\(index)"
    }

    static func addItem(_ item: InventoryListItem, toListId: UUID, in lists: [InventoryNamedList]) -> [InventoryNamedList] {
        guard let listIndex = lists.firstIndex(where: { $0.id == toListId }) else { return lists }
        var updated = lists
        var items = updated[listIndex].items
        if let existingIndex = items.firstIndex(where: { $0.productId == item.productId }) {
            items[existingIndex].pullCount += 1
        } else {
            items.append(item)
        }
        updated[listIndex].items = items
        return updated
    }

    /// Copies `item` into another list (new UUID). If the product already exists there,
    /// pull count is incremented — same rules as `addItem`.
    /// Returns `nil` when the destination is missing or equals the source (active) list.
    static func copyItem(
        _ item: InventoryListItem,
        fromActiveListId activeListId: UUID,
        toListId: UUID,
        in lists: [InventoryNamedList]
    ) -> [InventoryNamedList]? {
        guard toListId != activeListId,
              lists.contains(where: { $0.id == toListId }) else { return nil }
        let clone = InventoryListItem(
            productId: item.productId,
            barcode: item.barcode,
            name: item.name,
            productType: item.productType,
            manufacturer: item.manufacturer,
            priceLabel: item.priceLabel,
            stockLabel: item.stockLabel,
            stockEmphasis: item.stockEmphasis,
            pullCount: item.pullCount
        )
        return addItem(clone, toListId: toListId, in: lists)
    }

    /// Moves `item` from the active list into another list.
    /// Returns `nil` when the transfer is invalid.
    static func moveItem(
        _ item: InventoryListItem,
        fromActiveListId activeListId: UUID,
        toListId: UUID,
        in lists: [InventoryNamedList]
    ) -> [InventoryNamedList]? {
        guard let sourceIndex = lists.firstIndex(where: { $0.id == activeListId }),
              lists[sourceIndex].items.contains(where: { $0.id == item.id }),
              let copied = copyItem(item, fromActiveListId: activeListId, toListId: toListId, in: lists)
        else { return nil }
        var updated = copied
        guard let listIndex = updated.firstIndex(where: { $0.id == activeListId }),
              let itemIndex = updated[listIndex].items.firstIndex(where: { $0.id == item.id })
        else { return nil }
        updated[listIndex].items.remove(at: itemIndex)
        return updated
    }

    static func deleteItems(at offsets: IndexSet, in items: [InventoryListItem]) -> [InventoryListItem] {
        var updated = items
        updated.remove(atOffsets: offsets)
        return updated
    }

    static func incrementPullCount(for itemId: UUID, in items: [InventoryListItem]) -> [InventoryListItem] {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return items }
        var updated = items
        updated[index].pullCount += 1
        return updated
    }

    static func decrementPullCount(for itemId: UUID, in items: [InventoryListItem]) -> [InventoryListItem] {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return items }
        var updated = items
        updated[index].pullCount -= 1
        if updated[index].pullCount <= 0 {
            updated.remove(at: index)
        }
        return updated
    }

    /// Merges selected lists into a new list (dedupe by productId, sum pull counts).
    static func unionLists(
        ids: [UUID],
        into newName: String,
        in lists: [InventoryNamedList]
    ) -> ([InventoryNamedList], UUID)? {
        guard ids.count >= 2 else { return nil }

        var merged: [Int: InventoryListItem] = [:]
        for id in ids {
            guard let list = lists.first(where: { $0.id == id }) else { continue }
            for item in list.items {
                if var existing = merged[item.productId] {
                    existing.pullCount += item.pullCount
                    merged[item.productId] = existing
                } else {
                    merged[item.productId] = item
                }
            }
        }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Union List" : trimmed
        let listName = uniqueListName(base, existing: lists)
        let newList = InventoryNamedList(
            name: listName,
            items: Array(merged.values),
            isDefault: false
        )
        var updated = lists
        updated.append(newList)
        return (updated, newList.id)
    }

    static func diffLists(aId: UUID, bId: UUID, in lists: [InventoryNamedList]) -> ListDiffResult? {
        guard let listA = lists.first(where: { $0.id == aId }),
              let listB = lists.first(where: { $0.id == bId }) else { return nil }
        let idsA = Set(listA.items.map(\.productId))
        let idsB = Set(listB.items.map(\.productId))
        let common = listA.items.filter { idsB.contains($0.productId) }
        let onlyInA = listA.items.filter { !idsB.contains($0.productId) }
        let onlyInB = listB.items.filter { !idsA.contains($0.productId) }
        return ListDiffResult(
            listAName: listA.name,
            listBName: listB.name,
            common: common,
            onlyInA: onlyInA,
            onlyInB: onlyInB
        )
    }

    enum SplitMode: Equatable {
        case byNumberOfLists(Int)
        case byItemsPerList(Int)
    }

    /// Splits a list into multiple sublists appended to the collection.
    static func splitList(
        id: UUID,
        mode: SplitMode,
        prefix: String,
        in lists: [InventoryNamedList]
    ) -> ([InventoryNamedList], UUID)? {
        guard let source = lists.first(where: { $0.id == id }),
              !source.items.isEmpty else { return nil }

        let items = source.items
        let count = items.count

        let chunkSize: Int
        switch mode {
        case .byNumberOfLists(let n):
            chunkSize = Int(ceil(Double(count) / Double(max(1, n))))
        case .byItemsPerList(let n):
            chunkSize = max(1, n)
        }

        let cleanPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? source.name
            : prefix.trimmingCharacters(in: .whitespacesAndNewlines)

        var updated = lists
        var partIndex = 1
        var offset = 0
        var lastId: UUID?

        while offset < count {
            let slice = Array(items[offset ..< min(offset + chunkSize, count)])
            let rawName = "\(cleanPrefix)-\(partIndex)"
            let listName = uniqueListName(rawName, existing: updated)
            let newList = InventoryNamedList(name: listName, items: slice, isDefault: false)
            updated.append(newList)
            lastId = newList.id
            offset += chunkSize
            partIndex += 1
        }

        guard let lastId else { return nil }
        return (updated, lastId)
    }
}
