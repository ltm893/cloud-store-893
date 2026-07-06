import Foundation

/// In-memory cashier session cookie for API calls (mirrors ios-pos `CookieStore`).
final class CookieStore: @unchecked Sendable {
    static let cashierSession = "cashier_session"

    private let lock = NSLock()
    private var store: [String: [String: HTTPCookie]] = [:]
    private var manualSessionId: String?

    func saveFromResponse(url: URL, cookies: [HTTPCookie]) {
        guard !cookies.isEmpty, let host = url.host else { return }
        let now = Date()

        lock.lock()
        defer { lock.unlock() }

        for cookie in cookies {
            guard cookie.name == Self.cashierSession else { continue }
            if let expires = cookie.expiresDate, expires <= now {
                manualSessionId = nil
            } else {
                manualSessionId = cookie.value
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

    func clearHost(_ host: String) {
        lock.lock()
        defer { lock.unlock() }
        store.removeValue(forKey: host)
        manualSessionId = nil
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        store.removeAll()
        manualSessionId = nil
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
