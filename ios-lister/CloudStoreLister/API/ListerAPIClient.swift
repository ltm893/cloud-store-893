import Foundation

enum ListerAPIError: LocalizedError {
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

final class ListerAPIClient {
    let baseURL: URL
    let cookieStore: CookieStore
    let registerId: String
    private let session: URLSession

    init(baseURL: URL, cookieStore: CookieStore, registerId: String = AppConfig.registerId) {
        self.baseURL = AppConfigLogic.apiBaseURL(fromRaw: baseURL.absoluteString)
        self.cookieStore = cookieStore
        self.registerId = registerId
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        self.session = URLSession(configuration: config)
    }

    func fetchCashierSession() async throws -> CashierSessionResponse {
        try await getJSON(
            path: "api/cashier/session",
            queryItems: [URLQueryItem(name: "register_id", value: registerId)],
            as: CashierSessionResponse.self
        )
    }

    func logoutCashier() async throws {
        _ = try await postJSON(path: "api/cashier/logout", body: EmptyBody(), as: OkResponse.self)
        if let host = baseURL.host {
            cookieStore.clearHost(host)
        } else {
            cookieStore.clearAll()
        }
    }

    private struct EmptyBody: Encodable {}

    private func getJSON<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        as type: T.Type
    ) async throws -> T {
        let url = try requestURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyCookies(to: &request, url: url)
        return try await perform(request, url: url, as: type)
    }

    private func postJSON<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        queryItems: [URLQueryItem] = [],
        as type: T.Type
    ) async throws -> T {
        let url = try requestURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        applyCookies(to: &request, url: url)
        return try await perform(request, url: url, as: type)
    }

    private func requestURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard let url = AppConfigLogic.apiRequestURL(base: baseURL, path: path, queryItems: queryItems) else {
            throw ListerAPIError.invalidURL
        }
        return url
    }

    private func applyCookies(to request: inout URLRequest, url: URL) {
        if let header = cookieStore.cookieHeader(for: url) {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }
    }

    private func perform<T: Decodable>(
        _ request: URLRequest,
        url: URL,
        as type: T.Type
    ) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ListerAPIError.httpStatus(-1, nil)
        }
        cookieStore.absorbSetCookieHeaders(http.allHeaderFields, for: url)

        guard (200 ..< 300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw ListerAPIError.httpStatus(http.statusCode, message)
        }

        return try JSONDecoder().decode(type, from: data)
    }
}
