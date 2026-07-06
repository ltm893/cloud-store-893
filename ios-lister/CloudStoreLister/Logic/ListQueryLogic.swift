import Foundation

enum ListQueryLogic {
    static func resultListName(sourceName: String, customName: String) -> String {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(sourceName)-BQ" : trimmed
    }

    static func setItems(
        _ items: [InventoryListItem],
        forListId listId: UUID,
        in lists: [InventoryNamedList]
    ) -> [InventoryNamedList] {
        guard let index = lists.firstIndex(where: { $0.id == listId }) else { return lists }
        var updated = lists
        updated[index].items = items
        return updated
    }
}
