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

    static func adminURL(base: URL, portraitClient: Bool) -> URL {
        var components = URLComponents(
            url: base.appendingPathComponent("admin/"),
            resolvingAgainstBaseURL: false
        )!
        if portraitClient {
            components.queryItems = [URLQueryItem(name: "client_kind", value: "ios")]
        }
        return components.url!
    }
}
