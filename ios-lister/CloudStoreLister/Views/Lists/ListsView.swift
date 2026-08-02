import SwiftUI

private struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ListsView: View {
    @EnvironmentObject private var viewModel: InventoryLookupViewModel
    @State private var showAllLists = false
    @State private var showListOperations = false
    @State private var showDeleteAllAlert = false
    @State private var shareableFile: ShareableFile?
    @State private var searchText = ""

    private var filteredItems: [InventoryListItem] {
        ListSearchLogic.filtered(viewModel.activeListItems, query: searchText)
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var listCountLabel: String {
        let items = filteredItems
        let itemCount = items.count
        let totalPull = items.reduce(0) { $0 + $1.pullCount }
        let itemsLabel = "\(itemCount) item\(itemCount == 1 ? "" : "s")"
        let pulls = "\(totalPull) pull"
        if isFiltering {
            let total = viewModel.activeListItems.count
            return "\(itemsLabel) of \(total) · \(pulls)"
        }
        return "\(itemsLabel) · \(pulls)"
    }

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.activeListItems.isEmpty {
                listCountSummary
            }

            Group {
                if viewModel.activeListItems.isEmpty {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Items you add will appear here")
                    )
                } else if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "magnifyingglass",
                        description: Text("No items match \"\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                    )
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            ListItemRow(item: item, viewModel: viewModel)
                        }
                        .onDelete(perform: deleteFilteredItems)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.listerBackground)
        .navigationTitle(viewModel.activeListName)
        .listerNavigationBar()
        .searchable(text: $searchText, prompt: "Search list")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAllLists = true } label: {
                    Image(systemName: "list.bullet.rectangle.portrait")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button { showListOperations = true } label: {
                        Label("List Operations", systemImage: "arrow.triangle.merge")
                    }
                    .disabled(!viewModel.lists.contains { !$0.items.isEmpty })
                    Button {
                        if let url = viewModel.makeCSVExportFile() {
                            shareableFile = ShareableFile(url: url)
                        }
                    } label: {
                        Label("Share as CSV", systemImage: "tablecells")
                    }
                    .disabled(viewModel.activeListItems.isEmpty)
                    Divider()
                    Button(role: .destructive) {
                        showDeleteAllAlert = true
                    } label: {
                        Label("Delete All", systemImage: "trash")
                    }
                    .disabled(viewModel.activeListItems.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showAllLists) {
            AllListsView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showListOperations) {
            ListOperationsView()
                .environmentObject(viewModel)
        }
        .sheet(item: $shareableFile) { file in
            ActivityShareSheet(items: [file.url])
        }
        .alert("Delete All Items?", isPresented: $showDeleteAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                viewModel.deleteAllActiveItems()
            }
        } message: {
            Text("Are you sure you want to delete all \(viewModel.activeListItems.count) item(s) from \(viewModel.activeListName)? This action cannot be undone.")
        }
        .onChange(of: viewModel.activeListId) { _, _ in
            searchText = ""
        }
    }

    private func deleteFilteredItems(at offsets: IndexSet) {
        let ids = Set(offsets.map { filteredItems[$0].id })
        let originalOffsets = IndexSet(
            viewModel.activeListItems.indices.filter { ids.contains(viewModel.activeListItems[$0].id) }
        )
        viewModel.deleteItems(at: originalOffsets)
    }

    private var listCountSummary: some View {
        HStack {
            Text("List Count")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.listerAccent)
            Spacer()
            Text(listCountLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.listerHighlight)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ListsView()
            .environmentObject(InventoryLookupViewModel())
    }
}
#endif
