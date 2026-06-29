import Foundation

@MainActor
final class InventoryLookupViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var product: InventoryProduct?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastQuery = ""

    private let api: InventoryAPIClient

    init(api: InventoryAPIClient = InventoryAPIClient(baseURL: AppConfig.apiBaseURL)) {
        self.api = api
    }

    func appendDigit(_ digit: Character) {
        inputText.append(digit)
    }

    func backspace() {
        guard !inputText.isEmpty else { return }
        inputText.removeLast()
    }

    func clearInput() {
        inputText = ""
    }

    func lookup() {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            errorMessage = "Enter product ID or barcode"
            return
        }
        Task { await performLookup(query: query) }
    }

    private func performLookup(query: String) async {
        isLoading = true
        errorMessage = nil
        product = nil
        lastQuery = query
        defer { isLoading = false }

        do {
            product = try await api.lookup(query: query)
            inputText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
