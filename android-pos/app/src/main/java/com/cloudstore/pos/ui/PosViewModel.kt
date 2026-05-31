package com.cloudstore.pos.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.cloudstore.pos.data.CartItem
import com.cloudstore.pos.data.CartResponse
import com.cloudstore.pos.data.CheckoutPayment
import com.cloudstore.pos.data.OfflineQueueStore
import com.cloudstore.pos.data.PendingCheckout
import com.cloudstore.pos.data.QueuedCartLine
import com.cloudstore.pos.data.PosRepository
import com.cloudstore.pos.data.Product
import com.cloudstore.pos.data.Sale
import com.cloudstore.pos.data.StoreCustomer
import com.cloudstore.pos.BuildConfig
import java.io.IOException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import retrofit2.HttpException

data class PosUiState(
    val loading: Boolean = false,
    val products: List<Product> = emptyList(),
    val customers: List<StoreCustomer> = emptyList(),
    val selectedCustomerId: Int? = null,
    /** True when a customer is linked (all customers table rows get pre-tax discount). */
    val selectedCustomerDiscount: Boolean = false,
    val cart: List<CartItem> = emptyList(),
    val subtotalPreMember: Double = 0.0,
    val subtotalPayable: Double = 0.0,
    val memberDiscountPreTax: Double = 0.0,
    val linked893Cart: Boolean = false,
    val recentSales: List<Sale> = emptyList(),
    val paymentMethod: String = "card",
    val barcodeInput: String = "",
    val quantityEditCartItemId: Int? = null,
    val quantityEditInput: String = "",
    val status: String = "Ready",
    val isAuthenticated: Boolean = false,
    val pinInput: String = "",
    val queuedCheckoutCount: Int = 0,
    val queueSyncing: Boolean = false,
) {
    fun selectedCustomer(): StoreCustomer? =
        selectedCustomerId?.let { id -> customers.find { it.id == id } }

    /** True when a linked customer should receive the pre-tax discount. */
    fun customerDiscountActive(): Boolean = selectedCustomerId != null

    fun customerLinked(): Boolean = selectedCustomerId != null
}

