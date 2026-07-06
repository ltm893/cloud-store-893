import SwiftUI

private enum InputDestination: Hashable {
    case manual
    case barcode
}

struct LookupInputView: View {
    @EnvironmentObject private var viewModel: InventoryLookupViewModel
    @State private var showCSVImport = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            NavigationLink(value: InputDestination.barcode) {
                inputButtonLabel("Barcode Scanner", systemImage: "barcode.viewfinder")
            }
            .padding(.horizontal)

            NavigationLink(value: InputDestination.manual) {
                inputButtonLabel("Manual", systemImage: "123.rectangle")
            }
            .padding(.horizontal)

            Button {
                showCSVImport = true
            } label: {
                inputButtonLabel("Import CSV", systemImage: "doc.text")
            }
            .padding(.horizontal)

            Spacer()

            Text(AppConfig.apiHostLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.listerBackground)
        .navigationTitle("Search Input")
        .listerNavigationBar()
        .navigationDestination(for: InputDestination.self) { destination in
            switch destination {
            case .manual:
                ManualInputView()
            case .barcode:
                BarcodeScannerView()
            }
        }
        .sheet(isPresented: $showCSVImport) {
            CSVImportView()
                .environmentObject(viewModel)
        }
    }

    private func inputButtonLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title2)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.listerPrimary)
            .foregroundStyle(.white)
            .cornerRadius(10)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        LookupInputView()
            .environmentObject(InventoryLookupViewModel())
    }
}
#endif
