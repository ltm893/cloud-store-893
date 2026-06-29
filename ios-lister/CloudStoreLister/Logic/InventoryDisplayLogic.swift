import Foundation

enum InventoryDisplayLogic {
    static func stockLabel(
        trackInventory: Bool,
        quantityOnHand: Int?,
        inStock: Bool,
        lowStock: Bool
    ) -> String {
        guard trackInventory else { return "Not tracked" }
        guard let quantityOnHand else { return "—" }
        if !inStock { return "Out of stock" }
        if lowStock { return "\(quantityOnHand) (low)" }
        return "\(quantityOnHand)"
    }

    static func priceDetail(regularPrice: Double, onSale: Bool, salePrice: Double?) -> String {
        if onSale, let salePrice {
            return String(format: "Sale $%.2f (was $%.2f)", salePrice, regularPrice)
        }
        return String(format: "$%.2f", regularPrice)
    }
}
