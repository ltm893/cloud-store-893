import SwiftUI

struct ListItemRow: View {
    let item: InventoryListItem
    @ObservedObject var viewModel: InventoryLookupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProductFieldRow(label: "Name:", value: item.name, valueFont: .headline)
            Divider()
            ProductFieldRow(
                label: "Type:",
                value: item.productType?.isEmpty == false ? item.productType! : "—"
            )
            Divider()
            ProductFieldRow(label: "Product ID:", value: "\(item.productId)")
            Divider()
            ProductFieldRow(label: "Price:", value: item.priceLabel)
            Divider()
            HStack {
                Text("Stock:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(item.stockLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.stockEmphasis ? .red : .primary)
            }
            Divider()
            HStack {
                Text("Pull Count:")
                    .font(.subheadline)
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        viewModel.decrementPullCount(for: item)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.listerAccent)
                    }
                    .buttonStyle(.plain)
                    Text("\(item.pullCount)")
                        .font(.title3.weight(.bold))
                        .frame(minWidth: 30)
                    Button {
                        viewModel.incrementPullCount(for: item)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.listerAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.listerHighlight)
        .cornerRadius(10)
        .colorScheme(.light)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                if let index = viewModel.activeListItems.firstIndex(where: { $0.id == item.id }) {
                    viewModel.deleteItems(at: IndexSet([index]))
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
