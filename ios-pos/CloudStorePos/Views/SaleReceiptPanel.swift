import SwiftUI

struct SaleReceiptContent: View {
    let receipt: SaleReceiptInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Receipt")
                .font(.subheadline.bold())
                .foregroundStyle(PosColors.burgundy)

            Text(receipt.orderLabel)
                .font(.subheadline.weight(.semibold))

            Text(receipt.formattedTimestamp())
                .font(.caption)
                .foregroundStyle(.secondary)

            if receipt.queuedOffline {
                Text("Will sync when back online")
                    .font(.caption)
                    .foregroundStyle(PosColors.teal)
            }

            if let customerName = receipt.customerName {
                Text(customerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(receipt.lines.enumerated()), id: \.offset) { _, line in
                        ReceiptLineRow(line: line)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                Divider()
                    .overlay(PosColors.panelBorder.opacity(0.35))
                VStack(alignment: .leading, spacing: 2) {
                    ReceiptTotalsSection(receipt: receipt)
                    if !receipt.payments.isEmpty {
                        ReceiptPaymentsSection(receipt: receipt)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.45))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ReceiptActionPanel: View {
    let onPrint: () -> Void
    var printEnabled: Bool = true

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Button("Print Receipt") { onPrint() }
                .buttonStyle(PosFullWidthButtonStyle())
                .disabled(!printEnabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReceiptLineRow: View {
    let line: ReceiptLine

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(line.quantity) × \(line.name)")
                    .font(.subheadline)
                Text("ID \(line.productId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(CartTotalsLogic.formatMoney(line.lineTotal))
                .font(.subheadline.weight(.medium))
        }
    }
}

private struct ReceiptTotalsSection: View {
    let receipt: SaleReceiptInfo

    var body: some View {
        ReceiptTotalRow(label: "Items", value: "\(receipt.itemCount)")
        ReceiptTotalRow(label: "Subtotal", value: CartTotalsLogic.formatMoney(receipt.subtotal))
        ReceiptTotalRow(
            label: "Savings",
            value: receipt.savings > 0.005
                ? "−\(CartTotalsLogic.formatMoney(receipt.savings))"
                : CartTotalsLogic.formatMoney(0)
        )
        ReceiptTotalRow(label: "Tax", value: CartTotalsLogic.formatMoney(receipt.tax))
        if receipt.grandTotal - receipt.collectedTotal > 0.005 {
            ReceiptTotalRow(
                label: "Cash rounding",
                value: "−\(CartTotalsLogic.formatMoney(receipt.grandTotal - receipt.collectedTotal))"
            )
        }
        ReceiptTotalRow(
            label: receipt.grandTotal - receipt.collectedTotal > 0.005 ? "Collected" : "Total",
            value: CartTotalsLogic.formatMoney(receipt.collectedTotal),
            emphasize: true
        )
        if receipt.grandTotal - receipt.collectedTotal > 0.005 {
            ReceiptTotalRow(
                label: "Register total",
                value: CartTotalsLogic.formatMoney(receipt.grandTotal)
            )
        }
    }
}

private struct ReceiptPaymentsSection: View {
    let receipt: SaleReceiptInfo

    var body: some View {
        Text("Payment")
            .font(.caption.weight(.semibold))
            .foregroundStyle(PosColors.burgundy)
            .padding(.top, 6)

        ForEach(Array(receipt.payments.enumerated()), id: \.offset) { _, payment in
            let tendered = payment.tenderedAmount ?? payment.amount
            Text("\(CheckoutPaymentLogic.paymentMethodLabel(payment.method)) \(CartTotalsLogic.formatMoney(tendered))")
                .font(.caption)
            if let change = payment.changeGiven, change > 0.005 {
                Text("Change \(CartTotalsLogic.formatMoney(change))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if receipt.changeTotal > 0.005,
           !receipt.payments.contains(where: { ($0.changeGiven ?? 0) > 0.005 }) {
            Text("Change \(CartTotalsLogic.formatMoney(receipt.changeTotal))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ReceiptTotalRow: View {
    let label: String
    let value: String
    var emphasize: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(emphasize ? .subheadline : .caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(emphasize ? .subheadline.bold() : .caption.weight(.medium))
                .foregroundStyle(emphasize ? PosColors.burgundy : .primary)
        }
        .padding(.vertical, 1)
    }
}
