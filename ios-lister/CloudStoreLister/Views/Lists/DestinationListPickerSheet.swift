import SwiftUI

enum ItemTransferMode {
    case copy
    case move

    var title: String {
        switch self {
        case .copy: return "Copy to List"
        case .move: return "Move to List"
        }
    }

    var emptyMessage: String {
        switch self {
        case .copy: return "Create another list to copy this item into."
        case .move: return "Create another list to move this item into."
        }
    }
}

extension ItemTransferMode: Identifiable {
    var id: String {
        switch self {
        case .copy: return "copy"
        case .move: return "move"
        }
    }
}

/// Picks a destination list for copy/move. Excludes the current (source) list.
struct DestinationListPickerSheet: View {
    @ObservedObject var viewModel: InventoryLookupViewModel
    @Environment(\.dismiss) private var dismiss

    let item: InventoryListItem
    let mode: ItemTransferMode

    private var destinations: [InventoryNamedList] {
        viewModel.lists.filter { $0.id != viewModel.activeListId }
    }

    var body: some View {
        NavigationStack {
            Group {
                if destinations.isEmpty {
                    ContentUnavailableView(
                        "No Other Lists",
                        systemImage: "tray",
                        description: Text(mode.emptyMessage)
                    )
                } else {
                    List {
                        Section {
                            ForEach(destinations) { list in
                                Button {
                                    apply(to: list)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: mode == .copy
                                              ? "doc.on.doc"
                                              : "arrow.right.doc.on.clipboard")
                                            .foregroundStyle(Color.listerAccent)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(list.name)
                                                .foregroundStyle(.primary)
                                                .fontWeight(.medium)
                                            Text("\(list.items.count) item\(list.items.count == 1 ? "" : "s")")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .listRowBackground(Color.listerBackground.opacity(0.5))
                            }
                        } header: {
                            Text(mode == .copy
                                 ? "Copy “\(item.displayName)” to"
                                 : "Move “\(item.displayName)” to")
                                .foregroundStyle(Color.listerPrimary)
                                .fontWeight(.semibold)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.listerBackground)
            .navigationTitle(mode.title)
            .listerNavigationBar()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func apply(to list: InventoryNamedList) {
        switch mode {
        case .copy: _ = viewModel.copyItem(item, toListId: list.id)
        case .move: _ = viewModel.moveItem(item, toListId: list.id)
        }
        dismiss()
    }
}

private extension InventoryListItem {
    var displayName: String {
        name.isEmpty ? "\(productId)" : name
    }
}
