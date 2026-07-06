import SwiftUI

struct ListOperationsView: View {
    @EnvironmentObject private var viewModel: InventoryLookupViewModel
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable {
        case union = "Union"
        case diff = "Diff"
        case split = "Split"
        case sort = "Sort"
        case listQuery = "Query"
    }

    @State private var mode: Mode = .union

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .listerSegmentedPicker()
                .padding()
                .background(Color.listerBackground)

                switch mode {
                case .union:
                    UnionOperationView()
                        .environmentObject(viewModel)
                case .diff:
                    DiffOperationView()
                        .environmentObject(viewModel)
                case .split:
                    SplitOperationView()
                        .environmentObject(viewModel)
                case .sort:
                    SortOperationView()
                        .environmentObject(viewModel)
                case .listQuery:
                    ListQueryOperationView()
                        .environmentObject(viewModel)
                }
            }
            .background(Color.listerBackground)
            .navigationTitle("List Operations")
            .listerNavigationBar()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Union

private struct UnionOperationView: View {
    @EnvironmentObject private var viewModel: InventoryLookupViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIds: Set<UUID> = []
    @State private var customName = ""

    private var canCreate: Bool { selectedIds.count >= 2 }

    private var totalItems: Int {
        var productIds = Set<Int>()
        for id in selectedIds {
            guard let list = viewModel.lists.first(where: { $0.id == id }) else { continue }
            productIds.formUnion(list.items.map(\.productId))
        }
        return productIds.count
    }

