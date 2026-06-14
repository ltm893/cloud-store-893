import Foundation

enum CheckoutPaymentLogic {
    static func paymentMethodLabel(_ method: String) -> String {
        switch method {
        case "card": return "Card"
        case "cash": return "Cash"
        case "split": return "Split"
        default: return method
        }
    }

    static func checkoutFinalizeMethod(_ payments: [CheckoutPayment]) -> String {
        payments.count == 1 ? payments[0].method : "split"
    }

    static func checkoutChangeTotal(_ payments: [CheckoutPayment]) -> Double {
        CartTotalsLogic.roundMoney(payments.reduce(0) { $0 + ($1.changeGiven ?? 0) })
    }

    static func buildCheckoutPaymentLine(
        method: String,
        enteredAmount: Double,
        balanceDue: Double
    ) -> CheckoutPayment? {
        if enteredAmount <= 0 || balanceDue <= 0.005 { return nil }
        if method == "card" && enteredAmount > balanceDue + 0.005 { return nil }

        let appliedAmount = CartTotalsLogic.roundMoney(
            method == "cash" ? min(enteredAmount, balanceDue) : enteredAmount
        )
        if appliedAmount <= 0 { return nil }

        let changeGiven: Double? = {
            guard method == "cash" else { return nil }
            let change = CartTotalsLogic.roundMoney(max(0, enteredAmount - balanceDue))
            return change > 0.005 ? change : nil
        }()

        return CheckoutPayment(
            method: method,
            amount: appliedAmount,
            tenderedAmount: enteredAmount,
            changeGiven: changeGiven
        )
    }
}

enum CashEntryLogic {
    static func parseCashTendered(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." { return nil }
        return Double(trimmed)
    }

    static func appendCashDigit(current: String, digit: Character) -> String {
        if digit == "." {
            if current.contains(".") { return current }
            return current.isEmpty ? "0." : current + "."
        }
        if current.contains(".") {
            let frac = current.split(separator: ".", maxSplits: 1).last ?? ""
            if frac.count >= 2 { return current }
        } else if current.count >= 7 {
            return current
        }
        return current + String(digit)
    }

    static func appendCashDigitLimited(current: String, digit: Character, maxAmount: Double?) -> String {
        let next = appendCashDigit(current: current, digit: digit)
        guard let maxAmount, maxAmount > 0.005 else { return next }
        guard let parsed = parseCashTendered(next) else { return next }
        if parsed > maxAmount + 0.005 { return current }
        return next
    }

    static func appendScanDigit(current: String, digit: Character) -> String {
        if current.count >= 20 { return current }
        return current + String(digit)
    }
}
