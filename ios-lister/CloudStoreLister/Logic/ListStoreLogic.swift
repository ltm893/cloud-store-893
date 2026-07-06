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
}
