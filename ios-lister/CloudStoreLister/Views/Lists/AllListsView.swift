import SwiftUI

struct AllListsView: View {
    @EnvironmentObject private var viewModel: InventoryLookupViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAddList = false
    @State private var newListName = ""
    @State private var listToRename: InventoryNamedList?
    @State private var renameText = ""
    @State private var listToDelete: InventoryNamedList?
    @State private var showDeleteAlert = false

    private var isDefaultList: Bool { listToDelete?.isDefault == true }

    private var deleteAlertTitle: String {
        isDefaultList ? "Clear \(listToDelete?.name ?? "")?" : "Delete \(listToDelete?.name ?? "")?"
    }

    private var deleteAlertMessage: String {
        if isDefaultList {
            return "This will clear all \(listToDelete?.items.count ?? 0) item(s). The list itself will remain."
        }
        return "This will permanently delete \(listToDelete?.name ?? "this list") and all \(listToDelete?.items.count ?? 0) item(s) in it."
    }

    private var deleteButtonLabel: String { isDefaultList ? "Clear" : "Delete" }

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.lists) { list in
                    let isActive = list.id == viewModel.activeListId
                    Button {
                        viewModel.switchList(to: list.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isActive ? Color.listerAccent : Color.listerHighlight)
                                .frame(width: 4, height: 40)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(list.name)
                                    .foregroundStyle(isActive ? Color.listerAccent : .primary)
                                    .font(.body.weight(isActive ? .semibold : .regular))
                                Text("\(list.items.count) item\(list.items.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.listerAccent)
                                    .font(.title3)
                            }
                        }
                    }
                    .listRowBackground(
                        isActive ? Color.listerHighlight : Color.listerBackground.opacity(0.5)
                    )
                    .swipeActions(edge: .trailing) {
                        Button {
                            listToDelete = list
                            showDeleteAlert = true
                        } label: {
                            Label(list.isDefault ? "Clear" : "Delete", systemImage: "trash")
                        }
                        .tint(.red)
                        if !list.isDefault {
                            Button {
                                listToRename = list
                                renameText = list.name
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.listerBackground)
            .navigationTitle("My Lists")
            .listerNavigationBar()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddList = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New List", isPresented: $showAddList) {
                TextField("List name", text: $newListName)
                Button("Create") {
                    viewModel.createList(name: newListName)
                    newListName = ""
                    dismiss()
                }
                Button("Cancel", role: .cancel) { newListName = "" }
            } message: {
                Text("Enter a name for the new list")
            }
            .alert("Rename List", isPresented: Binding(
                get: { listToRename != nil },
                set: { if !$0 { listToRename = nil } }
            )) {
                TextField("List name", text: $renameText)
                Button("Save") {
                    if let list = listToRename {
                        viewModel.renameList(id: list.id, to: renameText)
                    }
                    listToRename = nil
                }
                Button("Cancel", role: .cancel) { listToRename = nil }
            } message: {
                Text("Enter a new name for this list")
            }
            .alert(deleteAlertTitle, isPresented: $showDeleteAlert) {
                Button(deleteButtonLabel, role: .destructive) {
                    if let list = listToDelete {
                        viewModel.deleteList(id: list.id)
                    }
                    listToDelete = nil
                }
                Button("Cancel", role: .cancel) { listToDelete = nil }
            } message: {
                Text(deleteAlertMessage)
            }
        }
    }
}

#if DEBUG
#Preview {
    AllListsView()
        .environmentObject(InventoryLookupViewModel())
}
#endif
