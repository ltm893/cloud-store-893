import SwiftUI

struct RegisterScreen: View {
    let user: String
    let onBreak: () -> Void
    @State private var viewModel: PosRegisterViewModel

    init(user: String, session: PosSessionViewModel, onBreak: @escaping () -> Void) {
        self.user = user
        self.onBreak = onBreak
        _viewModel = State(initialValue: session.makeRegisterViewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            registerHeader
            if let receipt = viewModel.receipt {
                receiptView(receipt)
            } else {
                HStack(alignment: .top, spacing: PosLayoutMetrics.registerCenterGutter) {
                    mainColumn
                    rightColumn
                }
                .padding(.horizontal, PosLayoutMetrics.registerSideGutter)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PosColors.cream)
        .overlay {
            if viewModel.processingCard {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(viewModel.processingMessage ?? "Processing card…")
                            .font(.subheadline)
                    }
                    .padding(24)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .onAppear { viewModel.loadOnAppear() }
    }

    private var registerHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cloud Store POS")
                    .font(.headline.bold())
                Text(user)
                    .font(.caption)
                    .opacity(0.9)
            }
            Spacer()
            Text(viewModel.status)
                .font(.caption)
                .opacity(0.85)
            Button("Break") { onBreak() }
                .font(.subheadline.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.leading, 12)
        }
        .foregroundStyle(PosColors.cream)
        .padding(.horizontal, PosLayoutMetrics.registerSideGutter)
        .padding(.vertical, 10)
        .background(PosColors.burgundy)
    }

    private var mainColumn: some View {
        VStack(spacing: 8) {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                salePanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            totalsBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var salePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            scanBar
            if let error = viewModel.addItemError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Divider()
                .overlay(PosColors.panelBorder.opacity(0.35))
                .padding(.vertical, 2)
            cartPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .posPanelStyle()
    }

    private var scanBar: some View {
        HStack(spacing: 8) {
            Text(viewModel.scanInput.isEmpty ? "Scan / Add Id" : viewModel.scanInput)
                .font(.body.monospacedDigit())
                .foregroundStyle(viewModel.scanInput.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.2), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Button("Add") { viewModel.addFromScanField() }
                .buttonStyle(PosPrimaryButtonStyle())
        }
    }

    private var cartPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Current sale")
                .font(.subheadline.bold())
                .foregroundStyle(PosColors.burgundy)
            if viewModel.cart.isEmpty {
                Text("Cart is empty")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.cart) { item in
                            CartLineRow(
                                item: item,
                                removeEnabled: !viewModel.saleItemsLocked,
                                onRemove: { viewModel.removeCartItem(item) }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var totalsBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pre-tax payable: \(CartTotalsLogic.formatMoney(viewModel.cartTotals.itemPreTax))")
                    .font(.footnote)
                Text("Total due: \(CartTotalsLogic.formatMoney(viewModel.registerTotal))")
                    .font(.title3.bold())
            }
            Spacer()
            if viewModel.canOpenCheckout {
                Button("Pay") { viewModel.openCheckout() }
                    .buttonStyle(PosPrimaryButtonStyle())
            }
        }
        .padding(12)
        .posPanelStyle()
    }

    private var rightColumn: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Group {
                if viewModel.checkoutOpen {
                    CheckoutPaymentPanel(
                        saleTotal: viewModel.registerTotal,
                        balanceDue: viewModel.balanceDue,
                        payments: viewModel.checkoutPayments,
                        cashEnabled: viewModel.cashEnabled,
                        creditOnlyPayments: viewModel.creditOnlyPayments,
                        amountInput: viewModel.checkoutAmountInput,
                        processingCard: viewModel.processingCard,
                        onAmountDigit: { viewModel.appendCheckoutDigit($0) },
                        onAmountClear: { viewModel.clearCheckoutAmount() },
                        onAmountBackspace: { viewModel.backspaceCheckoutAmount() },
                        onFillRemaining: { viewModel.fillRemainingBalance() },
                        onQuickBill: { viewModel.applyQuickBill($0) },
                        onApplyCash: { viewModel.applyPayment(method: "cash") },
                        onApplyCard: { viewModel.applyPayment(method: "card") },
                        onRemovePayment: { viewModel.removePayment(at: $0) },
                        onBack: { viewModel.closeCheckout() }
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    VStack(spacing: 8) {
                        PosNumberPad(
                            layout: .compact,
                            onDigit: { viewModel.appendScanDigit($0) },
                            onClear: { viewModel.clearScanInput() },
                            onBackspace: { viewModel.backspaceScanInput() }
                        )
                        .padding(PosLayoutMetrics.numpadKeyGap)
                        Button("Add to cart") { viewModel.addFromScanField() }
                            .buttonStyle(PosFullWidthButtonStyle())
                    }
                    .frame(height: PosLayoutMetrics.numpadCardHeight + 52)
                }
            }
            .frame(width: PosLayoutMetrics.numpadColumnWidth)
            .posPanelStyle()
        }
        .frame(width: PosLayoutMetrics.numpadColumnWidth)
        .frame(maxHeight: .infinity)
    }

    private func receiptView(_ receipt: SaleReceiptInfo) -> some View {
        VStack(spacing: 16) {
            Text("Sale complete")
                .font(.title2.bold())
                .foregroundStyle(PosColors.burgundy)
            Text(receipt.orderNumber)
                .font(.title3)
            Text(CartTotalsLogic.formatMoney(receipt.total))
                .font(.title)
            if receipt.changeTotal > 0.005 {
                Text("Change: \(CartTotalsLogic.formatMoney(receipt.changeTotal))")
                    .font(.headline)
                    .foregroundStyle(PosColors.teal)
            }
            ForEach(Array(receipt.payments.enumerated()), id: \.offset) { index, payment in
                Text("\(index + 1). \(CheckoutPaymentLogic.paymentMethodLabel(payment.method)) · \(CartTotalsLogic.formatMoney(payment.amount))")
                    .font(.subheadline)
            }
            Button("New sale") { viewModel.dismissReceipt() }
                .buttonStyle(PosPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

struct PosFullWidthButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(PosColors.teal)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct CartLineRow: View {
    let item: CartItem
    let removeEnabled: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline)
                        .lineLimit(2)
                    priceLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Quantity · \(item.quantity)")
                    .font(.caption)
                    .foregroundStyle(PosColors.teal)
                Button("Remove", action: onRemove)
                    .font(.caption)
                    .foregroundStyle(PosColors.burgundy)
                    .disabled(!removeEnabled)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var priceLine: some View {
        if item.onSale, let salePrice = item.salePrice {
            HStack(spacing: 6) {
                Text("Reg \(CartTotalsLogic.formatMoney(item.regularPrice))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .strikethrough(true, color: PosColors.burgundy)
                Text("Sale \(CartTotalsLogic.formatMoney(salePrice))")
                    .font(.caption)
                    .foregroundStyle(PosColors.burgundy)
            }
        } else {
            Text("ID \(item.productId) · Reg \(CartTotalsLogic.formatMoney(item.regularPrice))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
