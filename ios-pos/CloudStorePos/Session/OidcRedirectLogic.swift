import Foundation

/// OIDC redirect detection (mirrors Android `CashierOidcWebScreen.kt`).
enum OidcRedirectLogic {
    static func normalizedBase(_ url: URL) -> String {
        var base = url.absoluteString
        if base.hasSuffix("/") {
            base.removeLast()
        }
        return base
    }

    static func isCashierOidcComplete(completionURL: URL, apiBaseURL: URL) -> Bool {
        let base = normalizedBase(apiBaseURL)
        let target = completionURL.absoluteString
        guard target.hasPrefix(base) else { return false }

        guard let components = URLComponents(url: completionURL, resolvingAgainstBaseURL: false) else {
            return false
        }
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name, value)
            }
        )

        if query["awaiting_till"] != nil { return true }
        if query["approval"] == "pending" { return true }
        if query["cashier_resume"] != nil { return true }
        // Legacy / web-style resume marker (OCI may redirect here before native fix is deployed).
        if query["resumed"] != nil { return true }
        if isAppRootLanding(completionURL: completionURL, apiBaseURL: apiBaseURL) {
            return true
        }
        return false
    }

    static func isResumeRedirect(completionURL: URL) -> Bool {
        guard let components = URLComponents(url: completionURL, resolvingAgainstBaseURL: false) else {
            return false
        }
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name, value)
            }
        )
        if query["cashier_resume"] != nil || query["resumed"] != nil { return true }
        return false
    }

    /// OIDC `successRedirect` is `/` — session cookie may be set with no native query marker.
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

    static func parsePendingRequestToken(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let token = components.queryItems?
            .first(where: { $0.name == "request_token" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token, !token.isEmpty else { return nil }
        return token
    }

    static func syncProbeURLs(baseURL: URL) -> [URL] {
        let root = normalizedBase(baseURL)
        let candidates = [
            "\(root)/",
            "\(root)/?approval=pending",
            "\(root)/?awaiting_till=1",
            "\(root)/?cashier_resume=1",
            "\(root)/?resumed=1",
            "\(root)/oauth/callback",
        ]
        return candidates.compactMap { URL(string: $0) }
    }
}
