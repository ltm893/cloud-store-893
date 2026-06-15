import Foundation
import Observation

@Observable
@MainActor
final class PosRegisterViewModel {
    private(set) var cart: [CartItem] = []
    private(set) var customers: [StoreCustomer] = []
    private(set) var products: [Product] = []
    private(set) var selectedCustomerId: Int?
    private(set) var memberPricingActive = false
    private(set) var cartTotals = CartTotals(
        itemCount: 0, shelfSubtotal: 0, itemPreTax: 0,
        memberDiscount: 0, saleSavings: 0, linked893: false
    )
    private(set) var status = "Loading…"
    private(set) var addItemError: String?
    private(set) var isLoading = true

    var scanInput = ""
    var quantityEditCartItemId: Int?
    var quantityEditInput = ""
    var checkoutOpen = false
    var checkoutAmountInput = ""
    var checkoutPayments: [CheckoutPayment] = []
    var saleItemsLocked = false
    var processingCard = false
    var processingMessage: String?
    var receipt: SaleReceiptInfo?
    var receiptPrintMessage: String?
    var receiptPrintProgress: Double = 0

    var customerFindOpen = false
    private(set) var queuedCheckoutCount = 0
    private(set) var queueSyncing = false

    let cashEnabled: Bool
    let creditOnlyPayments: Bool

    private let api: PosAPIClient
    private let queueStore: OfflineQueueStore
    private let salesFeeRate = AppConfig.salesFeeRate
    private let taxRate = AppConfig.taxRate

    init(
        api: PosAPIClient,
        cashEnabled: Bool,
        creditOnlyPayments: Bool,
        queueStore: OfflineQueueStore = .shared
    ) {
        self.api = api
        self.cashEnabled = cashEnabled
        self.creditOnlyPayments = creditOnlyPayments
        self.queueStore = queueStore
        queuedCheckoutCount = queueStore.all().count
    }

    var selectedCustomer: StoreCustomer? {
        guard let selectedCustomerId else { return nil }
        return customers.first { $0.id == selectedCustomerId }
    }

    var customerLinked: Bool { selectedCustomerId != nil }
    var customerDiscountActive: Bool { selectedCustomerId != nil }

    var registerTotal: Double {
        CartTotalsLogic.computeSaleGrandTotal(
            cart: cart,
            customerLinked: customerLinked,
            customerDiscount: customerDiscountActive,
            salesFeeRate: salesFeeRate,
            taxRate: taxRate
        )
    }

    var balanceDue: Double {
        let paid = CartTotalsLogic.roundMoney(checkoutPayments.reduce(0) { $0 + $1.amount })
        return CartTotalsLogic.roundMoney(max(0, registerTotal - paid))
    }

    var quantityEditing: Bool { quantityEditCartItemId != nil }

