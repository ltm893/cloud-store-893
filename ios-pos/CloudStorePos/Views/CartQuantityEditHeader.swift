import SwiftUI

struct CartQuantityEditHeader: View {
    let itemName: String
    let quantityInput: String
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Cancel", action: onCancel)
                    .font(.subheadline)
                    .foregroundStyle(PosColors.burgundy)
                    .buttonStyle(.plain)
                Spacer()
                Text("Quantity")
                    .font(.subheadline.bold())
                    .foregroundStyle(PosColors.burgundy)
                Spacer()
                    .frame(width: 44)
            }

            Text(itemName)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            if !quantityInput.isEmpty {
                Text(quantityInput)
                    .font(.title3.bold())
                    .foregroundStyle(PosColors.burgundy)
            }

            Button("Set Quantity", action: onApply)
                .buttonStyle(PosTealButtonStyle())
                .disabled(quantityInput.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.85))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(PosColors.panelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 6)
    }
}
