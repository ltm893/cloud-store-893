import Foundation

/// Barcode lookup variants (mirrors `lib/barcode-normalize.js`).
enum BarcodeNormalizeLogic {
    static func ean13CheckDigit(_ data12: String) -> String? {
        let digits = data12.filter(\.isNumber)
        guard digits.count == 12 else { return nil }
        var sum = 0
        for (index, char) in digits.enumerated() {
            guard let n = char.wholeNumberValue else { return nil }
            sum += index.isMultiple(of: 2) ? n : n * 3
        }
        return String((10 - (sum % 10)) % 10)
    }

    static func lookupCandidates(_ raw: String) -> [String] {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        guard value.allSatisfy(\.isNumber) else { return [value] }

        var candidates: [String] = []
        func add(_ code: String) {
            guard !code.isEmpty, !candidates.contains(code) else { return }
            candidates.append(code)
        }

        add(value)

        if value.count == 13 {
            add(String(value.prefix(12)))
            if value.hasPrefix("0") {
                add(String(value.dropFirst()))
            }
        }

        if value.count == 12 {
            if let check = ean13CheckDigit(value) {
                add(value + check)
            }
            add("0" + value)
        }

        if value.count == 11 {
            let padded = String(repeating: "0", count: max(0, 12 - value.count)) + value
            if let check = ean13CheckDigit(padded) {
                add(padded + check)
            }
            add(padded)
        }

        return candidates
    }
}
