import SwiftUI

struct SaleTotalsPanel: View {
    let cart: [CartItem]
    let linkedCustomerName: String?
    let customerLinked: Bool
    let customerDiscount: Bool
    let salesFeeRate: Double
    let taxRate: Double

    private var displayItems: [CartItem] {
        customerLinked
            ? CartTotalsLogic.normalizeCartItems(cart, customerDiscount: customerDiscount)
            : cart
    }

    private var totals: CartTotals {
        CartTotalsLogic.computeCartTotals(displayItems, customerDiscount: customerLinked && customerDiscount)
    }

    private var taxAmount: Double {
        CartTotalsLogic.computeTaxAmount(
            cart: cart,
            customerLinked: customerLinked,
            customerDiscount: customerDiscount,
            salesFeeRate: salesFeeRate,
            taxRate: taxRate
        )
    }

    private var grandTotal: Double {
        CartTotalsLogic.computeSaleGrandTotal(
            cart: cart,
            customerLinked: customerLinked,
            customerDiscount: customerDiscount,
            salesFeeRate: salesFeeRate,
            taxRate: taxRate
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sale Total")
                .font(.subheadline.bold())
                .foregroundStyle(PosColors.burgundy)

            if let linkedCustomerName {
                Text(linkedCustomerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
            }

            HStack(alignment: .top, spacing: 2) {
                TotalSaleStat(label: "Items", value: "\(totals.itemCount)")

                if customerLinked {
                    TotalSaleStat(
                        label: "Subtotal",
                        value: CartTotalsLogic.formatMoney(totals.shelfSubtotal)
                    )
                    TotalSaleStat(
                        label: "Discount",
                        value: totals.showDiscount
                            ? "−\(CartTotalsLogic.formatMoney(totals.memberDiscount))"
                            : CartTotalsLogic.formatMoney(0),
                        valueColor: totals.showDiscount ? PosColors.teal : .secondary
                    )
                    TotalSaleStat(
                        label: "PreTax",
                        value: CartTotalsLogic.formatMoney(totals.itemPreTax)
                    )
                } else {
                    TotalSaleStat(
                        label: "Subtotal",
                        value: CartTotalsLogic.formatMoney(totals.itemPreTax)
                    )
                }

                TotalSaleStat(
                    label: "Savings",
                    value: totals.saleSavings > 0.005
                        ? "−\(CartTotalsLogic.formatMoney(totals.saleSavings))"
                        : CartTotalsLogic.formatMoney(0),
                    valueColor: PosColors.burgundy
                )
                TotalSaleStat(label: "Tax", value: CartTotalsLogic.formatMoney(taxAmount))
                TotalSaleStat(
                    label: "Total",
                    value: CartTotalsLogic.formatMoney(grandTotal),
                    emphasize: true
                )
            }
            .padding(.top, 2)
        }
    }
}

private struct TotalSaleStat: View {
    let label: String
    let value: String
    var emphasize: Bool = false
    var valueColor: Color?

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(emphasize ? .subheadline.bold() : .caption.weight(.medium))
                .foregroundStyle(valueColor ?? (emphasize ? PosColors.burgundy : Color.primary))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 1)
    }
}
