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
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = AppConfigLogic.apiBaseURL(fromRaw: baseURL.absoluteString)
        self.session = session
    }

    func lookup(query: String) async throws -> InventoryProduct {
        guard let url = AppConfigLogic.inventoryLookupURL(base: baseURL, query: query) else {
            throw InventoryAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw InventoryAPIError.httpStatus(-1, nil)
        }
        guard http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(InventoryLookupErrorResponse.self, from: data))?.error
            throw InventoryAPIError.httpStatus(http.statusCode, message)
        }
        return try JSONDecoder().decode(InventoryProduct.self, from: data)
    }
}
