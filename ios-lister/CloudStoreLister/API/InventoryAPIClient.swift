import Foundation

enum InventoryAPIError: LocalizedError {
    case invalidURL
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty { return message }
            return "Server error (\(code))"
        }
    }
}

final class InventoryAPIClient {
    let baseURL: URL
    private let cookieStore: CookieStore?
    private let session: URLSession

    init(baseURL: URL, cookieStore: CookieStore? = nil, session: URLSession? = nil) {
        self.baseURL = AppConfigLogic.apiBaseURL(fromRaw: baseURL.absoluteString)
        self.cookieStore = cookieStore
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.httpShouldSetCookies = false
            config.httpCookieAcceptPolicy = .never
            self.session = URLSession(configuration: config)
        }
    }

    func lookup(query: String) async throws -> InventoryProduct {
        let candidates = BarcodeNormalizeLogic.lookupCandidates(query)
        let attempts = candidates.isEmpty ? [query] : candidates
        var lastError: Error?

        for candidate in attempts {
            do {
                return try await performLookup(query: candidate)
            } catch {
                lastError = error
                if case InventoryAPIError.httpStatus(let code, _) = error, code == 404 {
                    continue
                }
                throw error
            }
        }

        throw lastError ?? InventoryAPIError.httpStatus(404, "Product not found")
    }

    private func performLookup(query: String) async throws -> InventoryProduct {
        guard let url = AppConfigLogic.inventoryLookupURL(base: baseURL, query: query) else {
            throw InventoryAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let header = cookieStore?.cookieHeader(for: url) {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw InventoryAPIError.httpStatus(-1, nil)
        }
        cookieStore?.absorbSetCookieHeaders(http.allHeaderFields, for: url)
        guard http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(InventoryLookupErrorResponse.self, from: data))?.error
            throw InventoryAPIError.httpStatus(http.statusCode, message)
        }
        return try JSONDecoder().decode(InventoryProduct.self, from: data)
    }

    func lookup(productId: Int) async throws -> InventoryProduct {
        try await lookup(query: "\(productId)")
    }
}
