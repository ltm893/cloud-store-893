import Foundation

/// Pure URL helpers (unit-tested without UIKit).
enum AppConfigLogic {
    static func normalizeBaseURLString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("/") ? trimmed : "\(trimmed)/"
    }

    static func apiBaseURL(fromRaw raw: String, fallback: String = "https://oci.cloudstore893.com/") -> URL {
        let normalized = normalizeBaseURLString(raw)
        return URL(string: normalized) ?? URL(string: fallback)!
    }

    static func inventoryLookupURL(base: URL, query: String) -> URL? {
        var components = URLComponents(
            url: base.appendingPathComponent("api/inventory/lookup"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}
