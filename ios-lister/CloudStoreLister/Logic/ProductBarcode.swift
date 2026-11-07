import Foundation

/// Chooses the barcode the product catalog can match.
///
/// A bottle often carries a UPC and a longer Code 128. The camera reports
/// whichever it decodes first. UPC-A arrives on iOS as an EAN-13 with a
/// leading zero (`0080432500170` is UPC `080432500170`).
enum ProductBarcode {
    enum Symbology: Equatable {
        case upcA, upcE, ean13, ean8, code128, pdf417, qr, other

        var label: String {
            switch self {
            case .upcA: return "UPC-A"
            case .upcE: return "UPC-E"
            case .ean13: return "EAN-13"
            case .ean8: return "EAN-8"
            case .code128: return "Code 128"
            case .pdf417: return "PDF417"
            case .qr: return "QR"
            case .other: return "Other"
            }
        }

        var isRetail: Bool {
            switch self {
            case .upcA, .upcE, .ean13, .ean8: return true
            case .code128, .pdf417, .qr, .other: return false
            }
        }
    }

    struct Read: Equatable {
        let symbology: Symbology
        let value: String
    }

    struct Selection: Equatable {
        let symbology: Symbology
        let value: String
        let ignored: [Read]

        var logMessage: String {
            let skipped = ignored
                .map { "\($0.value) (\($0.symbology.label))" }
                .joined(separator: ", ")
            let extra = skipped.isEmpty ? "" : "; ignored \(skipped)"
            return "Barcode scanned: \(value) (\(symbology.label))\(extra)"
        }
    }

    enum Decision: Equatable {
        case accept
        case wait
    }

    /// How long a Code 128 (or other non-UPC) is held so a UPC in the next frames can win.
    static let nonRetailHold: TimeInterval = 0.45

    static func preferred(from reads: [Read]) -> Selection? {
        let usable = reads.compactMap { read -> Read? in
            let value = read.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return Read(symbology: read.symbology, value: value)
        }
        guard let index = usable.indices.min(by: { rank(usable[$0].symbology) < rank(usable[$1].symbology) }) else {
            return nil
        }
        let best = usable[index]
        let value = catalogValue(symbology: best.symbology, raw: best.value)
        let reported: Symbology = (best.symbology == .ean13 && value.count == 12) ? .upcA : best.symbology
        let ignored = usable.enumerated().compactMap { offset, read in
            offset == index ? nil : read
        }
        return Selection(symbology: reported, value: value, ignored: ignored)
    }

    /// A retail code is used immediately. Anything else waits [nonRetailHold] for a UPC to appear.
    static func decide(symbology: Symbology, pendingSince: Date?, now: Date) -> Decision {
        if symbology.isRetail { return .accept }
        guard let pendingSince else { return .wait }
        if now.timeIntervalSince(pendingSince) >= nonRetailHold { return .accept }
        return .wait
    }

    static func catalogValue(symbology: Symbology, raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("'") {
            text = String(text.dropFirst())
        }
        switch symbology {
        case .ean13, .upcA:
            let digits = text.filter(\.isNumber)
            if symbology == .ean13, digits.count == 13, digits.hasPrefix("0") {
                return String(digits.dropFirst())
            }
            return digits.isEmpty ? text : digits
        default:
            return text
        }
    }

    private static func rank(_ symbology: Symbology) -> Int {
        switch symbology {
        case .upcA: return 0
        case .ean13: return 1
        case .upcE: return 2
        case .ean8: return 3
        case .code128: return 4
        case .pdf417: return 5
        case .qr: return 6
        case .other: return 7
        }
    }
}
