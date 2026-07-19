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

    var activeListSummary: ListExportLogic.Summary {
        ListExportLogic.summary(for: activeListItems)
    }

    func makeCSVExportFile() -> URL? {
        ListExportLogic.writeCSVFile(items: activeListItems, listName: activeListName)
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

    func importCSVItems(_ items: [InventoryListItem], toListId: UUID) {
        lists = CSVImportLogic.applyImport(items: items, toListId: toListId, in: lists)
        activeListId = toListId
        saveLists()
        saveActiveListId()
    }

    func submitLookup(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter product ID or barcode"
            return
        }
        inputText = trimmed
        Task { await performLookup(query: trimmed) }
    }

    func unionLists(ids: [UUID], into newName: String) {
        guard let (updated, newId) = ListStoreLogic.unionLists(ids: ids, into: newName, in: lists) else { return }
        lists = updated
        activeListId = newId
        saveLists()
        saveActiveListId()
    }

    func diffLists(aId: UUID, bId: UUID) -> ListDiffResult? {
        ListStoreLogic.diffLists(aId: aId, bId: bId, in: lists)
    }

    func splitList(id: UUID, mode: ListStoreLogic.SplitMode, prefix: String) {
        guard let (updated, newId) = ListStoreLogic.splitList(id: id, mode: mode, prefix: prefix, in: lists) else { return }
        lists = updated
        activeListId = newId
        saveLists()
        saveActiveListId()
    }

    func sortList(id: UUID, by field: ListSortField, ascending: Bool) {
        guard let updated = ListSortLogic.sortList(id: id, by: field, ascending: ascending, in: lists) else { return }
        lists = updated
        activeListId = id
        saveLists()
        saveActiveListId()
    }

    /// Re-queries each item in the source list by product ID and writes results to a new list.
    func batchListQuery(
        sourceListId: UUID,
        resultName: String,
        courtesyDelayMs: ClosedRange<Int> = 300...800,
        onProgress: @escaping (_ completed: Int, _ total: Int) -> Void
    ) async {
        guard let source = lists.first(where: { $0.id == sourceListId }),
              !source.items.isEmpty else { return }

        let finalName = ListStoreLogic.uniqueListName(
            ListQueryLogic.resultListName(sourceName: source.name, customName: resultName),
            existing: lists
        )
        let (createdLists, targetId) = ListStoreLogic.createList(name: finalName, in: lists)
        lists = createdLists
        activeListId = targetId
        saveLists()
        saveActiveListId()

        let sourceItems = source.items
        var results: [InventoryListItem] = []

        for (index, item) in sourceItems.enumerated() {
            if Task.isCancelled { break }
            if index > 0 {
                let delayMs = Int.random(in: courtesyDelayMs)
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }

            let refreshed: InventoryListItem
            do {
                let product = try await api.lookup(productId: item.productId)
                refreshed = item.refreshed(from: product)
            } catch {
                refreshed = item.withLookupFailure(error.localizedDescription)
            }

            results.append(refreshed)
            lists = ListQueryLogic.setItems(results, forListId: targetId, in: lists)
            saveLists()
            onProgress(index + 1, sourceItems.count)
        }
    }

    func deleteItems(at offsets: IndexSet) {
        guard let listIndex = lists.firstIndex(where: { $0.id == activeListId }) else { return }
        lists[listIndex].items = ListStoreLogic.deleteItems(at: offsets, in: lists[listIndex].items)
        saveLists()
    }

    @discardableResult
    func copyItem(_ item: InventoryListItem, toListId: UUID) -> Bool {
        guard let updated = ListStoreLogic.copyItem(
            item,
            fromActiveListId: activeListId,
            toListId: toListId,
            in: lists
        ) else { return false }
        lists = updated
        saveLists()
        return true
    }

    @discardableResult
    func moveItem(_ item: InventoryListItem, toListId: UUID) -> Bool {
        guard let updated = ListStoreLogic.moveItem(
            item,
            fromActiveListId: activeListId,
            toListId: toListId,
            in: lists
        ) else { return false }
        lists = updated
        saveLists()
        return true
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
