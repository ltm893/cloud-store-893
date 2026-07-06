import Foundation

@MainActor
final class InventoryLookupViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var product: InventoryProduct?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastQuery = ""
    @Published var lists: [InventoryNamedList] = []
    @Published var activeListId: UUID = InventoryListDefaults.myListId

    var activeListName: String {
        lists.first { $0.id == activeListId }?.name ?? InventoryListDefaults.myListName
    }

    var activeListItems: [InventoryListItem] {
        lists.first { $0.id == activeListId }?.items ?? []
    }

    private let api: InventoryAPIClient
    private let userDefaults: UserDefaults
    private let listsKey = "InventoryNamedLists"
    private let activeListIdKey = "InventoryActiveListId"

    init(
        api: InventoryAPIClient = InventoryAPIClient(baseURL: AppConfig.apiBaseURL),
        userDefaults: UserDefaults = .standard
    ) {
        self.api = api
        self.userDefaults = userDefaults
        loadLists()
    }

    func switchList(to id: UUID) {
        guard lists.contains(where: { $0.id == id }) else { return }
        activeListId = id
        saveActiveListId()
    }

    @discardableResult
    func createList(name: String) -> UUID {
        let (updated, newId) = ListStoreLogic.createList(name: name, in: lists)
        lists = updated
        activeListId = newId
        saveLists()
        return newId
    }

    func renameList(id: UUID, to name: String) {
        guard let updated = ListStoreLogic.renameList(id: id, to: name, in: lists) else { return }
        lists = updated
        saveLists()
    }

    func deleteList(id: UUID) {
        lists = ListStoreLogic.deleteList(id: id, in: lists)
        if !lists.contains(where: { $0.id == activeListId }) {
            activeListId = lists.first?.id ?? InventoryListDefaults.myListId
        }
        saveLists()
        saveActiveListId()
    }

    func addProduct(_ product: InventoryProduct, toListId: UUID) {
        let item = InventoryListItem(product: product)
        lists = ListStoreLogic.addItem(item, toListId: toListId, in: lists)
        saveLists()
    }

    func deleteItems(at offsets: IndexSet) {
        guard let listIndex = lists.firstIndex(where: { $0.id == activeListId }) else { return }
        lists[listIndex].items = ListStoreLogic.deleteItems(at: offsets, in: lists[listIndex].items)
        saveLists()
    }

    func deleteAllActiveItems() {
        guard let listIndex = lists.firstIndex(where: { $0.id == activeListId }) else { return }
        lists[listIndex].items = []
        saveLists()
    }

    func incrementPullCount(for item: InventoryListItem) {
        mutateActiveItems { ListStoreLogic.incrementPullCount(for: item.id, in: $0) }
    }

    func decrementPullCount(for item: InventoryListItem) {
        mutateActiveItems { ListStoreLogic.decrementPullCount(for: item.id, in: $0) }
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

    private func mutateActiveItems(_ transform: ([InventoryListItem]) -> [InventoryListItem]) {
        guard let listIndex = lists.firstIndex(where: { $0.id == activeListId }) else { return }
        lists[listIndex].items = transform(lists[listIndex].items)
        saveLists()
    }

    private func loadLists() {
        let savedLists: [InventoryNamedList]? = {
            guard let data = userDefaults.data(forKey: listsKey) else { return nil }
            return try? JSONDecoder().decode([InventoryNamedList].self, from: data)
        }()
        lists = ListStoreLogic.bootstrapLists(savedLists)
        activeListId = ListStoreLogic.resolveActiveListId(
            saved: userDefaults.string(forKey: activeListIdKey),
            in: lists
        )
        saveLists()
        saveActiveListId()
    }

    private func saveLists() {
        guard let encoded = try? JSONEncoder().encode(lists) else { return }
        userDefaults.set(encoded, forKey: listsKey)
    }

    private func saveActiveListId() {
        userDefaults.set(activeListId.uuidString, forKey: activeListIdKey)
    }
}
