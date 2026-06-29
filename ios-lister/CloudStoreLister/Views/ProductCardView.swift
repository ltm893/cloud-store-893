import SwiftUI

struct ProductCardView: View {
    let product: InventoryProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProductFieldRow(label: "Name:", value: product.name, valueFont: .headline)
            Divider()
            ProductFieldRow(
                label: "Type:",
                value: product.productType?.isEmpty == false ? product.productType! : "—"
            )
            Divider()
            ProductFieldRow(
                label: "Manufacturer:",
                value: product.manufacturer?.isEmpty == false ? product.manufacturer! : "—"
            )
            Divider()
            ProductFieldRow(label: "Product ID:", value: "\(product.id)")
            Divider()
            ProductFieldRow(
                label: "Barcode:",
                value: product.barcode?.isEmpty == false ? product.barcode! : "—"
            )
            Divider()
            ProductFieldRow(
                label: "Price:",
                value: InventoryDisplayLogic.priceDetail(
                    regularPrice: product.regularPrice,
                    onSale: product.onSale,
                    salePrice: product.salePrice
                )
            )
            Divider()
            HStack {
                Text("Stock:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    InventoryDisplayLogic.stockLabel(
                        trackInventory: product.trackInventory,
                        quantityOnHand: product.quantityOnHand,
                        inStock: product.inStock,
                        lowStock: product.lowStock
                    )
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(product.lowStock || !product.inStock ? .red : .primary)
            }
            if product.trackInventory, let reorder = product.reorderPoint {
                Divider()
                ProductFieldRow(label: "Reorder at:", value: "\(reorder)")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.listerHighlight)
        .cornerRadius(10)
        .colorScheme(.light)
    }
}

private struct ProductFieldRow: View {
    let label: String
    let value: String
    var valueFont: Font = .subheadline

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(valueFont)
                .multilineTextAlignment(.trailing)
        }
    }
}
