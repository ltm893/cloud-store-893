import Foundation

enum ListSearchLogic {
    /// Case-insensitive substring match across all searchable `InventoryListItem` fields.
    /// Empty / whitespace-only query returns `items` unchanged.
    static func filtered(_ items: [InventoryListItem], query: String) -> [InventoryListItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { matches($0, query: trimmed) }
    }

    static func matches(_ item: InventoryListItem, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return searchableValues(for: item).contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    private static func searchableValues(for item: InventoryListItem) -> [String] {
        [
            item.name,
            item.productType,
            item.manufacturer,
            item.barcode,
            String(item.productId),
            item.priceLabel,
            item.stockLabel,
            String(item.pullCount),
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
    }
}
