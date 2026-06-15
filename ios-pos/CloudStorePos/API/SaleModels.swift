import Foundation

struct Product: Codable, Equatable, Identifiable {
    let id: Int
    let barcode: String?
    let name: String
    let regularPrice: Double
    let salePrice: Double?
    let onSale: Bool
    let inStock: Bool
    let quantityOnHand: Int?

    enum CodingKeys: String, CodingKey {
        case id, barcode, name, regularPrice, salePrice, onSale, inStock, quantityOnHand
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        barcode = try c.decodeIfPresent(String.self, forKey: .barcode)
        name = try c.decode(String.self, forKey: .name)
        regularPrice = try c.decode(Double.self, forKey: .regularPrice)
        salePrice = try c.decodeIfPresent(Double.self, forKey: .salePrice)
        onSale = try c.decodeIfPresent(Bool.self, forKey: .onSale) ?? false
        inStock = try c.decodeIfPresent(Bool.self, forKey: .inStock) ?? true
        quantityOnHand = try c.decodeIfPresent(Int.self, forKey: .quantityOnHand)
    }

    var displayPrice: String {
        if onSale, let salePrice {
            return String(format: "$%.2f", salePrice)
        }
        return String(format: "$%.2f", regularPrice)
    }
}

struct StoreCustomer: Codable, Equatable, Identifiable {
    let id: Int
    let name: String
    let email: String?
    let phone: String?
    let memberCode: String?
    let is893: Bool
    let hasCardOnFile: Bool
    let cardLast4: String?

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, memberCode, is893, hasCardOnFile, cardLast4
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        memberCode = try c.decodeIfPresent(String.self, forKey: .memberCode)
        is893 = try c.decodeIfPresent(Bool.self, forKey: .is893) ?? false
        hasCardOnFile = try c.decodeIfPresent(Bool.self, forKey: .hasCardOnFile) ?? false
        cardLast4 = try c.decodeIfPresent(String.self, forKey: .cardLast4)
    }

    init(
        id: Int,
        name: String,
        email: String?,
        phone: String?,
        memberCode: String?,
        is893: Bool,
        hasCardOnFile: Bool,
        cardLast4: String?
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.memberCode = memberCode
        self.is893 = is893
        self.hasCardOnFile = hasCardOnFile
        self.cardLast4 = cardLast4
    }
}

struct CartItem: Codable, Equatable, Identifiable {
    let id: Int
    let productId: Int
    let name: String
    let regularPrice: Double
    let salePrice: Double?
    let onSale: Bool
    let quantity: Int
    let unitPricePublic: Double
    let unitPricePayable: Double
    let lineSubtotalPublic: Double
    let lineSubtotalPayable: Double

    func withPayablePrices(unit: Double, line: Double) -> CartItem {
        CartItem(
            id: id,
            productId: productId,
            name: name,
            regularPrice: regularPrice,
            salePrice: salePrice,
            onSale: onSale,
            quantity: quantity,
            unitPricePublic: unitPricePublic,
            unitPricePayable: unit,
            lineSubtotalPublic: lineSubtotalPublic,
            lineSubtotalPayable: line
        )
    }
}

struct CartResponse: Codable, Equatable {
    let items: [CartItem]
    let subtotalPreMember: Double
    let subtotalPayable: Double
    let memberDiscountPreTax: Double
    let linked893: Bool

    enum CodingKeys: String, CodingKey {
        case items, subtotalPreMember, subtotalPayable, memberDiscountPreTax, linked893
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([CartItem].self, forKey: .items) ?? []
        subtotalPreMember = try c.decodeIfPresent(Double.self, forKey: .subtotalPreMember) ?? 0
        subtotalPayable = try c.decodeIfPresent(Double.self, forKey: .subtotalPayable) ?? 0
        memberDiscountPreTax = try c.decodeIfPresent(Double.self, forKey: .memberDiscountPreTax) ?? 0
        linked893 = try c.decodeIfPresent(Bool.self, forKey: .linked893) ?? false
    }
}

struct CartLineQuantity: Codable, Equatable {
    let productId: Int
    let quantity: Int
}

struct CartReplaceRequest: Encodable {
    let items: [CartLineQuantity]
    let customerId: Int?
}

struct CheckoutPayment: Codable, Equatable {
    let method: String
    let amount: Double
    let tenderedAmount: Double?
    let changeGiven: Double?
}

struct CheckoutRequest: Encodable {
    let paymentMethod: String
    let customerId: Int?
    let payments: [CheckoutPayment]?
    let checkoutTotal: Double?
}

struct CheckoutResponse: Codable, Equatable {
    let ok: Bool
    let orderNumber: String
    let total: Double
    let paymentMethod: String?
    let payments: [CheckoutPayment]?

    enum CodingKeys: String, CodingKey {
        case ok, orderNumber, total, paymentMethod, payments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        orderNumber = try c.decodeIfPresent(String.self, forKey: .orderNumber) ?? ""
        total = try c.decodeIfPresent(Double.self, forKey: .total) ?? 0
        paymentMethod = try c.decodeIfPresent(String.self, forKey: .paymentMethod)
        payments = try c.decodeIfPresent([CheckoutPayment].self, forKey: .payments)
    }
}

