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

    /// Oracle OIDC entry for native iPad register (`client_kind=ios`).
    static func oidcLoginURL(
        base: URL,
        registerId: String,
        freshLogin: Bool = false
    ) -> URL {
        var components = URLComponents(
            url: base.appendingPathComponent("oauth/login"),
            resolvingAgainstBaseURL: false
        )!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "client_kind", value: "ios"),
            URLQueryItem(name: "register_id", value: registerId),
        ]
        if freshLogin {
            queryItems.append(URLQueryItem(name: "prompt", value: "login"))
        }
        components.queryItems = queryItems
        return components.url!
    }
}
