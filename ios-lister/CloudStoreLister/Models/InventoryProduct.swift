import Foundation

struct InventoryProduct: Codable, Equatable, Identifiable {
    let id: Int
    let barcode: String?
    let name: String
    let regularPrice: Double
    let salePrice: Double?
    let onSale: Bool
    let taxExempt: Bool
    let inStock: Bool
    let quantityOnHand: Int?
    let trackInventory: Bool
    let productType: String?
    let manufacturer: String?
    let reorderPoint: Int?
    let lowStock: Bool

    enum CodingKeys: String, CodingKey {
        case id, barcode, name, regularPrice, salePrice, onSale, taxExempt, inStock
        case quantityOnHand, trackInventory, productType, manufacturer, reorderPoint, lowStock
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        barcode = try c.decodeIfPresent(String.self, forKey: .barcode)
        name = try c.decode(String.self, forKey: .name)
        regularPrice = try c.decode(Double.self, forKey: .regularPrice)
        salePrice = try c.decodeIfPresent(Double.self, forKey: .salePrice)
        onSale = try c.decodeIfPresent(Bool.self, forKey: .onSale) ?? false
        taxExempt = try c.decodeIfPresent(Bool.self, forKey: .taxExempt) ?? false
        inStock = try c.decodeIfPresent(Bool.self, forKey: .inStock) ?? true
        quantityOnHand = try c.decodeIfPresent(Int.self, forKey: .quantityOnHand)
        trackInventory = try c.decodeIfPresent(Bool.self, forKey: .trackInventory) ?? false
        productType = try c.decodeIfPresent(String.self, forKey: .productType)
        manufacturer = try c.decodeIfPresent(String.self, forKey: .manufacturer)
        reorderPoint = try c.decodeIfPresent(Int.self, forKey: .reorderPoint)
        lowStock = try c.decodeIfPresent(Bool.self, forKey: .lowStock) ?? false
    }

    var displayPrice: String {
        if onSale, let salePrice {
            return String(format: "$%.2f", salePrice)
        }
        return String(format: "$%.2f", regularPrice)
    }
}

struct InventoryLookupErrorResponse: Decodable {
    let error: String?
}
