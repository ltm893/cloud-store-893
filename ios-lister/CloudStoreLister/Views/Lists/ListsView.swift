import SwiftUI

struct ListsView: View {
    @EnvironmentObject private var viewModel: InventoryLookupViewModel
    @State private var showAllLists = false
    @State private var showDeleteAllAlert = false

    var body: some View {
        Group {
            if viewModel.activeListItems.isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Items you add will appear here")
                )
            } else {
                List {
                    ForEach(viewModel.activeListItems) { item in
                        ListItemRow(item: item, viewModel: viewModel)
                    }
                    .onDelete { offsets in
                        viewModel.deleteItems(at: offsets)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.listerBackground)
        .navigationTitle(viewModel.activeListName)
        .listerNavigationBar()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAllLists = true } label: {
                    Image(systemName: "list.bullet.rectangle.portrait")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
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
        .alert("Delete All Items?", isPresented: $showDeleteAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                viewModel.deleteAllActiveItems()
            }
        } message: {
            Text("Are you sure you want to delete all \(viewModel.activeListItems.count) item(s) from \(viewModel.activeListName)? This action cannot be undone.")
        }
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
