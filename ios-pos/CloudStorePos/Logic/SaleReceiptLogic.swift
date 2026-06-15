import Foundation

struct ReceiptLine: Equatable {
    let productId: Int
    let quantity: Int
    let name: String
    let lineTotal: Double
}

struct SaleReceiptInfo: Equatable {
    let orderNumber: String?
    let completedAtMs: Int64
    let customerName: String?
    let lines: [ReceiptLine]
    let itemCount: Int
    let subtotal: Double
    let savings: Double
    let tax: Double
    let grandTotal: Double
    let payments: [CheckoutPayment]
    let changeTotal: Double
    var queuedOffline: Bool = false

    var orderLabel: String {
        if queuedOffline { return "Queued for sync" }
        if let orderNumber, !orderNumber.isEmpty { return orderNumber }
        return "Sale complete"
    }

    func formattedTimestamp() -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(completedAtMs) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy  h:mm a"
        return formatter.string(from: date)
    }
}

enum SaleReceiptLogic {
    static func buildSaleReceipt(
        cart: [CartItem],
        customerName: String?,
        customerLinked: Bool,
        customerDiscount: Bool,
        salesFeeRate: Double,
        taxRate: Double,
        payments: [CheckoutPayment],
        orderNumber: String? = nil,
        queuedOffline: Bool = false,
        completedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) -> SaleReceiptInfo {
        let items = customerLinked
            ? CartTotalsLogic.normalizeCartItems(cart, customerDiscount: customerDiscount)
            : cart
        let totals = CartTotalsLogic.computeCartTotals(items, customerDiscount: customerLinked && customerDiscount)
        let salesFee = totals.itemPreTax * salesFeeRate
        let taxable = totals.itemPreTax + salesFee
        let taxAmount = CartTotalsLogic.roundMoney(taxable * taxRate)
        let grandTotal = CartTotalsLogic.roundMoney(taxable + taxAmount)

        return SaleReceiptInfo(
            orderNumber: orderNumber,
            completedAtMs: completedAtMs,
            customerName: customerName,
            lines: items.map { item in
                ReceiptLine(
                    productId: item.productId,
                    quantity: item.quantity,
                    name: item.name,
                    lineTotal: CartTotalsLogic.roundMoney(item.lineSubtotalPayable)
                )
            },
            itemCount: totals.itemCount,
            subtotal: totals.itemPreTax,
            savings: totals.saleSavings,
            tax: taxAmount,
            grandTotal: grandTotal,
            payments: payments,
            changeTotal: CheckoutPaymentLogic.checkoutChangeTotal(payments),
            queuedOffline: queuedOffline
        )
    }
}
