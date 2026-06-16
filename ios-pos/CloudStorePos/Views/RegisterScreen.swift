import SwiftUI

struct RegisterScreen: View {
    let user: String
    let session: PosSessionViewModel
    let onBreak: () -> Void
    let onCloseTill: () -> Void
    @State private var viewModel: PosRegisterViewModel
    @State private var drawerOpen = false
    @State private var adminOpen = false
    @State private var statusVisible = false

    init(
        user: String,
        session: PosSessionViewModel,
        onBreak: @escaping () -> Void,
        onCloseTill: @escaping () -> Void
    ) {
        self.user = user
        self.session = session
        self.onBreak = onBreak
        self.onCloseTill = onCloseTill
        _viewModel = State(initialValue: session.makeRegisterViewModel())
    }

    var body: some View {
        PosNavigationDrawer(isOpen: $drawerOpen) {
            drawerMenu
        } content: {
            VStack(spacing: 0) {
                PosRegisterTopBar(user: user) {
                    drawerOpen = true
                }
                GeometryReader { geo in
                    let gutter = PosLayoutMetrics.registerCenterGutter
                    let hPad = PosLayoutMetrics.registerSideGutter * 2
                    let available = geo.size.width - hPad - gutter
                    HStack(alignment: .top, spacing: gutter) {
                        mainColumn.frame(width: (available * 0.52).rounded())
                        rightColumn.frame(width: (available * 0.48).rounded())
                    }
                    .padding(.horizontal, PosLayoutMetrics.registerSideGutter)
                    .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PosColors.cream)
            .overlay {
                if viewModel.processingCard {
                    processingOverlay(
                        message: viewModel.processingMessage ?? "Processing card…",
                        progress: nil
                    )
                } else if let printMessage = viewModel.receiptPrintMessage {
                    processingOverlay(
                        message: printMessage,
                        progress: viewModel.receiptPrintProgress
                    )
                }
            }
            .onAppear { viewModel.loadOnAppear() }
            .onChange(of: viewModel.queuedCheckoutCount) { _, count in
                if count > 0 {
                    statusVisible = true
                }
            }
            .fullScreenCover(isPresented: $adminOpen) {
                AdminWebScreen { adminOpen = false }
            }
        }
    }

    private var drawerMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Menu")
                .font(.headline.bold())
                .foregroundStyle(PosColors.burgundy)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            PosDrawerMenuButton(title: statusVisible ? "Hide status" : "Show status") {
                drawerOpen = false
                statusVisible.toggle()
            }
            PosDrawerMenuButton(title: viewModel.customerFindOpen ? "Show keypad" : "Find customer") {
                drawerOpen = false
                viewModel.toggleCustomerFind()
            }
            if viewModel.queuedCheckoutCount > 0 {
                PosDrawerMenuButton(
                    title: viewModel.queueSyncing
                        ? "Syncing queue…"
                        : "Sync queued (\(viewModel.queuedCheckoutCount))"
                ) {
                    drawerOpen = false
                    Task { await viewModel.flushOfflineQueue() }
                }
                PosDrawerMenuButton(title: "Discard queue (\(viewModel.queuedCheckoutCount))") {
                    drawerOpen = false
                    viewModel.clearOfflineQueue()
                }
            }
            PosDrawerMenuButton(title: "Admin") {
                drawerOpen = false
                adminOpen = true
            }
            PosDrawerMenuButton(title: "Sign out") {
                drawerOpen = false
                onBreak()
            }
            PosDrawerMenuButton(title: "Close till") {
                drawerOpen = false
                onCloseTill()
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var salePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let receipt = viewModel.receipt {
                SaleReceiptContent(receipt: receipt)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
                saleTotalsStrip
            }
        }
        .posPanelStyle()
    }

