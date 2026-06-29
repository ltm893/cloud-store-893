import SwiftUI

struct InventoryLookupView: View {
    @StateObject private var viewModel = InventoryLookupViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                resultSection
                    .frame(maxHeight: .infinity, alignment: .top)

                Text(viewModel.inputText.isEmpty ? "Enter ID or barcode" : viewModel.inputText)
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(Color.listerHighlight)
                    .cornerRadius(10)
                    .colorScheme(.light)
                    .padding(.horizontal)

                NumericKeypadGrid(inputText: $viewModel.inputText) {
                    viewModel.lookup()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                Text(AppConfig.apiHostLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.listerBackground)
            .navigationTitle("Inventory")
            .listerNavigationBar()
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if viewModel.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Looking up…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            ContentUnavailableView(
                viewModel.lastQuery.isEmpty ? "Lookup" : "No result for \(viewModel.lastQuery)",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if let product = viewModel.product {
            ScrollView {
                ProductCardView(product: product)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
        } else {
            ContentUnavailableView(
                "Product lookup",
                systemImage: "barcode.viewfinder",
                description: Text("Enter a product ID or barcode on the keypad.")
            )
        }
    }
}

#if DEBUG
#Preview {
    InventoryLookupView()
}
#endif
