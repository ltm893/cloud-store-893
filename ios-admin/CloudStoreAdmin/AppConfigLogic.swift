import Foundation

/// Pure URL helpers (unit-tested without UIKit device idiom).
enum AppConfigLogic {
    static func normalizeBaseURLString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("/") ? trimmed : "\(trimmed)/"
    }

    static func apiBaseURL(fromRaw raw: String, fallback: String = "https://oci.cloudstore893.com/") -> URL {
        let normalized = normalizeBaseURLString(raw)
        return URL(string: normalized) ?? URL(string: fallback)!
    }

    static func adminURL(base: URL, embeddedIosClient: Bool, cacheBust: String? = nil) -> URL {
        var components = URLComponents(
            url: base.appendingPathComponent("admin/"),
            resolvingAgainstBaseURL: false
        )!
        var queryItems: [URLQueryItem] = []
        if embeddedIosClient {
            queryItems.append(URLQueryItem(name: "client_kind", value: "ios"))
        }
        if let cacheBust, !cacheBust.isEmpty {
            queryItems.append(URLQueryItem(name: "_cb", value: cacheBust))
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url!
    }
}
