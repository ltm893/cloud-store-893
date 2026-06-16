import Foundation

struct CartTotals: Equatable {
    let itemCount: Int
    let shelfSubtotal: Double
    let itemPreTax: Double
    let memberDiscount: Double
    let saleSavings: Double
    let linked893: Bool

    var showDiscount: Bool { linked893 && memberDiscount > 0.005 }
}

enum CartTotalsLogic {
    private static let moneyEpsilon = 0.005

    static func roundMoney(_ amount: Double) -> Double {
        (amount * 100).rounded() / 100
    }

    static func formatMoney(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }

    static func roundToNickel(_ amount: Double) -> Double {
        roundMoney(floor(amount * 20) / 20)
    }

    static func cashQuickDenominations(amountDue: Double, cashEnabled: Bool = true) -> [Int] {
        if !cashEnabled || amountDue <= moneyEpsilon { return [] }
        let bills = [5, 10, 20, 50, 100]
        let start = bills.firstIndex { Double($0) >= amountDue - 0.001 } ?? bills.count
        if start >= bills.count { return [100] }
        return Array(bills.dropFirst(start).prefix(3))
    }

    static func normalizeCartItems(_ items: [CartItem], customerDiscount: Bool) -> [CartItem] {
        if customerDiscount { return items }
        return items.map { item in
            if abs(item.lineSubtotalPayable - item.lineSubtotalPublic) <= moneyEpsilon {
                return item
            }
            return item.withPayablePrices(unit: item.unitPricePublic, line: item.lineSubtotalPublic)
        }
    }

    static func computeSaleSavings(_ cart: [CartItem]) -> Double {
        let raw = cart
            .filter { $0.onSale && $0.salePrice != nil }
            .reduce(0.0) { sum, item in
                sum + roundMoney(item.regularPrice) * Double(item.quantity) - item.lineSubtotalPublic
            }
        return roundMoney(max(0, raw))
    }

    static func computeCartTotals(_ cart: [CartItem], customerDiscount: Bool) -> CartTotals {
        let shelf = cart.reduce(0.0) { $0 + $1.lineSubtotalPublic }
        let preTax = customerDiscount
            ? cart.reduce(0.0) { $0 + $1.lineSubtotalPayable }
            : shelf
        let discount = customerDiscount ? roundMoney(shelf - preTax) : 0
        return CartTotals(
            itemCount: cart.reduce(0) { $0 + $1.quantity },
            shelfSubtotal: roundMoney(shelf),
            itemPreTax: roundMoney(preTax),
            memberDiscount: discount,
            saleSavings: computeSaleSavings(cart),
            linked893: customerDiscount
        )
    }

    static func computeSaleGrandTotal(
        cart: [CartItem],
        customerLinked: Bool = false,
        customerDiscount: Bool = false,
        salesFeeRate: Double,
        taxRate: Double
    ) -> Double {
        let items = customerLinked ? normalizeCartItems(cart, customerDiscount: customerDiscount) : cart
        let totals = computeCartTotals(items, customerDiscount: customerLinked && customerDiscount)
        let salesFee = totals.itemPreTax * salesFeeRate
        let taxable = totals.itemPreTax + salesFee
        let taxAmt = taxable * taxRate
        return roundMoney(taxable + taxAmt)
    }

    static func computeCashAmountDue(
        cart: [CartItem],
        customerLinked: Bool = false,
        customerDiscount: Bool = false,
        salesFeeRate: Double,
        taxRate: Double
    ) -> Double {
        roundToNickel(
            computeSaleGrandTotal(
                cart: cart,
                customerLinked: customerLinked,
                customerDiscount: customerDiscount,
                salesFeeRate: salesFeeRate,
                taxRate: taxRate
            )
        )
    }

    static func collectedTotal(_ registerTotal: Double) -> Double {
        roundToNickel(registerTotal)
    }

    static func remainingCashAmountDue(registerTotal: Double, nonCashPaid: Double) -> Double {
        let collected = collectedTotal(registerTotal)
        return roundToNickel(roundMoney(max(0, collected - nonCashPaid)))
    }
}
