import Foundation

enum CSVImportError: LocalizedError, Equatable {
    case emptyFile
    case missingProductIdColumn
    case noValidRows

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The file is empty."
        case .missingProductIdColumn:
            return "Select which column contains Product ID."
        case .noValidRows:
            return "No rows with a valid Product ID were found."
        }
    }
}

enum CSVImportableField: String, CaseIterable, Identifiable {
    case productId = "Product ID"
    case barcode = "Barcode"
    case name = "Name"
    case productType = "Type"
    case manufacturer = "Manufacturer"
    case price = "Price"
    case stock = "Stock"
    case pullCount = "Pull Count"

    var id: String { rawValue }

    static var optionalFields: [CSVImportableField] {
        allCases.filter { $0 != .productId }
    }
}

struct ParsedCSV: Equatable {
    let headers: [String]
    let rows: [[String]]
}

struct CSVFieldMapping: Equatable {
    var productIdColumn: String?
    var enabledFields: Set<CSVImportableField> = []
    var columnByField: [CSVImportableField: String] = [:]
}

enum CSVImportLogic {
    static func parseCSV(_ content: String) -> ParsedCSV? {
        let lines = nonEmptyLines(from: content)
        guard !lines.isEmpty else { return nil }

        let firstFields = parseCSVLine(lines[0])
        if looksLikeHeader(firstFields) {
            return ParsedCSV(
                headers: firstFields,
                rows: lines.dropFirst().map(parseCSVLine)
            )
        }

        let width = firstFields.count
        let headers = (0..<width).map { "Column \($0 + 1)" }
        return ParsedCSV(headers: headers, rows: lines.map(parseCSVLine))
    }

    static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return fields
    }

    static func suggestedMapping(for parsed: ParsedCSV) -> CSVFieldMapping {
        var mapping = CSVFieldMapping()
        mapping.productIdColumn = guessProductIdColumn(from: parsed.headers)

        for field in CSVImportableField.optionalFields {
            if let column = guessColumn(for: field, in: parsed.headers) {
                mapping.enabledFields.insert(field)
                mapping.columnByField[field] = column
            }
        }
        return mapping
    }

    static func buildItems(parsed: ParsedCSV, mapping: CSVFieldMapping) throws -> [InventoryListItem] {
        guard let productIdColumn = mapping.productIdColumn,
              let productIdIndex = parsed.headers.firstIndex(of: productIdColumn) else {
            throw CSVImportError.missingProductIdColumn
        }

        var items: [InventoryListItem] = []
        for row in parsed.rows {
            guard productIdIndex < row.count,
                  let productId = parseProductId(row[productIdIndex]) else { continue }

            let pullCount = max(1, intValue(field: .pullCount, in: row, parsed: parsed, mapping: mapping) ?? 1)
            let stockLabel = stringValue(field: .stock, in: row, parsed: parsed, mapping: mapping) ?? "—"
            let stockEmphasis = stockLabel.localizedCaseInsensitiveContains("out")

            items.append(
                InventoryListItem(
                    productId: productId,
                    barcode: stringValue(field: .barcode, in: row, parsed: parsed, mapping: mapping),
                    name: stringValue(field: .name, in: row, parsed: parsed, mapping: mapping) ?? "",
                    productType: stringValue(field: .productType, in: row, parsed: parsed, mapping: mapping),
                    manufacturer: stringValue(field: .manufacturer, in: row, parsed: parsed, mapping: mapping),
                    priceLabel: stringValue(field: .price, in: row, parsed: parsed, mapping: mapping) ?? "—",
                    stockLabel: stockLabel,
                    stockEmphasis: stockEmphasis,
                    pullCount: pullCount
                )
            )
        }

        guard !items.isEmpty else { throw CSVImportError.noValidRows }
        return items
    }

    static func applyImport(
        items: [InventoryListItem],
        toListId: UUID,
        in lists: [InventoryNamedList]
    ) -> [InventoryNamedList] {
        var updated = lists
        for item in items {
            updated = ListStoreLogic.addItem(item, toListId: toListId, in: updated)
        }
        return updated
    }

    private static func nonEmptyLines(from content: String) -> [String] {
        content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func looksLikeHeader(_ fields: [String]) -> Bool {
        let normalized = fields.map { normalizeHeader($0) }
        if normalized.contains(where: { $0.contains("product") && $0.contains("id") }) { return true }
        let keywords = ["name", "barcode", "type", "manufacturer", "price", "stock", "pull"]
        return normalized.contains { field in keywords.contains(where: { field.contains($0) }) }
    }

    private static func guessProductIdColumn(from headers: [String]) -> String? {
        headers.first { header in
            let normalized = normalizeHeader(header)
            return normalized == "productid"
                || normalized == "product id"
                || normalized == "id"
                || (normalized.contains("product") && normalized.contains("id"))
        }
    }

    static func guessColumn(for field: CSVImportableField, in headers: [String]) -> String? {
        let candidates: [String]
        switch field {
        case .productId:
            return guessProductIdColumn(from: headers)
        case .barcode:
            candidates = ["barcode", "upc", "ean", "sku"]
        case .name:
            candidates = ["name", "product name", "description"]
        case .productType:
            candidates = ["type", "product type", "category"]
        case .manufacturer:
            candidates = ["manufacturer", "mfr", "brand"]
        case .price:
            candidates = ["price", "regular price", "sale price"]
        case .stock:
            candidates = ["stock", "qty", "quantity", "on hand"]
        case .pullCount:
            candidates = ["pull count", "pull", "count"]
        }
        return headers.first { header in
            let normalized = normalizeHeader(header)
            return candidates.contains(normalized)
        }
    }

    private static func normalizeHeader(_ header: String) -> String {
        header
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseProductId(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(trimmed) { return value }
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty, let value = Int(digits) else { return nil }
        return value
    }

    private static func stringValue(
        field: CSVImportableField,
        in row: [String],
        parsed: ParsedCSV,
        mapping: CSVFieldMapping
    ) -> String? {
        guard mapping.enabledFields.contains(field),
              let column = mapping.columnByField[field],
              let index = parsed.headers.firstIndex(of: column),
              index < row.count else { return nil }
        let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func intValue(
        field: CSVImportableField,
        in row: [String],
        parsed: ParsedCSV,
        mapping: CSVFieldMapping
    ) -> Int? {
        guard let string = stringValue(field: field, in: row, parsed: parsed, mapping: mapping) else { return nil }
        return Int(string.filter(\.isNumber))
    }
}