    private var generatedName: String {
        viewModel.lists
            .filter { selectedIds.contains($0.id) }
            .map(\.name)
            .joined(separator: "-")
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(viewModel.lists) { list in
                        let isSelected = selectedIds.contains(list.id)
                        Button {
                            if isSelected {
                                selectedIds.remove(list.id)
                            } else {
                                selectedIds.insert(list.id)
                            }
                            customName = generatedName
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
                    Text("Select lists to combine (pick 2 or more)")
                        .foregroundStyle(Color.listerPrimary)
                        .fontWeight(.semibold)
                }

                if canCreate {
                    Section {
                        TextField("List name", text: $customName)
                            .autocorrectionDisabled()
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text("\(totalItems) unique item\(totalItems == 1 ? "" : "s") (pull counts summed)")
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

            if canCreate {
                Button {
                    let finalName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                    viewModel.unionLists(
                        ids: Array(selectedIds),
                        into: finalName.isEmpty ? generatedName : finalName
                    )
                    dismiss()
                } label: {
                    Text("Create Union List")
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
}

// MARK: - Diff

private struct DiffOperationView: View {
    @EnvironmentObject private var viewModel: InventoryLookupViewModel

    @State private var listAId: UUID?
    @State private var listBId: UUID?
    @State private var result: ListDiffResult?

    private var canRun: Bool {
        guard let a = listAId, let b = listBId else { return false }
        return a != b
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker(selection: $listAId, label: EmptyView()) {
                        Text("Select…").tag(UUID?.none)
                        ForEach(viewModel.lists) { list in
                            Text(list.name).tag(UUID?.some(list.id))
                        }
                    }
                    .pickerStyle(.menu)

                    Picker(selection: $listBId, label: EmptyView()) {
                        Text("Select…").tag(UUID?.none)
                        ForEach(viewModel.lists) { list in
                            Text(list.name).tag(UUID?.some(list.id))
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Pick 2 lists to Compare")
                        .foregroundStyle(Color.listerPrimary)
                        .fontWeight(.semibold)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.listerBackground)
            .frame(maxHeight: 180)

            Button {
                guard let a = listAId, let b = listBId else { return }
                result = viewModel.diffLists(aId: a, bId: b)
            } label: {
                Text("Run Diff")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 45)
                    .background(canRun ? Color.listerAccent : Color.listerAccent.opacity(0.4))
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .disabled(!canRun)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.listerBackground)

            if let result {
                List {
                    DiffSection(title: "Common (\(result.common.count))", items: result.common)
                    DiffSection(
                        title: "Only in \(result.listAName) (\(result.onlyInA.count))",
                        items: result.onlyInA
                    )
                    DiffSection(
                        title: "Only in \(result.listBName) (\(result.onlyInB.count))",
                        items: result.onlyInB
                    )
                }
                .scrollContentBackground(.hidden)
                .background(Color.listerBackground)
            } else {
                Spacer()
            }
        }
        .background(Color.listerBackground)
    }
}

private struct DiffSection: View {
    let title: String
    let items: [InventoryListItem]

    var body: some View {
        Section {
            if items.isEmpty {
                Text("No items")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .listRowBackground(Color.listerBackground)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name.isEmpty ? "\(item.productId)" : item.name)
                            .font(.subheadline)
                        HStack(spacing: 8) {
                            Text("\(item.productId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontDesign(.monospaced)
                            if let productType = item.productType, !productType.isEmpty {
                                Text(productType)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowBackground(Color.listerBackground)
                }
            }
        } header: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.listerPrimary)
                    .frame(width: 8, height: 8)
                Text(title)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.listerPrimary)
            }
        }
    }
}

// MARK: - Split

private struct SplitOperationView: View {
    @EnvironmentObject private var viewModel: InventoryLookupViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.selectedTab) private var selectedTab

    enum SplitBy: String, CaseIterable {
        case numberOfLists = "Number of Lists"
        case itemsPerList = "Items per List"
    }

    @State private var selectedListId: UUID?
    @State private var splitBy: SplitBy = .numberOfLists
    @State private var splitValue = 3
    @State private var prefix = ""

    private var selectedList: InventoryNamedList? {
        guard let id = selectedListId else { return nil }
        return viewModel.lists.first { $0.id == id }
    }

    private var previewChunks: (count: Int, sizes: [Int]) {
        guard let list = selectedList, !list.items.isEmpty else { return (0, []) }
        let total = list.items.count
        let n = max(1, splitValue)
        let chunkSize: Int
        switch splitBy {
        case .numberOfLists:
            chunkSize = Int(ceil(Double(total) / Double(n)))
        case .itemsPerList:
            chunkSize = n
        }
        var sizes: [Int] = []
        var offset = 0
        while offset < total {
            sizes.append(min(chunkSize, total - offset))
            offset += chunkSize
        }
        return (sizes.count, sizes)
    }

    private var canRun: Bool {
        guard let list = selectedList else { return false }
        return !list.items.isEmpty && splitValue >= 1
    }

    private var effectivePrefix: String {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (selectedList?.name ?? "List") : trimmed
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(viewModel.lists) { list in
                        let isSelected = selectedListId == list.id
                        Button {
                            selectedListId = list.id
                            prefix = list.name
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
                    Text("Select list to split")
                        .foregroundStyle(Color.listerPrimary)
                        .fontWeight(.semibold)
                }

                if selectedList != nil {
                    Section {
                        Picker("Split by", selection: $splitBy) {
                            ForEach(SplitBy.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        .listerSegmentedPicker()
                        .listRowBackground(Color.listerBackground)

                        HStack {
                            Text(splitBy == .numberOfLists ? "Lists" : "Items / list")
                            Spacer()
                            Stepper("\(splitValue)", value: $splitValue, in: 1...999)
                                .fixedSize()
                        }
                        .listRowBackground(Color.listerBackground.opacity(0.5))

                        HStack {
                            Text("Prefix")
                            TextField("e.g. MyList", text: $prefix)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(Color.listerAccent)
                        }
                        .listRowBackground(Color.listerBackground.opacity(0.5))

                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text("Lists will be named \(effectivePrefix)-1, -2, …")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.listerBackground)
                    } header: {
                        Text("Split Options")
                            .foregroundStyle(Color.listerPrimary)
                            .fontWeight(.semibold)
                    }

                    if previewChunks.count > 0 {
                        Section {
                            ForEach(Array(previewChunks.sizes.enumerated()), id: \.offset) { idx, size in
                                HStack {
                                    Image(systemName: "list.bullet")
                                        .foregroundStyle(Color.listerAccent)
                                        .font(.caption)
                                    Text("\(effectivePrefix)-\(idx + 1)")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(size) item\(size == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .listRowBackground(
                                    idx % 2 == 0
                                        ? Color.listerHighlight.opacity(0.4)
                                        : Color.listerBackground.opacity(0.5)
                                )
                            }
                        } header: {
                            Text("Preview — \(previewChunks.count) list\(previewChunks.count == 1 ? "" : "s")")
                                .foregroundStyle(Color.listerPrimary)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.listerBackground)

            if canRun {
                Button {
                    guard let id = selectedListId else { return }
                    let mode: ListStoreLogic.SplitMode = splitBy == .numberOfLists
                        ? .byNumberOfLists(splitValue)
                        : .byItemsPerList(splitValue)
                    viewModel.splitList(id: id, mode: mode, prefix: prefix)
                    selectedTab.wrappedValue = 2
                    dismiss()
                } label: {
                    Text("Split List")
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
}

// MARK: - Sort

private struct SortOperationView: View {
    @EnvironmentObject private var viewModel: InventoryLookupViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.selectedTab) private var selectedTab

    @State private var selectedListId: UUID?
    @State private var sortField: ListSortField = .name
    @State private var ascending = true

    private var selectedList: InventoryNamedList? {
        guard let id = selectedListId else { return nil }
        return viewModel.lists.first { $0.id == id }
    }

    private var previewItems: [InventoryListItem] {
        guard let list = selectedList else { return [] }
        return ListSortLogic.sorted(list.items, by: sortField, ascending: ascending)
    }

    private var canRun: Bool {
        guard let list = selectedList else { return false }
        return !list.items.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(viewModel.lists) { list in
                        let isSelected = selectedListId == list.id
                        Button {
                            selectedListId = list.id
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
                    Text("Select list to sort")
                        .foregroundStyle(Color.listerPrimary)
                        .fontWeight(.semibold)
                }

                if selectedList != nil {
                    Section {
                        Picker("Sort by", selection: $sortField) {
                            ForEach(ListSortField.allCases) { field in
                                Text(field.rawValue).tag(field)
                            }
                        }
                        .pickerStyle(.menu)
                        .listRowBackground(Color.listerBackground.opacity(0.5))

                        Picker("Order", selection: $ascending) {
                            Text("Ascending").tag(true)
                            Text("Descending").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .listerSegmentedPicker()
                        .listRowBackground(Color.listerBackground)
                    } header: {
                        Text("Sort Options")
                            .foregroundStyle(Color.listerPrimary)
                            .fontWeight(.semibold)
                    }

                    if !previewItems.isEmpty {
                        Section {
                            ForEach(Array(previewItems.prefix(5).enumerated()), id: \.element.id) { index, item in
                                HStack {
                                    Text("\(index + 1).")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name.isEmpty ? "\(item.productId)" : item.name)
                                            .font(.subheadline)
                                        Text(sortPreviewDetail(for: item))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .listRowBackground(
                                    index % 2 == 0
                                        ? Color.listerHighlight.opacity(0.4)
                                        : Color.listerBackground.opacity(0.5)
                                )
                            }
                            if previewItems.count > 5 {
                                Text("+ \(previewItems.count - 5) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .listRowBackground(Color.listerBackground)
                            }
                        } header: {
                            Text("Preview")
                                .foregroundStyle(Color.listerPrimary)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.listerBackground)

            if canRun {
                Button {
                    guard let id = selectedListId else { return }
                    viewModel.sortList(id: id, by: sortField, ascending: ascending)
                    selectedTab.wrappedValue = 2
                    dismiss()
                } label: {
                    Text("Sort List")
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

    private func sortPreviewDetail(for item: InventoryListItem) -> String {
        switch sortField {
        case .name:
            return "\(item.productId)"
        case .productType:
            return item.productType?.isEmpty == false ? item.productType! : "—"
        case .productId:
            return item.name
        case .barcode:
            return item.barcode ?? "—"
        case .price:
            return item.priceLabel
        case .stock:
            return item.stockLabel
        case .pullCount:
            return "Pull: \(item.pullCount)"
        }
    }
}

#if DEBUG
#Preview {
    ListOperationsView()
        .environmentObject(InventoryLookupViewModel())
}
#endif
