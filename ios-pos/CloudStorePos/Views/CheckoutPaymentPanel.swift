import SwiftUI

struct CheckoutPaymentPanel: View {
    let saleTotal: Double
    let balanceDue: Double
    let cashAmountDue: Double
    let payments: [CheckoutPayment]
    let cashEnabled: Bool
    let creditOnlyPayments: Bool
    let amountInput: String
    let processingCard: Bool
    let onAmountDigit: (Character) -> Void
    let onAmountClear: () -> Void
    let onAmountBackspace: () -> Void
    let onAmountDecimal: () -> Void
    let onFillRemaining: () -> Void
    let onQuickBill: (Int) -> Void
    let onApplyCash: () -> Void
    let onApplyCard: () -> Void
    let onRemovePayment: (Int) -> Void
    let onBack: () -> Void

    private var quickBills: [Int] {
        let target = (!creditOnlyPayments && cashEnabled && cashAmountDue + 0.005 < balanceDue)
            ? cashAmountDue
            : balanceDue
        return CartTotalsLogic.cashQuickDenominations(
            amountDue: target,
            cashEnabled: !creditOnlyPayments && cashEnabled
        )
    }

    private var tenderTarget: Double {
        (cashEnabled && cashAmountDue + 0.005 < balanceDue) ? cashAmountDue : balanceDue
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
            let collectedSale = CartTotalsLogic.collectedTotal(saleTotal)
            if collectedSale + 0.005 < saleTotal {
                amountRow("Payable (nickels)", CartTotalsLogic.formatMoney(collectedSale))
            }
            amountRow("Balance due", CartTotalsLogic.formatMoney(balanceDue), bold: true)
            amountRow("Amount entered", CashEntryLogic.displayCashEntry(amountInput))

            if let entered = CashEntryLogic.parseCashTendered(amountInput) {
                let changeDelta = CartTotalsLogic.roundMoney(entered - tenderTarget)
                if changeDelta < -0.005 {
                    amountRow("Still need", CartTotalsLogic.formatMoney(-changeDelta), color: PosColors.burgundy)
                } else if changeDelta >= 0.005 {
                    amountRow("Give change", CartTotalsLogic.formatMoney(changeDelta), bold: true, color: PosColors.teal)
                } else {
                    amountRow("Change", CartTotalsLogic.formatMoney(0))
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

            Spacer(minLength: 0)

            if balanceDue > 0.005 {
                HStack(spacing: 6) {
                    Button {
                        onFillRemaining()
                    } label: {
                        Text(CartTotalsLogic.formatMoney(tenderTarget))
                    }
                    .buttonStyle(PosOutlinedQuickButtonStyle())
                    .frame(maxWidth: .infinity)

                    ForEach(quickBills, id: \.self) { bill in
                        Button("$\(bill)") { onQuickBill(bill) }
                            .buttonStyle(PosOutlinedQuickButtonStyle())
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            PosNumberPad(
                layout: .compact,
                onDigit: onAmountDigit,
                onClear: onAmountClear,
                onBackspace: onAmountBackspace,
                onDecimal: onAmountDecimal
            )

            let nextAmount = CashEntryLogic.parseCashTendered(amountInput)
            let canPayCard = balanceDue > 0.005
                && nextAmount.map { $0 > 0 && $0 <= balanceDue + 0.005 } ?? false

            if cashEnabled && !creditOnlyPayments {
                Button("Cash") { onApplyCash() }
                    .buttonStyle(PosFullWidthButtonStyle())
                    .disabled(processingCard || balanceDue <= 0.005)
            }
            Button(processingCard ? "Processing…" : "Charge Card") { onApplyCard() }
                .buttonStyle(PosFullWidthButtonStyle())
                .disabled(processingCard || !canPayCard)
        }
        .padding(4)
        .frame(maxHeight: .infinity)
    }

    private func amountRow(_ label: String, _ value: String, bold: Bool = false, color: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(color ?? Color.primary)
            Spacer()
            Text(value)
                .font(bold ? .subheadline.bold() : .subheadline)
                .foregroundStyle(color ?? Color.primary)
        }
    }
}