    var canAddFromScanField: Bool {
        !checkoutOpen
            && receipt == nil
            && !saleItemsLocked
            && !quantityEditing
            && !customerFindOpen
            && !scanInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canOpenCheckout: Bool {
        !cart.isEmpty
            && receipt == nil
            && !checkoutOpen
            && !customerFindOpen
            && !(quantityEditing && !quantityEditInput.isEmpty)
    }

    func loadOnAppear() {
        reloadQueuedCheckoutCount()
        Task {
            await refresh()
            await flushOfflineQueue()
        }
    }

    func reloadQueuedCheckoutCount() {
        queuedCheckoutCount = queueStore.all().count
    }

    func refresh() async {
        isLoading = true
        status = "Loading…"
        do {
            async let customersResponse = api.fetchCustomers()
            async let productsResponse = api.fetchProducts()
            async let cartResponse = api.fetchCart(customerId: selectedCustomerId)
            customers = try await customersResponse
            products = try await productsResponse
            applyCartResponse(try await cartResponse)
            status = "Ready"
            isLoading = false
        } catch {
            isLoading = false
            status = "Load failed — \(error.localizedDescription)"
        }
    }

    func toggleCustomerFind() {
        if !customerFindOpen {
            cancelQuantityEdit()
        }
        customerFindOpen.toggle()
    }

    func closeCustomerFind() {
        customerFindOpen = false
    }

    func linkCustomer(id: Int) {
        guard let customer = customers.first(where: { $0.id == id }) else {
            status = "Unknown customer id \(id)"
            return
        }
        selectedCustomerId = id
        customerFindOpen = false
        status = "Linked \(customer.name) — customer discount"
        Task { await reloadCart() }
    }

    func unlinkCustomer() {
        selectedCustomerId = nil
        status = "Ready"
        Task { await reloadCart() }
    }

    private func reloadCart() async {
        do {
            let response = try await api.fetchCart(customerId: selectedCustomerId)
            applyCartResponse(response)
        } catch {
            status = "Cart refresh failed — \(error.localizedDescription)"
        }
    }

    func appendScanDigit(_ digit: Character) {
        guard !checkoutOpen, receipt == nil, !quantityEditing else { return }
        scanInput = CashEntryLogic.appendScanDigit(current: scanInput, digit: digit)
    }

    func backspaceScanInput() {
        guard !checkoutOpen else { return }
        scanInput = String(scanInput.dropLast())
    }

    func clearScanInput() {
        guard !checkoutOpen else { return }
        scanInput = ""
    }

    func addFromScanField() {
        let cleaned = scanInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            addItemError = "Enter barcode or product ID"
            return
        }
        if let productId = Int(cleaned), cleaned.count <= 6 {
            guard let product = products.first(where: { $0.id == productId }) else {
                if customers.contains(where: { $0.id == productId }) {
                    linkCustomer(id: productId)
                    scanInput = ""
                    addItemError = nil
                    return
                }
                addItemError = "Product not found: ID \(cleaned)"
                return
            }
            if !product.inStock {
                let stockMsg = product.quantityOnHand.map { " (qty \($0))" } ?? ""
                addItemError = "\(product.name) is out of stock\(stockMsg)"
                return
            }
            addProduct(productId: productId)
        } else {
            if let product = products.first(where: { $0.barcode == cleaned }), !product.inStock {
                let stockMsg = product.quantityOnHand.map { " (qty \($0))" } ?? ""
                addItemError = "\(product.name) is out of stock\(stockMsg)"
                return
            }
            Task { await addByBarcode(cleaned) }
        }
    }

    func addProduct(productId: Int) {
        Task {
            do {
                let response = try await api.addProductToCart(
                    productId: productId,
                    customerId: selectedCustomerId
                )
                applyCartResponse(response)
                scanInput = ""
                addItemError = nil
            } catch {
                addItemError = error.localizedDescription
            }
        }
    }

    private func addByBarcode(_ barcode: String) async {
        do {
            let response = try await api.addBarcodeToCart(
                barcode: barcode,
                customerId: selectedCustomerId
            )
            applyCartResponse(response)
            scanInput = ""
            addItemError = nil
        } catch {
            addItemError = error.localizedDescription
        }
    }

    func removeCartItem(_ item: CartItem) {
        guard !saleItemsLocked else { return }
        if quantityEditCartItemId == item.id {
            cancelQuantityEdit()
        }
        Task {
            do {
                let response = try await api.removeCartItem(
                    id: item.id,
                    customerId: selectedCustomerId
                )
                applyCartResponse(response)
            } catch {
                status = "Remove failed — \(error.localizedDescription)"
            }
        }
    }

    func startQuantityEdit(cartItemId: Int) {
        guard !saleItemsLocked, !checkoutOpen, receipt == nil else { return }
        quantityEditCartItemId = cartItemId
        quantityEditInput = ""
        scanInput = ""
        addItemError = nil
    }

    func cancelQuantityEdit() {
        quantityEditCartItemId = nil
        quantityEditInput = ""
    }

    func appendQuantityEditDigit(_ digit: Character) {
        guard quantityEditing else { return }
        quantityEditInput = CashEntryLogic.appendQuantityDigit(current: quantityEditInput, digit: digit)
    }

    func clearQuantityEditInput() {
        guard quantityEditing else { return }
        quantityEditInput = ""
    }

    func backspaceQuantityEditInput() {
        guard quantityEditing else { return }
        quantityEditInput = String(quantityEditInput.dropLast())
    }

    func applyQuantityEdit() {
        guard let itemId = quantityEditCartItemId else { return }
        guard let qty = Int(quantityEditInput) else {
            status = "Enter a quantity"
            return
        }
        cancelQuantityEdit()
        Task {
            do {
                let response: CartResponse
                if qty <= 0 {
                    response = try await api.removeCartItem(
                        id: itemId,
                        customerId: selectedCustomerId
                    )
                } else {
                    response = try await api.updateCartItemQuantity(
                        id: itemId,
                        quantity: qty,
                        customerId: selectedCustomerId
                    )
                }
                applyCartResponse(response)
            } catch {
                status = qty <= 0
                    ? "Remove failed — \(error.localizedDescription)"
                    : "Quantity update failed — \(error.localizedDescription)"
            }
        }
    }

