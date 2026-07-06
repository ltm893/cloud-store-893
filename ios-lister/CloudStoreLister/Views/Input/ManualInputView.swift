import SwiftUI

struct ManualInputView: View {
    @EnvironmentObject private var viewModel: InventoryLookupViewModel
    @Environment(\.selectedTab) private var selectedTab

    var body: some View {
        VStack(spacing: 16) {
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
                selectedTab.wrappedValue = 1
            }
            .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.listerBackground)
        .navigationTitle("Manual Entry")
        .listerNavigationBar()
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ManualInputView()
            .environmentObject(InventoryLookupViewModel())
    }
}
#endif
