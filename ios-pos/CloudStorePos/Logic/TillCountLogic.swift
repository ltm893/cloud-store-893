import Foundation

enum TillCountLogic {
    private static let moneyEpsilon = 0.005

    static func roundMoney(_ amount: Double) -> Double {
        (amount * 100).rounded() / 100
    }

    static func formatMoney(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }

    static func sumTillCounts(
        denominations: [TillDenomination],
        counts: [String: String]
    ) -> Double {
        var total = 0.0
        for denom in denominations {
            let count = Int(counts[denom.id] ?? "") ?? 0
            if count > 0 {
                total += denom.value * Double(count)
            }
        }
        return roundMoney(total)
    }

    static func canSubmit(
        expectedOpeningFloat: Double?,
        denominations: [TillDenomination],
        counts: [String: String],
        requireExactMatch: Bool = true
    ) -> Bool {
        let countedTotal = sumTillCounts(denominations: denominations, counts: counts)
        if let expected = expectedOpeningFloat {
            let targetReached = abs(countedTotal - expected) < moneyEpsilon
            if targetReached { return true }
        }
        if !requireExactMatch {
            return denominations.contains { denom in
                (Int(counts[denom.id] ?? "") ?? 0) > 0
            }
        }
        return expectedOpeningFloat.map { abs(countedTotal - $0) < moneyEpsilon } ?? false
    }

    static func summaryLine(
        expectedOpeningFloat: Double?,
        countedTotal: Double,
        referenceLabel: String = "Target"
    ) -> String {
        var parts: [String] = []
        if let expected = expectedOpeningFloat {
            parts.append("\(referenceLabel) \(formatMoney(expected))")
        }
        parts.append("Total \(formatMoney(countedTotal))")
        return parts.joined(separator: " · ")
    }

    static func actionStatus(
        expectedOpeningFloat: Double?,
        denominations: [TillDenomination],
        counts: [String: String],
        submitting: Bool,
        status: String,
        defaultStatus: String = "Count opening till",
        requireExactMatch: Bool = true
    ) -> String {
        if submitting { return "Submitting till count…" }
        if !status.isEmpty && status != "Ready" && status != defaultStatus { return status }

        let countedTotal = sumTillCounts(denominations: denominations, counts: counts)
        let targetReached = expectedOpeningFloat.map { abs(countedTotal - $0) < moneyEpsilon } == true
        if targetReached { return "Ready to submit" }

        if !requireExactMatch {
            let hasCounts = denominations.contains { (Int(counts[$0.id] ?? "") ?? 0) > 0 }
            if hasCounts, let expected = expectedOpeningFloat {
                let variance = roundMoney(countedTotal - expected)
                if abs(variance) > moneyEpsilon {
                    let sign = variance >= 0 ? "+" : ""
                    return "Variance \(sign)\(formatMoney(variance)) — ready to submit"
                }
            }
            if hasCounts { return "Ready to submit for approval" }
        }

        if let expected = expectedOpeningFloat {
            let diff = roundMoney(expected - countedTotal)
            if diff > moneyEpsilon { return "Need \(formatMoney(diff)) more" }
            if diff < -moneyEpsilon { return "\(formatMoney(-diff)) over target" }
            return "Ready to submit"
        }
        return "Enter counts for each denomination"
    }
}