    func openCheckout() {
        guard canOpenCheckout else { return }
        cancelQuantityEdit()
        closeCustomerFind()
        checkoutOpen = true
        checkoutPayments = []
        saleItemsLocked = false
        if registerTotal > 0.005 {
            checkoutAmountInput = String(format: "%.2f", registerTotal)
        } else {
            checkoutAmountInput = ""
        }
    }

    func closeCheckout() {
        guard checkoutPayments.isEmpty else { return }
        checkoutOpen = false
        checkoutAmountInput = ""
        saleItemsLocked = false
    }

    func appendCheckoutDigit(_ digit: Character) {
        let maxAmount = creditOnlyPayments && balanceDue > 0.005 ? balanceDue : nil
        checkoutAmountInput = CashEntryLogic.appendCashDigitLimited(
            current: checkoutAmountInput,
            digit: digit,
            maxAmount: maxAmount
        )
    }

    func clearCheckoutAmount() {
        checkoutAmountInput = ""
    }

    func backspaceCheckoutAmount() {
        checkoutAmountInput = String(checkoutAmountInput.dropLast())
    }

    func fillRemainingBalance() {
        let remaining = balanceDue
        if remaining <= 0.005 { return }
        checkoutAmountInput = String(format: "%.2f", remaining)
    }

    func applyQuickBill(_ amount: Int) {
        checkoutAmountInput = String(amount)
    }

    func applyPayment(method: String) {
        guard let entered = CashEntryLogic.parseCashTendered(checkoutAmountInput) else { return }
        guard let payment = CheckoutPaymentLogic.buildCheckoutPaymentLine(
            method: method,
            enteredAmount: entered,
            balanceDue: balanceDue
        ) else { return }

        saleItemsLocked = true
        if method == "card" {
            Task { await processCardPayment(payment) }
        } else {
            checkoutPayments.append(payment)
            checkoutAmountInput = ""
            if balanceDue <= 0.005 {
                Task { await finalizeCheckout() }
            }
        }
    }

    private func processCardPayment(_ payment: CheckoutPayment) async {
        processingCard = true
        processingMessage = "Sending \(CartTotalsLogic.formatMoney(payment.amount)) to terminal…"
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        checkoutPayments.append(payment)
        checkoutAmountInput = ""
        processingCard = false
        processingMessage = nil
        if balanceDue <= 0.005 {
            await finalizeCheckout()
        }
    }

    func removePayment(at index: Int) {
        guard checkoutPayments.indices.contains(index) else { return }
        guard checkoutPayments[index].method != "card" else { return }
        checkoutPayments.remove(at: index)
        if checkoutPayments.isEmpty {
            saleItemsLocked = false
        }
    }

    private func finalizeCheckout() async {
        let payments = checkoutPayments
        let total = registerTotal
        let method = CheckoutPaymentLogic.checkoutFinalizeMethod(payments)
        let customerId = selectedCustomerId
        let cartSnapshot = cart
        let customerName = selectedCustomerId.map {
            CustomerFindLogic.displayName(selectedCustomer, customerId: $0)
        }
        let customerLinked = customerId != nil
        let customerDiscount = customerLinked
        status = "Completing sale…"
        do {
            let response = try await api.checkout(
                CheckoutRequest(
                    paymentMethod: method,
                    customerId: customerId,
                    payments: payments,
                    checkoutTotal: total
                )
            )
            receipt = SaleReceiptLogic.buildSaleReceipt(
                cart: cartSnapshot,
                customerName: customerName,
                customerLinked: customerLinked,
                customerDiscount: customerDiscount,
                salesFeeRate: salesFeeRate,
                taxRate: taxRate,
                payments: response.payments ?? payments,
                orderNumber: response.orderNumber.isEmpty ? nil : response.orderNumber
            )
            checkoutOpen = false
            checkoutPayments = []
            checkoutAmountInput = ""
            saleItemsLocked = false
            selectedCustomerId = nil
            status = "Sale complete"
            await refresh()
        } catch let error as PosAPIError {
            switch error {
            case .httpStatus(401, _):
                status = "Session expired — sign in again"
            default:
                status = error.localizedDescription
                saleItemsLocked = false
            }
        } catch {
            if NetworkErrorLogic.isOfflineLike(error) {
                enqueueOfflineCheckout(
                    paymentMethod: method,
                    customerId: customerId,
                    cartSnapshot: cartSnapshot,
                    payments: payments,
                    checkoutTotal: total
                )
            } else {
                status = error.localizedDescription
                saleItemsLocked = false
            }
        }
    }

