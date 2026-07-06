import Foundation

enum ListSortField: String, CaseIterable, Identifiable {
    case name = "Name"
    case productType = "Type"
    case productId = "Product ID"
    case barcode = "Barcode"
    case price = "Price"
    case stock = "Stock"
    case pullCount = "Pull Count"

    var id: String { rawValue }
}

enum ListSortLogic {
    static func sorted(
        _ items: [InventoryListItem],
        by field: ListSortField,
        ascending: Bool
    ) -> [InventoryListItem] {
        items.sorted { lhs, rhs in
            let ordered = compare(lhs, rhs, by: field)
            if ordered == .orderedSame {
                return lhs.productId < rhs.productId
            }
            return ascending ? ordered == .orderedAscending : ordered == .orderedDescending
        }
    }

    static func sortList(
        id: UUID,
        by field: ListSortField,
        ascending: Bool,
        in lists: [InventoryNamedList]
    ) -> [InventoryNamedList]? {
        guard let index = lists.firstIndex(where: { $0.id == id }),
              !lists[index].items.isEmpty else { return nil }
        var updated = lists
        updated[index].items = sorted(updated[index].items, by: field, ascending: ascending)
        return updated
    }

    private static func compare(
        _ lhs: InventoryListItem,
        _ rhs: InventoryListItem,
        by field: ListSortField
    ) -> ComparisonResult {
        switch field {
        case .name:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        case .productType:
            return (lhs.productType ?? "").localizedCaseInsensitiveCompare(rhs.productType ?? "")
        case .productId:
            return numericCompare(lhs.productId, rhs.productId)
        case .barcode:
            return (lhs.barcode ?? "").localizedCaseInsensitiveCompare(rhs.barcode ?? "")
        case .price:
            return lhs.priceLabel.localizedCaseInsensitiveCompare(rhs.priceLabel)
        case .stock:
            return lhs.stockLabel.localizedCaseInsensitiveCompare(rhs.stockLabel)
        case .pullCount:
            return numericCompare(lhs.pullCount, rhs.pullCount)
        }
    }

    private static func numericCompare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }
}
