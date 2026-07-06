import SwiftUI

struct LookupResultsView: View {
    @EnvironmentObject private var viewModel: InventoryLookupViewModel
    @Environment(\.selectedTab) private var selectedTab

    @State private var targetListId: UUID?
    @State private var showNewListAlert = false
    @State private var newListName = ""

    private var effectiveTargetListId: UUID {
        targetListId ?? viewModel.activeListId
    }

    private var targetListName: String {
        viewModel.lists.first { $0.id == effectiveTargetListId }?.name ?? viewModel.activeListName
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Looking up…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView(
                    viewModel.lastQuery.isEmpty ? "No Results" : "No Results for \(viewModel.lastQuery)",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if let product = viewModel.product {
                VStack(spacing: 0) {
                    ScrollView {
                        ProductCardView(product: product)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                    addToListBar(product: product)
                }
            } else {
                ContentUnavailableView(
                    viewModel.lastQuery.isEmpty
                        ? "No Results"
                        : "No Results for \(viewModel.lastQuery)",
                    systemImage: "magnifyingglass",
                    description: Text("Enter a product ID or barcode on the Input tab.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.listerBackground)
        .navigationTitle("Results")
        .listerNavigationBar()
        .alert("New List", isPresented: $showNewListAlert) {
            TextField("List name", text: $newListName)
            Button("Create") {
                let newId = viewModel.createList(name: newListName)
                targetListId = newId
                newListName = ""
            }
            Button("Cancel", role: .cancel) { newListName = "" }
        } message: {
            Text("Enter a name for the new list")
        }
        .onChange(of: viewModel.activeListId) { _, _ in
            targetListId = nil
        }
    }

    private func addToListBar(product: InventoryProduct) -> some View {
        HStack(spacing: 10) {
            Button {
                viewModel.addProduct(product, toListId: effectiveTargetListId)
                selectedTab.wrappedValue = 2
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add to List")
                }
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 45)
                .background(Color.listerAccent)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }

            Menu {
                ForEach(viewModel.lists) { list in
                    Button {
                        targetListId = list.id
                    } label: {
                        HStack {
                            Text(list.name)
                            if list.id == effectiveTargetListId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button {
                    showNewListAlert = true
                } label: {
                    Label("New List…", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 4) {
                    Text("List:")
                        .font(.subheadline)
                    Text(targetListName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 45)
                .background(Color.listerPrimary)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.listerBackground)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        LookupResultsView()
            .environmentObject(InventoryLookupViewModel())
    }
}
#endif
