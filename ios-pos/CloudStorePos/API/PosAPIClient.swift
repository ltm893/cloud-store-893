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
            return APIErrorMessageLogic.httpErrorMessage(statusCode: code, body: nil)
        }
    }
}

final class PosAPIClient {
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

    func unlockCashier(pin: String, registerId: String) async throws -> UnlockCashierResponse {
        try await postJSON(
            path: "api/cashier/unlock",
            body: UnlockCashierRequest(pin: pin, clientKind: "ios", registerId: registerId),
            as: UnlockCashierResponse.self
        )
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

    func closeTillPreview() async throws -> CloseTillPreviewResponse {
        try await getJSON(
            path: "api/cashier/shift/close/preview",
            queryItems: [URLQueryItem(name: "register_id", value: registerId)],
            as: CloseTillPreviewResponse.self
        )
    }

    func submitCloseTill(_ body: SubmitCloseTillRequest) async throws -> SubmitCloseTillResponse {
        try await postJSON(
            path: "api/cashier/shift/close/till",
            body: body,
            as: SubmitCloseTillResponse.self
        )
    }

    func closeTillStatus(closeToken: String? = nil) async throws -> CloseTillStatusResponse {
        var queryItems: [URLQueryItem] = []
        if let token = closeToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            queryItems.append(URLQueryItem(name: "closeToken", value: token))
        }
        return try await getJSON(
            path: "api/cashier/shift/close/status",
            queryItems: queryItems,
            as: CloseTillStatusResponse.self
        )
    }

    func cancelCloseTill() async throws {
        _ = try await postJSON(path: "api/cashier/shift/close/cancel", body: EmptyBody(), as: OkResponse.self)
    }

    func fetchProducts() async throws -> [Product] {
        try await getJSON(path: "api/products", as: [Product].self)
    }

    func fetchCustomers() async throws -> [StoreCustomer] {
        try await getJSON(path: "api/customers", as: [StoreCustomer].self)
    }

    func fetchCart(customerId: Int? = nil) async throws -> CartResponse {
        try await getJSON(
            path: "api/cart",
            queryItems: customerQueryItems(customerId),
            as: CartResponse.self
        )
    }

    func addProductToCart(productId: Int, customerId: Int? = nil) async throws -> CartResponse {
        try await postJSON(
            path: "api/cart",
            body: ProductIdBody(productId: productId),
            queryItems: customerQueryItems(customerId),
            as: CartResponse.self
        )
    }

    func addBarcodeToCart(barcode: String, customerId: Int? = nil) async throws -> CartResponse {
        try await postJSON(
            path: "api/cart/barcode",
            body: BarcodeBody(barcode: barcode),
            queryItems: customerQueryItems(customerId),
            as: CartResponse.self
        )
    }

    func removeCartItem(id: Int, customerId: Int? = nil) async throws -> CartResponse {
        try await deleteJSON(
            path: "api/cart/\(id)",
            queryItems: customerQueryItems(customerId),
            as: CartResponse.self
        )
    }

    func updateCartItemQuantity(id: Int, quantity: Int, customerId: Int? = nil) async throws -> CartResponse {
        try await putJSON(
            path: "api/cart/\(id)",
            body: QuantityBody(quantity: quantity),
            queryItems: customerQueryItems(customerId),
            as: CartResponse.self
        )
    }

    func replaceCart(items: [CartLineQuantity], customerId: Int? = nil) async throws -> CartResponse {
        try await postJSON(
            path: "api/cart/replace",
            body: CartReplaceRequest(items: items, customerId: customerId),
            as: CartResponse.self
        )
    }

    func checkout(_ body: CheckoutRequest) async throws -> CheckoutResponse {
        try await postJSON(path: "api/checkout", body: body, as: CheckoutResponse.self)
    }

    private func customerQueryItems(_ customerId: Int?) -> [URLQueryItem] {
        guard let customerId else { return [] }
        return [URLQueryItem(name: "customerId", value: String(customerId))]
    }

    private struct EmptyBody: Encodable {}
    private struct ProductIdBody: Encodable { let productId: Int }
    private struct BarcodeBody: Encodable { let barcode: String }
    private struct QuantityBody: Encodable { let quantity: Int }

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

    private func putJSON<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        queryItems: [URLQueryItem] = [],
        as type: T.Type
    ) async throws -> T {
        let url = try requestURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        applyCookies(to: &request, url: url)
        return try await perform(request, url: url, as: type)
    }

    private func deleteJSON<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        as type: T.Type
    ) async throws -> T {
        let url = try requestURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        applyCookies(to: &request, url: url)
        return try await perform(request, url: url, as: type)
    }

    private func requestURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard let url = AppConfigLogic.apiRequestURL(base: baseURL, path: path, queryItems: queryItems) else {
            throw PosAPIError.invalidURL
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
            throw PosAPIError.httpStatus(-1, "No HTTP response")
        }
        cookieStore.absorbSetCookieHeaders(http.allHeaderFields, for: url)

        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            let message = APIErrorMessageLogic.httpErrorMessage(statusCode: http.statusCode, body: body)
            throw PosAPIError.httpStatus(http.statusCode, message)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
}
