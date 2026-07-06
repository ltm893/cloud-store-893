import Foundation

/// OIDC redirect detection for lister sign-in (no till or supervisor approval).
enum ListerOidcRedirectLogic {
    static func normalizedBase(_ url: URL) -> String {
        var base = url.absoluteString
        if base.hasSuffix("/") {
            base.removeLast()
        }
        return base
    }

    static func isOidcComplete(completionURL: URL, apiBaseURL: URL) -> Bool {
        let base = normalizedBase(apiBaseURL)
        guard completionURL.absoluteString.hasPrefix(base) else { return false }

        guard let components = URLComponents(url: completionURL, resolvingAgainstBaseURL: false) else {
            return false
        }
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name, value)
            }
        )

        if query["lister_signed_in"] != nil { return true }
        return isAppRootLanding(completionURL: completionURL, apiBaseURL: apiBaseURL)
    }

    private static func isAppRootLanding(completionURL: URL, apiBaseURL: URL) -> Bool {
        let base = normalizedBase(apiBaseURL)
        guard completionURL.absoluteString.hasPrefix(base) else { return false }
        guard let components = URLComponents(url: completionURL, resolvingAgainstBaseURL: false) else {
            return false
        }
        let path = components.path
        guard path.isEmpty || path == "/" else { return false }
        let lower = completionURL.absoluteString.lowercased()
        if lower.contains("/oauth/") { return false }
        return true
    }

    static func syncProbeURLs(baseURL: URL) -> [URL] {
        let root = normalizedBase(baseURL)
        let candidates = [
            "\(root)/",
            "\(root)/?lister_signed_in=1",
            "\(root)/oauth/callback",
        ]
        return candidates.compactMap { URL(string: $0) }
    }
}