    private var saleTotalsStrip: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(PosColors.panelBorder.opacity(0.35))
            SaleTotalsPanel(
                cart: viewModel.cart,
                linkedCustomerName: viewModel.selectedCustomer.map {
                    CustomerFindLogic.displayName($0, customerId: $0.id)
                },
                customerLinked: viewModel.customerLinked,
                customerDiscount: viewModel.customerDiscountActive,
                salesFeeRate: AppConfig.salesFeeRate,
                taxRate: AppConfig.taxRate
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.45))
        }
        .padding(.top, 4)
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
                .disabled(!viewModel.canAddFromScanField)
        }
    }

    private var cartPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Current sale")
                .font(.subheadline.bold())
                .foregroundStyle(PosColors.burgundy)
            if let customerId = viewModel.selectedCustomerId {
                HStack {
                    Text(CustomerFindLogic.displayName(
                        viewModel.selectedCustomer,
                        customerId: customerId
                    ))
                    .font(.subheadline)
                    Spacer()
                    Button("Unlink") { viewModel.unlinkCustomer() }
                        .font(.caption.bold())
                        .foregroundStyle(PosColors.burgundy)
                        .buttonStyle(.plain)
                        .disabled(viewModel.saleItemsLocked)
                }
                .padding(.top, 4)
            }
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
                                quantityEditActive: viewModel.quantityEditCartItemId == item.id,
                                editEnabled: !viewModel.saleItemsLocked,
                                onEditQuantity: { viewModel.startQuantityEdit(cartItemId: item.id) },
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

    private var rightColumn: some View {
        let showStatusPanel = statusVisible
            && viewModel.receipt == nil
            && !viewModel.checkoutOpen
            && !viewModel.customerFindOpen

        return VStack(spacing: 8) {
            if showStatusPanel {
                RegisterStatusPanel(
                    apiBaseURL: AppConfig.apiBaseURL.absoluteString,
                    tillId: session.activeTillId,
                    posSessionId: session.activePosSessionId,
                    statusMessage: viewModel.status,
                    queuedCount: viewModel.queuedCheckoutCount,
                    syncing: viewModel.queueSyncing,
                    onSyncQueued: { Task { await viewModel.flushOfflineQueue() } },
                    onDiscardQueued: { viewModel.clearOfflineQueue() }
                )
            }

            if viewModel.receipt != nil {
                ReceiptActionPanel(
                    onPrint: { viewModel.printReceipt() },
                    printEnabled: viewModel.receiptPrintMessage == nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    registerInputPanel
                }
                .frame(maxWidth: .infinity)
                .posPanelStyle()
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var registerInputPanel: some View {
        Group {
            if viewModel.checkoutOpen {
                CheckoutPaymentPanel(
                    saleTotal: viewModel.registerTotal,
                    balanceDue: viewModel.balanceDue,
                    cashAmountDue: viewModel.cashBalanceDue,
                    payments: viewModel.checkoutPayments,
                    cashEnabled: viewModel.cashEnabled,
                    creditOnlyPayments: viewModel.creditOnlyPayments,
                    amountInput: viewModel.checkoutAmountInput,
                    processingCard: viewModel.processingCard,
                    onAmountDigit: { viewModel.appendCheckoutDigit($0) },
                    onAmountClear: { viewModel.clearCheckoutAmount() },
                    onAmountBackspace: { viewModel.backspaceCheckoutAmount() },
                    onAmountDecimal: { viewModel.appendCheckoutDigit(".") },
                    onFillRemaining: { viewModel.fillRemainingBalance() },
                    onQuickBill: { viewModel.applyQuickBill($0) },
                    onApplyCash: { viewModel.applyPayment(method: "cash") },
                    onApplyCard: { viewModel.applyPayment(method: "card") },
                    onRemovePayment: { viewModel.removePayment(at: $0) },
                    onBack: { viewModel.closeCheckout() }
                )
                .frame(maxHeight: .infinity)
            } else if viewModel.customerFindOpen {
                CustomerFindPanel(
                    customers: viewModel.customers,
                    linkedCustomerId: viewModel.selectedCustomerId,
                    onLink: { viewModel.linkCustomer(id: $0) },
                    onUnlink: { viewModel.unlinkCustomer() },
                    onClose: { viewModel.closeCustomerFind() }
                )
                .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 6) {
                    if viewModel.quantityEditing {
                        let editingItem = viewModel.cart.first { $0.id == viewModel.quantityEditCartItemId }
                        CartQuantityEditHeader(
                            itemName: editingItem?.name ?? "",
                            quantityInput: viewModel.quantityEditInput,
                            onCancel: { viewModel.cancelQuantityEdit() },
                            onApply: { viewModel.applyQuantityEdit() }
                        )
                    }
                    PosNumberPad(
                        layout: .compact,
                        onDigit: { digit in
                            if viewModel.quantityEditing {
                                viewModel.appendQuantityEditDigit(digit)
                            } else {
                                viewModel.appendScanDigit(digit)
                            }
                        },
                        onClear: {
                            if viewModel.quantityEditing {
                                viewModel.clearQuantityEditInput()
                            } else {
                                viewModel.clearScanInput()
                            }
                        },
                        onBackspace: {
                            if viewModel.quantityEditing {
                                viewModel.backspaceQuantityEditInput()
                            } else {
                                viewModel.backspaceScanInput()
                            }
                        }
                    )
                    .padding(PosLayoutMetrics.numpadKeyGap)
                    .frame(height: PosLayoutMetrics.numpadCardHeight)
                    Button("Pay") { viewModel.openCheckout() }
                        .buttonStyle(PosFullWidthButtonStyle())
                        .disabled(!viewModel.canOpenCheckout)
                }
            }
        }
    }

    private func processingOverlay(message: String, progress: Double?) -> some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                if let progress {
                    ProgressView(value: progress)
                        .frame(width: 180)
                } else {
                    ProgressView()
                }
                Text(message)
                    .font(.subheadline)
            }
            .padding(24)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct PosFullWidthButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(PosColors.teal)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct CartLineRow: View {
    let item: CartItem
    var quantityEditActive: Bool = false
    var editEnabled: Bool = true
    var onEditQuantity: () -> Void = {}
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
                Button(action: onEditQuantity) {
                    Text(quantityEditActive ? "Quantity" : "Quantity · \(item.quantity)")
                        .font(.caption.weight(quantityEditActive ? .bold : .regular))
                        .foregroundStyle(PosColors.teal)
                }
                .buttonStyle(.plain)
                .disabled(!editEnabled)
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
