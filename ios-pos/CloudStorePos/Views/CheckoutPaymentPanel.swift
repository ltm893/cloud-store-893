import SwiftUI

struct CheckoutPaymentPanel: View {
    let saleTotal: Double
    let balanceDue: Double
    let payments: [CheckoutPayment]
    let cashEnabled: Bool
    let creditOnlyPayments: Bool
    let amountInput: String
    let processingCard: Bool
    let onAmountDigit: (Character) -> Void
    let onAmountClear: () -> Void
    let onAmountBackspace: () -> Void
    let onFillRemaining: () -> Void
    let onQuickBill: (Int) -> Void
    let onApplyCash: () -> Void
    let onApplyCard: () -> Void
    let onRemovePayment: (Int) -> Void
    let onBack: () -> Void

    private var quickBills: [Int] {
        CartTotalsLogic.cashQuickDenominations(
            amountDue: balanceDue,
            cashEnabled: !creditOnlyPayments && cashEnabled
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Back", action: onBack)
                    .font(.footnote.bold())
                    .foregroundStyle(PosColors.burgundy)
                    .disabled(!payments.isEmpty)
                Spacer()
                Text("Payment")
                    .font(.headline)
                    .foregroundStyle(PosColors.burgundy)
                Spacer()
            }

            amountRow("Sale total", CartTotalsLogic.formatMoney(saleTotal))
            amountRow("Balance due", CartTotalsLogic.formatMoney(balanceDue), bold: true)
            amountRow("Entered", amountInput.isEmpty ? "—" : "$\(amountInput)")

            if !quickBills.isEmpty {
                HStack(spacing: 6) {
                    ForEach(quickBills, id: \.self) { bill in
                        Button("$\(bill)") { onQuickBill(bill) }
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Button("Exact") { onFillRemaining() }
                        .font(.caption.bold())
                }
            }

            if !payments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Payments received")
                        .font(.caption.bold())
                    ForEach(Array(payments.enumerated()), id: \.offset) { index, payment in
                        HStack {
                            Text("\(index + 1). \(CheckoutPaymentLogic.paymentMethodLabel(payment.method)) · \(CartTotalsLogic.formatMoney(payment.amount))")
                                .font(.caption)
                            Spacer()
                            if payment.method != "card" {
                                Button("Remove") { onRemovePayment(index) }
                                    .font(.caption2.bold())
                                    .foregroundStyle(PosColors.burgundy)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            PosNumberPad(
                layout: .compact,
                onDigit: onAmountDigit,
                onClear: onAmountClear,
                onBackspace: onAmountBackspace
            )

            if cashEnabled && !creditOnlyPayments {
                Button("Cash") { onApplyCash() }
                    .buttonStyle(PosFullWidthButtonStyle())
                    .disabled(processingCard || balanceDue <= 0.005)
            }
            Button(processingCard ? "Processing…" : "Charge Card") { onApplyCard() }
                .buttonStyle(PosFullWidthButtonStyle())
                .disabled(processingCard || balanceDue <= 0.005)
        }
        .padding(4)
    }

    private func amountRow(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            Text(value)
                .font(bold ? .subheadline.bold() : .subheadline)
        }
    }
}
