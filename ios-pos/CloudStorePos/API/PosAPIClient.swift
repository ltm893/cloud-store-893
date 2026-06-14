import Foundation

enum PosAPIError: LocalizedError {
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

final class PosAPIClient {
    let baseURL: URL
    let cookieStore: CookieStore
    private let session: URLSession

    init(baseURL: URL, cookieStore: CookieStore) {
        self.baseURL = AppConfigLogic.apiBaseURL(fromRaw: baseURL.absoluteString)
        self.cookieStore = cookieStore
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        self.session = URLSession(configuration: config)
    }

    func fetchCashierSession() async throws -> CashierSessionResponse {
        try await getJSON(path: "api/cashier/session", as: CashierSessionResponse.self)
    }

    func pollApprovalStatus() async throws -> ApprovalStatusResponse {
        try await getJSON(path: "api/cashier/approval/status", as: ApprovalStatusResponse.self)
    }

    func cancelApproval() async throws {
        _ = try await postJSON(path: "api/cashier/approval/cancel", body: EmptyBody(), as: OkResponse.self)
    }

    func logoutCashier() async throws {
        _ = try await postJSON(path: "api/cashier/logout", body: EmptyBody(), as: OkResponse.self)
        if let host = baseURL.host {
            cookieStore.clearHost(host)
        } else {
            cookieStore.clearAll()
        }
    }

    func fetchTillConfig() async throws -> TillConfigResponse {
        try await getJSON(path: "api/cashier/till/config", as: TillConfigResponse.self)
    }

    func submitOpeningTill(_ body: SubmitOpeningTillRequest) async throws -> SubmitOpeningTillResponse {
        try await postJSON(path: "api/cashier/approval/till", body: body, as: SubmitOpeningTillResponse.self)
    }

    func cancelOpeningTill() async throws {
        _ = try await postJSON(path: "api/cashier/approval/till/cancel", body: EmptyBody(), as: OkResponse.self)
    }

    func fetchProducts() async throws -> [Product] {
        try await getJSON(path: "api/products", as: [Product].self)
    }

    func fetchCart() async throws -> CartResponse {
        try await getJSON(path: "api/cart", as: CartResponse.self)
    }

    func addProductToCart(productId: Int) async throws -> CartResponse {
        try await postJSON(path: "api/cart", body: ProductIdBody(productId: productId), as: CartResponse.self)
    }

    func addBarcodeToCart(barcode: String) async throws -> CartResponse {
        try await postJSON(path: "api/cart/barcode", body: BarcodeBody(barcode: barcode), as: CartResponse.self)
    }

    func removeCartItem(id: Int) async throws -> CartResponse {
        try await deleteJSON(path: "api/cart/\(id)", as: CartResponse.self)
    }

    func checkout(_ body: CheckoutRequest) async throws -> CheckoutResponse {
        try await postJSON(path: "api/checkout", body: body, as: CheckoutResponse.self)
    }

    private struct EmptyBody: Encodable {}
    private struct ProductIdBody: Encodable { let productId: Int }
    private struct BarcodeBody: Encodable { let barcode: String }

    private func getJSON<T: Decodable>(path: String, as type: T.Type) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyCookies(to: &request, url: url)
        return try await perform(request, url: url, as: type)
    }

    private func postJSON<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        as type: T.Type
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        applyCookies(to: &request, url: url)
        return try await perform(request, url: url, as: type)
    }

    private func deleteJSON<T: Decodable>(path: String, as type: T.Type) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        applyCookies(to: &request, url: url)
        return try await perform(request, url: url, as: type)
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
            throw PosAPIError.httpStatus(-1, "No HTTP response")
        }
        cookieStore.absorbSetCookieHeaders(http.allHeaderFields, for: url)

        guard (200 ..< 300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw PosAPIError.httpStatus(http.statusCode, message)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
}
