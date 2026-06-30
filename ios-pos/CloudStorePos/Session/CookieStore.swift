import Foundation

/// In-memory cashier cookies for API calls (mirrors Android `MemoryCookieJar.kt`).
/// Thread-safe: parallel URLSession tasks may read/write cookies concurrently.
final class CookieStore: @unchecked Sendable {
    static let cashierSession = "cashier_session"
    static let cashierPending = "cashier_pending"
    static let cashierAwaitingTill = "cashier_awaiting_till"

    private let lock = NSLock()
    private var store: [String: [String: HTTPCookie]] = [:]
    private var pinnedPendingToken: String?
    private var pinnedAwaitingTillToken: String?
    private var manualSessionId: String?

    var hasPinnedPendingToken: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pinnedPendingToken != nil
    }

    var hasPinnedAwaitingTillToken: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pinnedAwaitingTillToken != nil
    }

    func saveFromResponse(url: URL, cookies: [HTTPCookie]) {
        guard !cookies.isEmpty, let host = url.host else { return }
        let now = Date()

        lock.lock()
        defer { lock.unlock() }

        for cookie in cookies {
            switch cookie.name {
            case Self.cashierPending:
                if let expires = cookie.expiresDate, expires <= now {
                    if pinnedPendingToken == cookie.value { pinnedPendingToken = nil }
                } else if pinnedPendingToken == nil {
                    pinnedPendingToken = cookie.value
                }
            case Self.cashierAwaitingTill:
                if let expires = cookie.expiresDate, expires <= now {
                    if pinnedAwaitingTillToken == cookie.value { pinnedAwaitingTillToken = nil }
                } else if pinnedAwaitingTillToken == nil {
                    pinnedAwaitingTillToken = cookie.value
                }
            case Self.cashierSession:
                if let expires = cookie.expiresDate, expires <= now {
                    manualSessionId = nil
                } else {
                    manualSessionId = cookie.value
                    pinnedPendingToken = nil
                    pinnedAwaitingTillToken = nil
                }
            default:
                break
            }

            var bucket = store[host, default: [:]]
            bucket.removeValue(forKey: cookie.name)
            if let expires = cookie.expiresDate, expires <= now { continue }
            bucket[cookie.name] = cookie
            store[host] = bucket
        }
    }

    func absorbSetCookieHeaders(_ headers: [AnyHashable: Any], for url: URL) {
        var collected: [HTTPCookie] = []
        for (key, value) in headers {
            guard let name = key as? String, name.lowercased() == "set-cookie" else { continue }
            let rawValues: [String]
            if let raw = value as? String {
                rawValues = [raw]
            } else if let array = value as? [String] {
                rawValues = array
            } else {
                continue
            }
            for raw in rawValues {
                collected.append(
                    contentsOf: HTTPCookie.cookies(
                        withResponseHeaderFields: ["Set-Cookie": raw],
                        for: url
                    )
                )
            }
        }
        guard !collected.isEmpty else { return }
        saveFromResponse(url: url, cookies: collected)
    }

    func cookies(for url: URL) -> [HTTPCookie] {
        guard let host = url.host else { return [] }
        let now = Date()
        let secure = url.scheme?.lowercased() == "https"

        lock.lock()
        defer { lock.unlock() }

        var bucket = store[host, default: [:]]
        bucket = bucket.filter { _, cookie in
            guard let expires = cookie.expiresDate else { return true }
            return expires > now
        }
        store[host] = bucket

        var merged = Array(bucket.values)
        if let token = pinnedPendingToken,
           let cookie = makeCookie(host: host, name: Self.cashierPending, value: token, secure: secure) {
            merged.removeAll { $0.name == Self.cashierPending }
            merged.append(cookie)
        }
        if let token = pinnedAwaitingTillToken,
           let cookie = makeCookie(host: host, name: Self.cashierAwaitingTill, value: token, secure: secure) {
            merged.removeAll { $0.name == Self.cashierAwaitingTill }
            merged.append(cookie)
        }
        if let sessionId = manualSessionId,
           !merged.contains(where: { $0.name == Self.cashierSession }),
           let cookie = makeCookie(host: host, name: Self.cashierSession, value: sessionId, secure: secure) {
            merged.append(cookie)
        }
        return merged
    }

    func cookieHeader(for url: URL) -> String? {
        let parts = cookies(for: url).map { "\($0.name)=\($0.value)" }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    func rememberPendingRequestToken(_ token: String, baseURL: URL) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let host = baseURL.host else { return }
        let secure = baseURL.scheme?.lowercased() == "https"

        lock.lock()
        pinnedPendingToken = trimmed
        lock.unlock()

        if let cookie = makeCookie(host: host, name: Self.cashierPending, value: trimmed, secure: secure) {
            saveFromResponse(url: baseURL, cookies: [cookie])
        }
    }

    func rememberAwaitingTillToken(_ token: String, baseURL: URL) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let host = baseURL.host else { return }
        let secure = baseURL.scheme?.lowercased() == "https"

        lock.lock()
        pinnedAwaitingTillToken = trimmed
        lock.unlock()

        if let cookie = makeCookie(host: host, name: Self.cashierAwaitingTill, value: trimmed, secure: secure) {
            saveFromResponse(url: baseURL, cookies: [cookie])
        }
    }

    /// After WebView sync, pin awaiting-till from the jar if the server set it but the pin was lost.
    func pinAwaitingTillFromStoreIfNeeded(baseURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard pinnedAwaitingTillToken == nil,
              let host = baseURL.host,
              let cookie = store[host]?[Self.cashierAwaitingTill] else { return }
        pinnedAwaitingTillToken = cookie.value
    }

    func clearHost(_ host: String) {
        lock.lock()
        defer { lock.unlock() }
        store.removeValue(forKey: host)
        pinnedPendingToken = nil
        pinnedAwaitingTillToken = nil
        manualSessionId = nil
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        store.removeAll()
        pinnedPendingToken = nil
        pinnedAwaitingTillToken = nil
        manualSessionId = nil
    }

    func clearAwaitingTillAuth(for host: String?) {
        lock.lock()
        pinnedAwaitingTillToken = nil
        if let host {
            store[host]?.removeValue(forKey: Self.cashierAwaitingTill)
        }
        lock.unlock()
    }

    var pinnedAwaitingTillTokenValue: String? {
        lock.lock()
        defer { lock.unlock() }
        return pinnedAwaitingTillToken
    }

    func hasCashierSession(for host: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if manualSessionId != nil { return true }
        guard let host else { return false }
        return store[host]?[Self.cashierSession] != nil
    }

    private func makeCookie(host: String, name: String, value: String, secure: Bool) -> HTTPCookie? {
        HTTPCookie(properties: [
            .domain: host,
            .path: "/",
            .name: name,
            .value: value,
            .secure: secure ? "TRUE" : "FALSE",
            .discard: "TRUE",
        ])
    }
}
