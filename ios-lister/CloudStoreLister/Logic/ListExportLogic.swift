import Foundation

enum ListExportLogic {
    struct Summary: Equatable {
        let itemCount: Int
        let totalPullCount: Int
    }

    static func summary(for items: [InventoryListItem]) -> Summary {
        Summary(
            itemCount: items.count,
            totalPullCount: items.reduce(0) { $0 + $1.pullCount }
        )
    }

    static func buildCSVString(for items: [InventoryListItem]) -> String {
        var csv = "Name,Type,Product ID,Barcode,Price,Stock,Pull Count\n"
        for item in items {
            csv += [
                csvQuoted(item.name),
                csvQuoted(item.productType ?? ""),
                csvQuoted("\(item.productId)"),
                csvQuoted(item.barcode ?? ""),
                csvQuoted(item.priceLabel),
                csvQuoted(item.stockLabel),
                "\(item.pullCount)",
            ].joined(separator: ",")
            csv += "\n"
        }
        return csv
    }

    static func writeCSVFile(items: [InventoryListItem], listName: String) -> URL? {
        let safeName = sanitizedFileName(listName)
        let timestamp = Int(Date().timeIntervalSince1970)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName)_\(timestamp).csv")
        do {
            try buildCSVString(for: items).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func csvQuoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func sanitizedFileName(_ name: String) -> String {
        let noSpaces = name.replacingOccurrences(of: " ", with: "_")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = noSpaces
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
        return cleaned.isEmpty ? "list" : cleaned
    }
}
