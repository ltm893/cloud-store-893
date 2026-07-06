import Foundation

struct InventoryListItem: Identifiable, Codable, Equatable {
    let id: UUID
    let productId: Int
    let barcode: String?
    let name: String
    let productType: String?
    let manufacturer: String?
    let priceLabel: String
    let stockLabel: String
    let stockEmphasis: Bool
    var pullCount: Int

    init(
        id: UUID = UUID(),
        productId: Int,
        barcode: String?,
        name: String,
        productType: String?,
        manufacturer: String?,
        priceLabel: String,
        stockLabel: String,
        stockEmphasis: Bool,
        pullCount: Int = 1
    ) {
        self.id = id
        self.productId = productId
        self.barcode = barcode
        self.name = name
        self.productType = productType
        self.manufacturer = manufacturer
        self.priceLabel = priceLabel
        self.stockLabel = stockLabel
        self.stockEmphasis = stockEmphasis
        self.pullCount = pullCount
    }

    init(product: InventoryProduct) {
        self.init(
            productId: product.id,
            barcode: product.barcode,
            name: product.name,
            productType: product.productType,
            manufacturer: product.manufacturer,
            priceLabel: InventoryDisplayLogic.priceDetail(
                regularPrice: product.regularPrice,
                onSale: product.onSale,
                salePrice: product.salePrice
            ),
            stockLabel: InventoryDisplayLogic.stockLabel(
                trackInventory: product.trackInventory,
                quantityOnHand: product.quantityOnHand,
                inStock: product.inStock,
                lowStock: product.lowStock
            ),
            stockEmphasis: product.lowStock || !product.inStock
        )
    }
}

struct InventoryNamedList: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var items: [InventoryListItem]
    var isDefault: Bool

    init(id: UUID = UUID(), name: String, items: [InventoryListItem] = [], isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.items = items
        self.isDefault = isDefault
    }
}

enum InventoryListDefaults {
    static let myListId = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
    static let myListName = "MyList"
}