class PosViewModel(
    private val repository: PosRepository,
    private val queueStore: OfflineQueueStore,
) : ViewModel() {
    private data class FreshPos(
        val products: List<Product>,
        val customers: List<StoreCustomer>,
        val cart: CartResponse,
        val sales: List<Sale>,
    )

    private val _state = MutableStateFlow(PosUiState())
    val state: StateFlow<PosUiState> = _state.asStateFlow()

    private val _checkoutState = MutableStateFlow(CheckoutUiState())
    val checkoutState: StateFlow<CheckoutUiState> = _checkoutState.asStateFlow()

    private val salesFeeRate = BuildConfig.POS_SALES_FEE_RATE.toDoubleOrNull() ?: 0.0
    private val taxRate = BuildConfig.POS_TAX_RATE.toDoubleOrNull() ?: 0.0

    private var cartRefreshGeneration = 0
    private var cardProcessingJob: Job? = null
    private var finalizeJob: Job? = null

    init {
        _state.update { it.copy(queuedCheckoutCount = queueStore.all().size) }
        viewModelScope.launch {
            state.map { it.isAuthenticated }
                .distinctUntilChanged()
                .collect { authed -> if (!authed) resetCheckout() }
        }
        viewModelScope.launch {
            combine(
                state.map { it.cart },
                state.map { it.isAuthenticated },
            ) { cart, authed -> authed && cart.isEmpty() }
                .distinctUntilChanged()
                .collect { empty -> if (empty) resetCheckout() }
        }
        viewModelScope.launch {
            state.map { it.status }
                .distinctUntilChanged()
                .collect { status ->
                    if (status.startsWith("Sale complete") || status.startsWith("Offline: checkout")) {
                        resetCheckout()
                    }
                }
        }
    }

    fun resetCheckout() {
        cardProcessingJob?.cancel()
        cardProcessingJob = null
        finalizeJob?.cancel()
        finalizeJob = null
        _checkoutState.value = CheckoutUiState()
    }

    fun updateCheckout(transform: (CheckoutUiState) -> CheckoutUiState) {
        _checkoutState.update(transform)
    }

    fun openCheckout() {
        cancelQuantityEdit()
        _checkoutState.value = CheckoutUiState(open = true)
    }

    private fun registerTotal(): Double {
        val s = _state.value
        return computeSaleGrandTotal(
            cart = s.cart,
            customerLinked = s.customerLinked(),
            customerDiscount = s.customerDiscountActive(),
            salesFeeRate = salesFeeRate,
            taxRate = taxRate,
        )
    }

    fun applyCheckoutPayment(method: String) {
        val current = _checkoutState.value
        val registerTotal = registerTotal()
        val paidTotal = roundMoney(current.payments.sumOf { it.amount })
        val remainingAmount = roundMoney((registerTotal - paidTotal).coerceAtLeast(0.0))
        val enteredAmount = parseCashTendered(current.amountInput) ?: return
        applyCheckoutPayment(method = method, enteredAmount = enteredAmount, remainingAmount = remainingAmount)
    }

    fun applyCardOnFilePayment() {
        val current = _checkoutState.value
        val registerTotal = registerTotal()
        val paidTotal = roundMoney(current.payments.sumOf { it.amount })
        val remainingAmount = roundMoney((registerTotal - paidTotal).coerceAtLeast(0.0))
        val enteredAmount = parseCashTendered(current.amountInput) ?: return
        applyCheckoutPayment(method = "card", enteredAmount = enteredAmount, remainingAmount = remainingAmount)
    }

    private fun applyCheckoutPayment(
        method: String,
        enteredAmount: Double,
        remainingAmount: Double,
    ) {
        val current = _checkoutState.value
        val registerTotal = registerTotal()
        val payment = buildCheckoutPaymentLine(method, enteredAmount, remainingAmount) ?: return
        _checkoutState.update { it.copy(saleItemsLocked = true) }
        if (method == "card") {
            processCardPayment(payment)
        } else {
            val updatedPayments = current.payments + payment
            val newRemaining = roundMoney(
                (registerTotal - updatedPayments.sumOf { it.amount }).coerceAtLeast(0.0),
            )
            if (newRemaining <= 0.005) {
                beginFinalize(updatedPayments, registerTotal)
            } else {
                _checkoutState.update {
                    it.copy(payments = updatedPayments, amountInput = "")
                }
            }
        }
    }

    private fun processCardPayment(payment: CheckoutPayment) {
        cardProcessingJob?.cancel()
        cardProcessingJob = viewModelScope.launch {
            _checkoutState.update { it.copy(processingCardPayment = payment) }
            var finalizeAfterCard = false
            try {
                _checkoutState.update {
                    it.copy(
                        paymentProcessingProgress = 0f,
                        processingDialogMessage = cardTerminalMessage(payment.amount),
                    )
                }
                repeat(50) { index ->
                    delay(100)
                    _checkoutState.update { it.copy(paymentProcessingProgress = (index + 1) / 50f) }
                }
                val updatedPayments = _checkoutState.value.payments + payment
                val total = registerTotal()
                val newRemaining = roundMoney(
                    (total - updatedPayments.sumOf { it.amount }).coerceAtLeast(0.0),
                )
                if (newRemaining <= 0.005) {
                    finalizeAfterCard = true
                    _checkoutState.update {
                        it.copy(
                            payments = updatedPayments,
                            amountInput = "",
                            pendingCheckoutPayments = updatedPayments,
                            pendingCheckoutTotal = total,
                            processingCheckoutMethod = checkoutFinalizeMethod(updatedPayments),
                        )
                    }
                } else {
                    _checkoutState.update {
                        it.copy(payments = updatedPayments, amountInput = "")
                    }
                }
            } finally {
                _checkoutState.update {
                    val cleared = it.copy(
                        processingCardPayment = null,
                        paymentProcessingProgress = 0f,
                    )
                    if (!finalizeAfterCard) {
                        cleared.copy(processingDialogMessage = null)
                    } else {
                        cleared
                    }
                }
                if (finalizeAfterCard) {
                    val pending = _checkoutState.value
                    beginFinalize(
                        payments = pending.pendingCheckoutPayments ?: return@launch,
                        registerTotal = pending.pendingCheckoutTotal ?: return@launch,
                        skipStateUpdate = true,
                    )
                }
            }
        }
    }

    private fun beginFinalize(
        payments: List<CheckoutPayment>,
        registerTotal: Double,
        skipStateUpdate: Boolean = false,
    ) {
        finalizeJob?.cancel()
        val method = checkoutFinalizeMethod(payments)
        val message = finalizeProcessingMessage(payments)
        val cardOnly = isCardOnlyCheckout(payments)
        if (!skipStateUpdate) {
            _checkoutState.update {
                it.copy(
                    payments = payments,
                    amountInput = "",
                    pendingCheckoutPayments = payments,
                    pendingCheckoutTotal = registerTotal,
                    processingCheckoutMethod = method,
                    processingDialogMessage = if (cardOnly) null else message,
                )
            }
        }
        finalizeJob = viewModelScope.launch {
            if (cardOnly) {
                _checkoutState.update {
                    it.copy(processingDialogMessage = null, paymentProcessingProgress = 0f)
                }
            } else {
                _checkoutState.update {
                    it.copy(paymentProcessingProgress = 0f, processingDialogMessage = message)
                }
                repeat(50) { index ->
                    delay(100)
                    _checkoutState.update { it.copy(paymentProcessingProgress = (index + 1) / 50f) }
                }
            }
            setPaymentMethod(method)
            checkout(payments = payments, checkoutTotal = registerTotal)
            resetCheckout()
        }
    }

    fun refresh() {
        if (!_state.value.isAuthenticated) return
        viewModelScope.launch {
            _state.value = _state.value.copy(loading = true, status = "Loading...")
            runCatching {
                val products = repository.products()
                val customers = repository.customers()
                val cartResp = repository.cart(_state.value.selectedCustomerId)
                val sales = repository.recentSales()
                FreshPos(products, customers, cartResp, sales)
            }.onSuccess { result ->
                val (products, customers, cartResp, sales) = result
                _state.value = _state.value.copy(
                    loading = false,
                    products = products,
                    customers = customers,
                    recentSales = sales,
                )
                applyCartResponse(cartResp, _state.value.customerDiscountActive())
            }.onFailure { err ->
                val authLost = err is HttpException && err.code() == 401
                _state.value = _state.value.copy(
                    loading = false,
                    isAuthenticated = !authLost,
                    status = when {
                        authLost -> "Session expired — sign in again"
                        else -> "Error: ${err.message ?: "Unable to connect"}"
                    },
                )
            }
        }
    }

    fun setSelectedCustomerId(id: Int?) {
        val customer = id?.let { cid -> _state.value.customers.find { it.id == cid } }
        _state.value = _state.value.copy(
            selectedCustomerId = id,
            selectedCustomerDiscount = id != null,
        )
        refreshCart()
    }

    fun linkCustomerById(customerId: Int) {
        val customer = _state.value.customers.find { it.id == customerId }
        if (customer == null) {
            _state.value = _state.value.copy(status = "Unknown customer id $customerId")
            return
        }
        setSelectedCustomerId(customerId)
        _state.value = _state.value.copy(
            status = "Linked ${customer.name} — customer discount",
        )
    }

    /** Reload cart lines and totals for the current (or cleared) customer link. */
    fun refreshCart() {
        if (!_state.value.isAuthenticated) return
        val customerId = _state.value.selectedCustomerId
        val discountAtRequest = _state.value.customerDiscountActive()
        val generation = ++cartRefreshGeneration
        viewModelScope.launch {
            _state.value = _state.value.copy(loading = true)
            runCatching { repository.cart(customerId) }
                .onSuccess { resp ->
                    if (generation != cartRefreshGeneration) return@onSuccess
                    applyCartResponse(resp, discountAtRequest)
                }
                .onFailure { err ->
                    if (generation != cartRefreshGeneration) return@onFailure
                    val authLost = err is HttpException && err.code() == 401
                    _state.value = _state.value.copy(
                        isAuthenticated = !authLost,
                        status = when {
                            authLost -> "Session expired — sign in again"
                            else -> "Cart refresh failed: ${err.message ?: "Unable to connect"}"
                        },
                    )
                }
            if (generation == cartRefreshGeneration) {
                _state.value = _state.value.copy(loading = false)
            }
        }
    }

    fun setPaymentMethod(method: String) {
        _state.value = _state.value.copy(paymentMethod = method)
    }

    fun setBarcodeInput(value: String) {
        _state.value = _state.value.copy(barcodeInput = value)
    }

    fun setPinInput(value: String) {
        if (value.length <= 8) {
            _state.value = _state.value.copy(pinInput = value)
        }
    }

    fun unlock() {
        val entered = _state.value.pinInput
        if (entered.isBlank()) {
            _state.value = _state.value.copy(status = "Enter PIN")
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(status = "Signing in...")
            runCatching { repository.unlockCashier(entered) }
                .onSuccess {
                    _state.value = _state.value.copy(
                        isAuthenticated = true,
                        pinInput = "",
                        status = "Signed in",
                    )
                    refresh()
                    flushOfflineQueue()
                }
                .onFailure { err ->
                    val msg = when (err) {
                        is HttpException -> when (err.code()) {
                            401 -> "Invalid PIN"
                            404 -> "Server needs update (missing login API)"
                            else -> "Server error (${err.code()})"
                        }
                        else -> when {
                            err.message?.contains("did not persist", ignoreCase = true) == true ->
                                err.message!!
                            else -> "Cannot reach server — check Wi‑Fi and API URL (${BuildConfig.API_BASE_URL})"
                        }
                    }
                    _state.value = _state.value.copy(
                        isAuthenticated = false,
                        status = msg,
                    )
                }
        }
    }

    fun lock() {
        viewModelScope.launch {
            runCatching { repository.logoutCashier() }
            _state.value = PosUiState(
                isAuthenticated = false,
                pinInput = "",
                barcodeInput = "",
                queuedCheckoutCount = queueStore.all().size,
                status = "Signed out",
            )
        }
    }

    fun addProduct(productId: Int) {
        viewModelScope.launch {
            val cid = _state.value.selectedCustomerId
            runCatching { repository.addProduct(productId, cid) }
                .onSuccess { applyCartResponse(it, _state.value.customerDiscountActive()) }
                .onFailure { err ->
                    val authLost = err is HttpException && err.code() == 401
                    _state.value = _state.value.copy(
                        isAuthenticated = !authLost,
                        status = when {
                            authLost -> "Session expired — sign in again"
                            else -> "Add failed: ${err.message}"
                        },
                    )
                }
        }
    }

    fun addByBarcode() {
        addByBarcodeValue(_state.value.barcodeInput)
    }

    fun addByBarcodeValue(input: String) {
        val cleaned = input.trim()
        if (cleaned.isEmpty()) {
            _state.value = _state.value.copy(status = "Enter barcode or product ID")
            return
        }

        val asId = cleaned.toIntOrNull()
        val treatAsId = asId != null && cleaned.length <= 6

        // Scan field adds products when the ID matches a product (even if the same number is a customer ID).
        // Link customers via Find customer when IDs overlap (e.g. product 2 and customer 2).
        if (treatAsId) {
            val hasProduct = _state.value.products.any { it.id == asId }
            val hasCustomer = _state.value.customers.any { it.id == asId }
            if (!hasProduct && hasCustomer) {
                linkCustomerById(asId)
                _state.value = _state.value.copy(barcodeInput = "")
                return
            }
        }

        viewModelScope.launch {
            val cid = _state.value.selectedCustomerId
            runCatching {
                if (treatAsId) repository.addProduct(asId!!, cid) else repository.addProductByBarcode(cleaned, cid)
            }
                .onSuccess { resp ->
                    applyCartResponse(resp, _state.value.customerDiscountActive())
                    _state.value = _state.value.copy(
                        barcodeInput = "",
                        status = if (treatAsId) "Added by id $cleaned" else "Scanned $cleaned",
                    )
                }
                .onFailure { err ->
                    val authLost = err is HttpException && err.code() == 401
                    _state.value = _state.value.copy(
                        isAuthenticated = !authLost,
                        status = when {
                            authLost -> "Session expired — sign in again"
                            else -> "Add failed: ${err.message}"
                        },
                    )
                }
        }
    }

    private fun applyCartResponse(
        resp: CartResponse,
        customerDiscount: Boolean = _state.value.customerDiscountActive(),
    ) {
        val items = normalizeCartItems(resp.items, customerDiscount)
        val totals = computeCartTotals(items, customerDiscount)
        val status = when {
            customerDiscount && !resp.linked893 ->
                "Customer linked — pricing may be stale; try Unlink and link again"
            customerDiscount && totals.memberDiscount < 0.005 && items.isNotEmpty() ->
                "Customer linked — no discount on cart lines yet"
            customerDiscount -> "Customer discount applied"
            _state.value.status == "Loading..." -> "Ready"
            else -> _state.value.status
        }
        _state.value = _state.value.copy(
            cart = items,
            subtotalPreMember = totals.shelfSubtotal,
            subtotalPayable = totals.itemPreTax,
            memberDiscountPreTax = totals.memberDiscount,
            linked893Cart = customerDiscount && resp.linked893,
            status = status,
        )
    }

    fun removeCartItem(cartItemId: Int) {
        if (_state.value.quantityEditCartItemId == cartItemId) {
            cancelQuantityEdit()
        }
        viewModelScope.launch {
            val cid = _state.value.selectedCustomerId
            runCatching { repository.removeCartItem(cartItemId, cid) }
                .onSuccess { applyCartResponse(it, _state.value.customerDiscountActive()) }
                .onFailure { _state.value = _state.value.copy(status = "Remove failed: ${it.message}") }
        }
    }

    fun startQuantityEdit(cartItemId: Int) {
        if (_checkoutState.value.saleItemsLocked) return
        _state.value = _state.value.copy(
            quantityEditCartItemId = cartItemId,
            quantityEditInput = "",
            barcodeInput = "",
        )
    }

    fun cancelQuantityEdit() {
        _state.value = _state.value.copy(
            quantityEditCartItemId = null,
            quantityEditInput = "",
        )
    }

    fun setQuantityEditInput(value: String) {
        _state.value = _state.value.copy(quantityEditInput = value.filter { it.isDigit() }.take(4))
    }

    fun appendQuantityEditDigit(digit: Char) {
        val current = _state.value.quantityEditInput
        if (current.length >= 4) return
        val next = if (current == "0") digit.toString() else current + digit
        _state.value = _state.value.copy(quantityEditInput = next)
    }

    fun backspaceQuantityEditInput() {
        _state.value = _state.value.copy(
            quantityEditInput = _state.value.quantityEditInput.dropLast(1),
        )
    }

    fun applyQuantityEdit() {
        val itemId = _state.value.quantityEditCartItemId ?: return
        val qty = _state.value.quantityEditInput.toIntOrNull()
        if (qty == null) {
            _state.value = _state.value.copy(status = "Enter a quantity")
            return
        }
        cancelQuantityEdit()
        viewModelScope.launch {
            val cid = _state.value.selectedCustomerId
            val result = if (qty <= 0) {
                runCatching { repository.removeCartItem(itemId, cid) }
            } else {
                runCatching { repository.updateCartItemQuantity(itemId, qty, cid) }
            }
            result
                .onSuccess { applyCartResponse(it, _state.value.customerDiscountActive()) }
                .onFailure { err ->
                    _state.value = _state.value.copy(
                        status = if (qty <= 0) {
                            "Remove failed: ${err.message}"
                        } else {
                            "Quantity update failed: ${err.message}"
                        },
                    )
                }
        }
    }

    private fun effectivePaymentMethod(
        fallbackMethod: String,
        payments: List<CheckoutPayment>?,
    ): String {
        val normalized = payments?.takeIf { it.isNotEmpty() } ?: return fallbackMethod
        return if (normalized.size == 1) {
            normalized.first().method
        } else {
            "split"
        }
    }

    fun checkout(
        payments: List<CheckoutPayment>? = null,
        checkoutTotal: Double? = null,
    ) {
        viewModelScope.launch {
            if (_state.value.cart.isEmpty()) {
                _state.value = _state.value.copy(status = "Cart is empty")
                return@launch
            }

            val paymentMethod = effectivePaymentMethod(_state.value.paymentMethod, payments)
            val customerId = _state.value.selectedCustomerId
            runCatching { repository.checkout(paymentMethod, customerId, payments, checkoutTotal) }
                .onSuccess { receipt ->
                    val extra = buildList {
                        if (receipt.linked893 == true) add("customer discount")
                        receipt.memberDiscountPreTax?.takeIf { it > 0.001 }?.let { add("−${"%.2f".format(it)} pre-tax") }
                    }.joinToString(" · ").takeIf { it.isNotEmpty() }
                    val msg = listOfNotNull("Sale complete: ${receipt.orderNumber}", extra).joinToString(" — ")
                    setSelectedCustomerId(null)
                    _state.value = _state.value.copy(status = msg)
                    refresh()
                }
                .onFailure { err ->
                    val authLost = err is HttpException && err.code() == 401
                    if (authLost) {
                        _state.value = _state.value.copy(
                            isAuthenticated = false,
                            status = "Session expired — sign in again",
                        )
                        return@onFailure
                    }

                    val isOfflineLike = err is IOException
                    if (!isOfflineLike) {
                        val serverMsg = when (err) {
                            is HttpException -> "Checkout failed (${err.code()})"
                            else -> "Checkout failed: ${err.message ?: "Unknown error"}"
                        }
                        _state.value = _state.value.copy(status = serverMsg)
                        return@onFailure
                    }

                    val lines = _state.value.cart.map { QueuedCartLine(it.productId, it.quantity) }
                    queueStore.enqueue(paymentMethod, customerId, lines, payments, checkoutTotal)
                    _state.value = _state.value.copy(
                        status = "Offline: checkout queued",
                        queuedCheckoutCount = queueStore.all().size,
                    )
                }
        }
    }

    fun flushOfflineQueue() {
        viewModelScope.launch {
            val queued = queueStore.all()
            if (queued.isEmpty()) {
                _state.value = _state.value.copy(queuedCheckoutCount = 0, status = "No queued checkouts")
                return@launch
            }

            _state.value = _state.value.copy(queueSyncing = true, status = "Syncing ${queued.size} queued…")

            var synced = 0
            var droppedStale = 0
            var droppedPermanent = 0
            val remaining = mutableListOf<PendingCheckout>()
            var lastError: String? = null

            for (pending in queued) {
                if (pending.cartLines.isEmpty()) {
                    droppedStale++
                    continue
                }
                val result = runCatching {
                    repository.replaceCart(pending.cartLines, pending.customerId)
                    repository.checkout(
                        pending.paymentMethod,
                        pending.customerId,
                        pending.payments,
                        pending.checkoutTotal,
                    )
                }
                if (result.isSuccess) {
                    synced++
                } else {
                    val err = result.exceptionOrNull()
                    val retryable = err is IOException
                    if (retryable) {
                        remaining.add(pending)
                    } else {
                        droppedPermanent++
                    }
                    lastError = when (err) {
                        is HttpException -> "HTTP ${err.code()}"
                        else -> err?.message
                    }
                }
            }

            queueStore.replace(remaining)
            val msg = buildString {
                if (synced > 0) append("Synced $synced sale(s)")
                if (droppedStale > 0) {
                    if (isNotEmpty()) append(" · ")
                    append("dropped $droppedStale old entries (no cart saved)")
                }
                if (droppedPermanent > 0) {
                    if (isNotEmpty()) append(" · ")
                    append("dropped $droppedPermanent invalid entries")
                }
                if (remaining.isNotEmpty()) {
                    if (isNotEmpty()) append(" · ")
                    append("${remaining.size} still pending")
                    lastError?.let { append(": $it") }
                }
                if (isEmpty()) append("Nothing to sync")
            }

            refresh()
            _state.value = _state.value.copy(
                queueSyncing = false,
                queuedCheckoutCount = remaining.size,
                status = msg,
            )
        }
    }

    fun clearOfflineQueue() {
        queueStore.clear()
        _state.value = _state.value.copy(
            queuedCheckoutCount = 0,
            status = "Offline queue cleared",
        )
    }

}

class PosViewModelFactory(
    private val repository: PosRepository,
    private val queueStore: OfflineQueueStore,
) : ViewModelProvider.Factory {
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(PosViewModel::class.java)) {
            @Suppress("UNCHECKED_CAST")
            return PosViewModel(repository, queueStore) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class")
    }
}