    private func enqueueOfflineCheckout(
        paymentMethod: String,
        customerId: Int?,
        cartSnapshot: [CartItem],
        payments: [CheckoutPayment],
        checkoutTotal: Double
    ) {
        let customerName = customerId.map {
            CustomerFindLogic.displayName(selectedCustomer, customerId: $0)
        }
        let lines = cartSnapshot.map { CartLineQuantity(productId: $0.productId, quantity: $0.quantity) }
        queueStore.enqueue(
            paymentMethod: paymentMethod,
            customerId: customerId,
            cartLines: lines,
            payments: payments,
            checkoutTotal: checkoutTotal
        )
        receipt = SaleReceiptLogic.buildSaleReceipt(
            cart: cartSnapshot,
            customerName: customerName,
            customerLinked: customerId != nil,
            customerDiscount: customerId != nil,
            salesFeeRate: salesFeeRate,
            taxRate: taxRate,
            payments: payments,
            queuedOffline: true
        )
        checkoutOpen = false
        checkoutPayments = []
        checkoutAmountInput = ""
        selectedCustomerId = nil
        queuedCheckoutCount = queueStore.all().count
        status = "Ready"
    }

    func flushOfflineQueue() async {
        let queued = queueStore.all()
        guard !queued.isEmpty else {
            queuedCheckoutCount = 0
            if status == "Loading…" || status == "Ready" {
                return
            }
            status = "No queued checkouts"
            return
        }

        queueSyncing = true
        status = "Syncing \(queued.count) queued…"

        var synced = 0
        var droppedStale = 0
        var droppedPermanent = 0
        var remaining: [PendingCheckout] = []
        var lastError: String?

        for pending in queued {
            if pending.cartLines.isEmpty {
                droppedStale += 1
                continue
            }
            do {
                try await syncPendingCheckout(pending)
                synced += 1
            } catch {
                if NetworkErrorLogic.isRetryableSyncError(error) {
                    remaining.append(pending)
                } else {
                    droppedPermanent += 1
                }
                lastError = syncErrorMessage(error)
            }
        }

        queueStore.replace(remaining)
        queuedCheckoutCount = remaining.count
        queueSyncing = false
        status = OfflineQueueFlushLogic.buildStatusMessage(
            .init(
                synced: synced,
                droppedStale: droppedStale,
                droppedPermanent: droppedPermanent,
                remaining: remaining.count,
                lastError: lastError
            )
        )
        await refresh()
    }

    private func syncPendingCheckout(_ pending: PendingCheckout) async throws {
        _ = try await api.replaceCart(items: pending.cartLines, customerId: pending.customerId)
        _ = try await api.checkout(
            CheckoutRequest(
                paymentMethod: pending.paymentMethod,
                customerId: pending.customerId,
                payments: pending.payments,
                checkoutTotal: pending.checkoutTotal
            )
        )
    }

    private func syncErrorMessage(_ error: Error) -> String {
        if case let PosAPIError.httpStatus(code, _) = error {
            return "HTTP \(code)"
        }
        return error.localizedDescription
    }

    func clearOfflineQueue() {
        queueStore.clear()
        queuedCheckoutCount = 0
        status = "Offline queue cleared"
    }

    func printReceipt() {
        guard receipt != nil, receiptPrintMessage == nil else { return }
        Task {
            receiptPrintMessage = "Printing Receipt"
            receiptPrintProgress = 0
            for step in 1...25 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                receiptPrintProgress = Double(step) / 25.0
            }
            await dismissReceiptAndRefresh()
        }
    }

    func dismissReceipt() {
        receipt = nil
        receiptPrintMessage = nil
        receiptPrintProgress = 0
        saleItemsLocked = false
        checkoutOpen = false
        checkoutPayments = []
        checkoutAmountInput = ""
        status = "Ready"
    }

    private func dismissReceiptAndRefresh() async {
        dismissReceipt()
        await refresh()
    }

    private func applyCartResponse(_ response: CartResponse) {
        memberPricingActive = response.linked893
        let discount = customerDiscountActive
        let items = CartTotalsLogic.normalizeCartItems(response.items, customerDiscount: discount)
        cart = items
        cartTotals = CartTotalsLogic.computeCartTotals(items, customerDiscount: discount)
        if let editingId = quantityEditCartItemId, !items.contains(where: { $0.id == editingId }) {
            cancelQuantityEdit()
        }
    }
}
