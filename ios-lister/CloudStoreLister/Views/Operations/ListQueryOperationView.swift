import SwiftUI

struct ListQueryOperationView: View {
    @EnvironmentObject private var viewModel: InventoryLookupViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.selectedTab) private var selectedTab

    @State private var selectedListId: UUID?
    @State private var customName = ""
    @State private var isRunning = false
    @State private var queryCurrent = 0
    @State private var queryTotal = 0
    @State private var queryTask: Task<Void, Never>?

    private var selectedList: InventoryNamedList? {
        guard let id = selectedListId else { return nil }
        return viewModel.lists.first { $0.id == id }
    }

    private var canRun: Bool {
        guard let list = selectedList else { return false }
        return !list.items.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(Color.listerAccent)
                            .font(.caption)
                            .padding(.top, 2)
                        Text("Re-queries each item by product ID via the Cloud Store API. Pull counts are preserved; name, price, and stock are refreshed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.listerBackground)
                } header: {
                    Text("List Query")
                        .foregroundStyle(Color.listerPrimary)
                        .fontWeight(.semibold)
                }

                Section {
                    ForEach(viewModel.lists) { list in
                        let isSelected = selectedListId == list.id
                        Button {
                            selectedListId = list.id
                            customName = "\(list.name)-BQ"
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isSelected ? Color.listerAccent : Color.listerHighlight)
                                    .frame(width: 4, height: 36)
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.listerAccent : .secondary)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(list.name)
                                        .foregroundStyle(isSelected ? Color.listerAccent : .primary)
                                        .fontWeight(isSelected ? .semibold : .regular)
                                    Text("\(list.items.count) item\(list.items.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .listRowBackground(
                            isSelected ? Color.listerHighlight : Color.listerBackground.opacity(0.5)
                        )
                    }
                } header: {
                    Text("Select list to re-query")
                        .foregroundStyle(Color.listerPrimary)
                        .fontWeight(.semibold)
                }

                if selectedList != nil {
                    Section {
                        TextField("List name", text: $customName)
                            .autocorrectionDisabled()
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text("Creates a new list with fresh stock and price data")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Result List")
                            .foregroundStyle(Color.listerPrimary)
                            .fontWeight(.semibold)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.listerBackground)

            if isRunning {
                VStack(spacing: 12) {
                    ProgressView(value: Double(queryCurrent), total: Double(max(queryTotal, 1)))
                        .padding(.horizontal, 24)
                    Text("Querying \(queryCurrent) of \(queryTotal)…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        queryTask?.cancel()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 45)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                }
                .padding()
                .background(Color.listerBackground)
            } else if canRun {
                Button {
                    queryTask = Task {
                        await runListQuery()
                        queryTask = nil
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Run List Query")
                    }
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 45)
                    .background(Color.listerAccent)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .padding()
                .background(Color.listerBackground)
            }
        }
        .background(Color.listerBackground)
    }

    @MainActor
    private func runListQuery() async {
        guard let sourceListId = selectedListId else { return }

        isRunning = true
        queryTotal = selectedList?.items.count ?? 0
        queryCurrent = 0

        await viewModel.batchListQuery(
            sourceListId: sourceListId,
            resultName: customName
        ) { completed, total in
            queryCurrent = completed
            queryTotal = total
        }

        isRunning = false
        if queryCurrent > 0 {
            selectedTab.wrappedValue = 2
            dismiss()
        }
    }
}

#if DEBUG
#Preview {
    ListQueryOperationView()
        .environmentObject(InventoryLookupViewModel())
}
#endif
