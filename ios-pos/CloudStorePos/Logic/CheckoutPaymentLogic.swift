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

    static func exactBalanceDue(registerTotal: Double, payments: [CheckoutPayment]) -> Double {
        let paid = CartTotalsLogic.roundMoney(payments.reduce(0) { $0 + $1.amount })
        return CartTotalsLogic.roundMoney(
            max(0, CartTotalsLogic.collectedTotal(registerTotal) - paid)
        )
    }

    static func cashBalanceDue(registerTotal: Double, payments: [CheckoutPayment]) -> Double {
        let cardPaid = CartTotalsLogic.roundMoney(
            payments.filter { $0.method == "card" }.reduce(0) { $0 + $1.amount }
        )
        let cashPaid = CartTotalsLogic.roundMoney(
            payments.filter { $0.method == "cash" }.reduce(0) { $0 + $1.amount }
        )
        let cashDue = CartTotalsLogic.remainingCashAmountDue(registerTotal: registerTotal, nonCashPaid: cardPaid)
        return CartTotalsLogic.roundMoney(max(cashDue - cashPaid, 0.0))
    }

    static func balanceDueForMethod(
        registerTotal: Double,
        payments: [CheckoutPayment],
        method: String
    ) -> Double {
        CartTotalsLogic.roundToNickel(
            exactBalanceDue(registerTotal: registerTotal, payments: payments)
        )
    }

    static func expectedCollectedTotal(registerTotal: Double, payments: [CheckoutPayment]) -> Double {
        CartTotalsLogic.collectedTotal(registerTotal)
    }

    static func isCheckoutComplete(registerTotal: Double, payments: [CheckoutPayment]) -> Bool {
        let paid = CartTotalsLogic.roundMoney(payments.reduce(0) { $0 + $1.amount })
        return paid + 0.005 >= CartTotalsLogic.collectedTotal(registerTotal)
    }
}

enum CashEntryLogic {
    static func formatCashEntry(_ amount: Double) -> String {
        let rounded = CartTotalsLogic.roundMoney(amount)
        if rounded == rounded.rounded(.towardZero) && abs(rounded - rounded.rounded(.towardZero)) < 0.000_001 {
            return String(Int(rounded.rounded(.towardZero)))
        }
        return String(format: "%.2f", rounded)
    }

    static func parseCashTendered(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." || trimmed == "0" { return nil }
        return Double(trimmed)
    }

    /// Strip leading zeros while keeping a single keypad value (not a running total).
    static func normalizeCashEntryInput(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "0" }
        if trimmed == "." { return "0." }
        if trimmed.contains(".") {
            let parts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            let whole = String(parts[0]).trimmingCharacters(in: CharacterSet(charactersIn: "0")).isEmpty
                ? "0"
                : String(parts[0]).trimmingCharacters(in: CharacterSet(charactersIn: "0"))
            let frac = parts.count > 1 ? String(parts[1]) : ""
            return frac.isEmpty ? "\(whole)." : "\(whole).\(frac)"
        }
        let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
        return stripped.isEmpty ? "0" : stripped
    }

    static func displayCashEntry(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." { return "—" }
        return "$\(normalizeCashEntryInput(trimmed))"
    }

    static func appendCashDigit(current: String, digit: Character) -> String {
        let base = normalizeCashEntryInput(current.isEmpty ? "0" : current)
        if digit == "." {
            if base.contains(".") { return base }
            return base == "0" ? "0." : "\(base)."
        }
        if base.contains(".") {
            let frac = base.split(separator: ".", maxSplits: 1).last.map(String.init) ?? ""
            if frac.count >= 2 { return base }
            return normalizeCashEntryInput("\(base)\(digit)")
        }
        if base == "0" {
            return digit == "0" ? "0" : String(digit)
        }
        if base.count >= 7 { return base }
        return normalizeCashEntryInput(base + String(digit))
    }

    static func backspaceCashEntry(_ current: String) -> String {
        let base = current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "0" : current
        if base.count <= 1 { return "0" }
        return normalizeCashEntryInput(String(base.dropLast()))
    }

    static func appendCashDigitLimited(current: String, digit: Character, maxAmount: Double?) -> String {
        let next = appendCashDigit(current: current, digit: digit)
        guard let maxAmount, maxAmount > 0.005 else { return next }
        guard let parsed = parseCashTendered(next) else { return next }
        if parsed > maxAmount + 0.005 {
            return normalizeCashEntryInput(current.isEmpty ? "0" : current)
        }
        return next
    }

    static func appendScanDigit(current: String, digit: Character) -> String {
        if current.count >= 20 { return current }
        return current + String(digit)
    }

    static func appendQuantityDigit(current: String, digit: Character) -> String {
        guard digit.isNumber else { return current }
        if current.count >= 4 { return current }
        return current + String(digit)
    }

    static func sanitizeQuantityInput(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(4))
    }
}
