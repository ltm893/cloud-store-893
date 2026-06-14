import Foundation
import WebKit

/// Copy cookies from WKWebView into [CookieStore] for URLSession API calls.
@MainActor
enum WebViewCookieSync {
    static func sync(
        baseURL: URL,
        cookieStore: CookieStore,
        dataStore: WKWebsiteDataStore? = nil
    ) async {
        let resolvedStore = dataStore ?? WKWebsiteDataStore.default()
        let httpStore = resolvedStore.httpCookieStore
        var collected: [HTTPCookie] = []

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            httpStore.getAllCookies { cookies in
                collected = cookies
                continuation.resume()
            }
        }

        let host = baseURL.host?.lowercased()
        if let host {
            let hostCookies = collected.filter { cookie in
                cookie.domain.lowercased().hasSuffix(host) || host.hasSuffix(cookie.domain.lowercased())
            }
            cookieStore.saveFromResponse(url: baseURL, cookies: hostCookies)
        }

        for probeURL in OidcRedirectLogic.syncProbeURLs(baseURL: baseURL) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                httpStore.getAllCookies { all in
                    let host = probeURL.host?.lowercased()
                    let matched = all.filter { cookie in
                        guard let host else { return false }
                        return cookie.domain.lowercased().hasSuffix(host) || host.hasSuffix(cookie.domain.lowercased())
                    }
                    cookieStore.saveFromResponse(url: probeURL, cookies: matched)
                    continuation.resume()
                }
            }
        }
    }

    static func clearIdpCookies(dataStore: WKWebsiteDataStore? = nil) async {
        let resolvedStore = dataStore ?? WKWebsiteDataStore.default()
        let httpStore = resolvedStore.httpCookieStore
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            httpStore.getAllCookies { cookies in
                let group = DispatchGroup()
                for cookie in cookies {
                    group.enter()
                    httpStore.delete(cookie) { group.leave() }
                }
                group.notify(queue: .main) {
                    continuation.resume()
                }
            }
        }
    }
}
