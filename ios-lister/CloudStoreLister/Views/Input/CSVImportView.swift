import SwiftUI
import UniformTypeIdentifiers

private enum CSVImportDestination: String, CaseIterable, Identifiable {
    case existing = "Existing List"
    case newList = "New List"

    var id: String { rawValue }
}

struct CSVImportView: View {
    @EnvironmentObject private var viewModel: InventoryLookupViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.selectedTab) private var selectedTab

    @State private var destination: CSVImportDestination = .existing
    @State private var selectedListId: UUID?
    @State private var newListName = ""
    @State private var isFilePickerPresented = false
    @State private var parsedCSV: ParsedCSV?
    @State private var mapping = CSVFieldMapping()
    @State private var errorMessage: String?
    @State private var importedCount = 0

    private var effectiveListId: UUID {
        selectedListId ?? viewModel.activeListId
    }

    private var targetListName: String {
        switch destination {
        case .existing:
            return viewModel.lists.first { $0.id == effectiveListId }?.name ?? viewModel.activeListName
        case .newList:
            let trimmed = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "New List" : trimmed
        }
    }

    private var canImport: Bool {
        guard parsedCSV != nil, mapping.productIdColumn != nil else { return false }
        switch destination {
        case .existing:
            return true
        case .newList:
            return !newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Import Into", selection: $destination) {
                        ForEach(CSVImportDestination.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .listerSegmentedPicker()
                    .listRowBackground(Color.listerBackground)

                    if destination == .existing {
                        Picker("List", selection: Binding(
                            get: { effectiveListId },
                            set: { selectedListId = $0 }
                        )) {
                            ForEach(viewModel.lists) { list in
                                Text(list.name).tag(list.id)
                            }
                        }
                        .listRowBackground(Color.listerBackground.opacity(0.5))
                    } else {
                        TextField("New list name", text: $newListName)
                            .autocorrectionDisabled()
                            .listRowBackground(Color.listerBackground.opacity(0.5))
                    }

                    Button {
                        isFilePickerPresented = true
                    } label: {
                        Label(
                            parsedCSV == nil ? "Choose CSV File" : "Choose Different File",
                            systemImage: "doc.badge.plus"
                        )
                    }
                    .listRowBackground(Color.listerBackground)
                } header: {
                    Text("CSV File")
                        .foregroundStyle(Color.listerPrimary)
                        .fontWeight(.semibold)
                }

                if let parsedCSV {
                    Section {
                        Picker("Product ID", selection: Binding(
                            get: { mapping.productIdColumn ?? "" },
                            set: { mapping.productIdColumn = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("Select column…").tag("")
                            ForEach(parsedCSV.headers, id: \.self) { header in
                                Text(header).tag(header)
                            }
                        }
                        .listRowBackground(Color.listerBackground.opacity(0.5))
                    } header: {
                        Text("Required Column")
                            .foregroundStyle(Color.listerPrimary)
                            .fontWeight(.semibold)
                    } footer: {
                        Text("Product ID is required. Map it to the column that contains each item's numeric product ID.")
                    }

                    Section {
                        ForEach(CSVImportableField.optionalFields) { field in
                            optionalFieldRow(field, parsedCSV: parsedCSV)
                        }
                    } header: {
                        Text("Optional Columns")
                            .foregroundStyle(Color.listerPrimary)
                            .fontWeight(.semibold)
                    } footer: {
                        Text("Enable only the fields you want to import from the CSV. Unmapped fields use defaults (— or empty).")
                    }

                    Section {
                        Text("\(parsedCSV.rows.count) row\(parsedCSV.rows.count == 1 ? "" : "s") detected")
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.listerBackground)
                    } header: {
                        Text("Preview")
                            .foregroundStyle(Color.listerPrimary)
                            .fontWeight(.semibold)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .listRowBackground(Color.listerBackground)
                    }
                }

                if importedCount > 0 {
                    Section {
                        Text("Imported \(importedCount) item\(importedCount == 1 ? "" : "s") into \(targetListName).")
                            .foregroundStyle(Color.listerAccent)
                            .listRowBackground(Color.listerBackground)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.listerBackground)
            .navigationTitle("Import CSV")
            .listerNavigationBar()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Import") { runImport() }
                        .disabled(!canImport)
                }
            }
            .onAppear {
                if selectedListId == nil {
                    selectedListId = viewModel.activeListId
                }
            }
        }
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
    }

    @ViewBuilder
    private func optionalFieldRow(_ field: CSVImportableField, parsedCSV: ParsedCSV) -> some View {
        let isEnabled = Binding(
            get: { mapping.enabledFields.contains(field) },
            set: { enabled in
                if enabled {
                    mapping.enabledFields.insert(field)
                    if mapping.columnByField[field] == nil {
                        mapping.columnByField[field] = CSVImportLogic.guessColumn(for: field, in: parsedCSV.headers)
                            ?? parsedCSV.headers.first
                    }
                } else {
                    mapping.enabledFields.remove(field)
                    mapping.columnByField[field] = nil
                }
            }
        )

        VStack(alignment: .leading, spacing: 8) {
            Toggle(field.rawValue, isOn: isEnabled)
                .tint(Color.listerAccent)

            if mapping.enabledFields.contains(field) {
                Picker("Column", selection: Binding(
                    get: { mapping.columnByField[field] ?? "" },
                    set: { mapping.columnByField[field] = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Select column…").tag("")
                    ForEach(parsedCSV.headers, id: \.self) { header in
                        Text(header).tag(header)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .listRowBackground(Color.listerBackground.opacity(0.5))
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        errorMessage = nil
        importedCount = 0

        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Could not access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                guard let parsed = CSVImportLogic.parseCSV(content) else {
                    errorMessage = CSVImportError.emptyFile.localizedDescription
                    return
                }
                parsedCSV = parsed
                mapping = CSVImportLogic.suggestedMapping(for: parsed)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func runImport() {
        guard let parsedCSV else { return }
        errorMessage = nil

        do {
            let items = try CSVImportLogic.buildItems(parsed: parsedCSV, mapping: mapping)
            let targetId: UUID
            switch destination {
            case .existing:
                targetId = effectiveListId
            case .newList:
                targetId = viewModel.createList(name: newListName)
            }

            viewModel.importCSVItems(items, toListId: targetId)
            importedCount = items.count
            selectedTab.wrappedValue = 2
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    CSVImportView()
        .environmentObject(InventoryLookupViewModel())
}
#endif
