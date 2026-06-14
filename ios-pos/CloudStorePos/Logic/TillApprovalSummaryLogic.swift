import Foundation

/// Till open/close approval summary lines (mirrors Android `TillApprovalSummary.kt`).
enum TillApprovalSummaryLogic {
    private static let moneyEpsilon = 0.005

    static func approvalTimerText(secondsRemaining: Int?) -> String? {
        guard let secondsRemaining, secondsRemaining >= 0 else { return nil }
        let mins = secondsRemaining / 60
        let secs = secondsRemaining % 60
        return String(format: "Expires in %d:%02d", mins, secs)
    }

    static func openingSummaryLine(
        cashMode: String?,
        counted: Double?,
        expected: Double?,
        variance: Double?
    ) -> String? {
        guard let cashMode, !cashMode.isEmpty else { return nil }

        if cashMode == "credit_only" {
            return "Card only · Card payments only"
        }

        var parts = ["Cash + card"]
        if let counted {
            parts.append("Opening \(formatMoney(counted))")
        }
        if let expected, counted == nil || abs(expected - (counted ?? 0)) > moneyEpsilon {
            parts.append("(target \(formatMoney(expected)))")
        }
        if let variance, abs(variance) > moneyEpsilon {
            let sign = variance >= 0 ? "+" : ""
            parts.append("\(sign)\(formatMoney(variance))")
        }
        return parts.joined(separator: " · ")
    }

    static func activeTillLine(cashMode: String?, tillId: Int?) -> String? {
        var parts: [String] = []
        if let tillId {
            parts.append("Active till #\(tillId)")
        }
        if let cashMode, !cashMode.isEmpty {
            parts.append(cashMode == "credit_only" ? "Card payments only" : "Cash + card")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func formatMoney(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}
