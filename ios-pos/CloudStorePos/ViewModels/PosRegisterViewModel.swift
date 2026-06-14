import Foundation
import Observation

@Observable
@MainActor
final class PosRegisterViewModel {
    private(set) var cart: [CartItem] = []
    private(set) var cartTotals = CartTotals(
        itemCount: 0, shelfSubtotal: 0, itemPreTax: 0,
        memberDiscount: 0, saleSavings: 0, linked893: false
    )
    private(set) var status = "Loading…"
    private(set) var addItemError: String?
    private(set) var isLoading = true

    var scanInput = ""
    var checkoutOpen = false
    var checkoutAmountInput = ""
    var checkoutPayments: [CheckoutPayment] = []
    var saleItemsLocked = false
    var processingCard = false
    var processingMessage: String?
    var receipt: SaleReceiptInfo?

    let cashEnabled: Bool
    let creditOnlyPayments: Bool

    private let api: PosAPIClient
    private let salesFeeRate = AppConfig.salesFeeRate
    private let taxRate = AppConfig.taxRate

    init(api: PosAPIClient, cashEnabled: Bool, creditOnlyPayments: Bool) {
        self.api = api
        self.cashEnabled = cashEnabled
        self.creditOnlyPayments = creditOnlyPayments
    }

    var registerTotal: Double {
        CartTotalsLogic.computeSaleGrandTotal(cart: cart, salesFeeRate: salesFeeRate, taxRate: taxRate)
    }

    var balanceDue: Double {
        let paid = CartTotalsLogic.roundMoney(checkoutPayments.reduce(0) { $0 + $1.amount })
        return CartTotalsLogic.roundMoney(max(0, registerTotal - paid))
    }

    var canOpenCheckout: Bool {
        !cart.isEmpty && receipt == nil && !checkoutOpen
    }

    func loadOnAppear() {
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        status = "Loading…"
        do {
            let cartResponse = try await api.fetchCart()
            applyCartResponse(cartResponse)
            status = "Ready"
            isLoading = false
        } catch {
            isLoading = false
            status = "Load failed — \(error.localizedDescription)"
        }
    }

    func appendScanDigit(_ digit: Character) {
        guard !checkoutOpen, receipt == nil else { return }
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
            addProduct(productId: productId)
        } else {
            Task { await addByBarcode(cleaned) }
        }
    }

    func addProduct(productId: Int) {
        Task {
            do {
                let response = try await api.addProductToCart(productId: productId)
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
            let response = try await api.addBarcodeToCart(barcode: barcode)
            applyCartResponse(response)
            scanInput = ""
            addItemError = nil
        } catch {
            addItemError = error.localizedDescription
        }
    }

    func removeCartItem(_ item: CartItem) {
        guard !saleItemsLocked else { return }
        Task {
            do {
                let response = try await api.removeCartItem(id: item.id)
                applyCartResponse(response)
            } catch {
                status = "Remove failed — \(error.localizedDescription)"
            }
        }
    }

    func openCheckout() {
        guard canOpenCheckout else { return }
        checkoutOpen = true
        checkoutAmountInput = ""
        checkoutPayments = []
        saleItemsLocked = false
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
        status = "Completing sale…"
        do {
            let response = try await api.checkout(
                CheckoutRequest(
                    paymentMethod: method,
                    customerId: nil,
                    payments: payments,
                    checkoutTotal: total
                )
            )
            receipt = SaleReceiptInfo(
                orderNumber: response.orderNumber,
                total: response.total,
                payments: response.payments ?? payments,
                changeTotal: CheckoutPaymentLogic.checkoutChangeTotal(payments)
            )
            checkoutOpen = false
            checkoutPayments = []
            checkoutAmountInput = ""
            saleItemsLocked = false
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
            status = error.localizedDescription
            saleItemsLocked = false
        }
    }

    func dismissReceipt() {
        receipt = nil
        status = "Ready"
    }

    private func applyCartResponse(_ response: CartResponse) {
        let items = CartTotalsLogic.normalizeCartItems(response.items, customerDiscount: false)
        cart = items
        cartTotals = CartTotalsLogic.computeCartTotals(items, customerDiscount: false)
    }
}
