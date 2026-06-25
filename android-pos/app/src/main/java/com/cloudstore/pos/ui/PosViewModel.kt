package com.cloudstore.pos.ui

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.cloudstore.pos.data.CartItem
import com.cloudstore.pos.data.CartResponse
import com.cloudstore.pos.data.CashierSessionResponse
import com.cloudstore.pos.data.CloseTillPreviewResponse
import com.cloudstore.pos.data.SubmitCloseTillRequest
import com.cloudstore.pos.data.SubmitOpeningTillRequest
import com.cloudstore.pos.data.TillConfigResponse
import com.cloudstore.pos.data.TillDenomination
import com.cloudstore.pos.data.CashierUserStore
import com.cloudstore.pos.data.CheckoutPayment
import com.cloudstore.pos.data.OfflineQueueStore
import com.cloudstore.pos.data.PosIdentityLog
import com.cloudstore.pos.data.PendingCheckout
import com.cloudstore.pos.data.QueuedCartLine
import com.cloudstore.pos.data.PosRepository
import com.cloudstore.pos.data.Product
import com.cloudstore.pos.data.Sale
import com.cloudstore.pos.data.StoreCustomer
import com.cloudstore.pos.domain.checkout.balanceDueForMethod
import com.cloudstore.pos.domain.checkout.buildCheckoutPaymentLine
import com.cloudstore.pos.domain.checkout.cardTerminalMessage
import com.cloudstore.pos.domain.checkout.checkoutFinalizeMethod
import com.cloudstore.pos.domain.checkout.finalizeProcessingMessage
import com.cloudstore.pos.domain.checkout.isCheckoutComplete
import com.cloudstore.pos.domain.checkout.parseCashTendered
import com.cloudstore.pos.domain.checkout.paymentMethodLabel
import com.cloudstore.pos.domain.network.NetworkErrorLogic
import com.cloudstore.pos.domain.pricing.collectedTotal
import com.cloudstore.pos.domain.pricing.computeCartTotals
import com.cloudstore.pos.domain.pricing.computeSaleGrandTotal
import com.cloudstore.pos.domain.pricing.normalizeCartItems
import com.cloudstore.pos.domain.receipt.SaleReceipt
import com.cloudstore.pos.domain.receipt.buildSaleReceipt
import com.cloudstore.pos.domain.receipt.customerDisplayName
import com.cloudstore.pos.BuildConfig
import java.io.IOException
import kotlinx.coroutines.CancellationException
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

private const val APPROVAL_POLL_MS = 2500L

sealed class CashierAuthGate {
    data object Checking : CashierAuthGate()
    data object SignedIn : CashierAuthGate()
    data object OidcSignIn : CashierAuthGate()
    data class PinSignIn(
        val pinAllowed: Boolean = false,
    ) : CashierAuthGate()
    data class WaitingApproval(
        val email: String? = null,
        val secondsRemaining: Int? = null,
        val cashMode: String? = null,
        val expectedOpeningFloat: Double? = null,
        val openingCountedFloat: Double? = null,
        val openingVariance: Double? = null,
    ) : CashierAuthGate()
    data class OpeningTill(
        val expectedOpeningFloat: Double? = null,
        val denominations: List<TillDenomination> = emptyList(),
        val counts: Map<String, String> = emptyMap(),
        val selectedDenominationId: String? = null,
        val submitting: Boolean = false,
    ) : CashierAuthGate()
    data class ClosingTill(
        val expectedCloseFloat: Double? = null,
        val openingCountedFloat: Double? = null,
        val cashSalesTotal: Double? = null,
        val changeGivenTotal: Double? = null,
        val denominations: List<TillDenomination> = emptyList(),
        val counts: Map<String, String> = emptyMap(),
        val selectedDenominationId: String? = null,
        val submitting: Boolean = false,
    ) : CashierAuthGate()
    data class ClosingCreditOnly(
        val submitting: Boolean = false,
    ) : CashierAuthGate()
    data class WaitingCloseApproval(
        val closeToken: String? = null,
        val secondsRemaining: Int? = null,
        val cashMode: String? = null,
        val expectedCloseFloat: Double? = null,
        val countedCloseFloat: Double? = null,
        val closeVariance: Double? = null,
    ) : CashierAuthGate()
}

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
    val addItemError: String? = null,
    val quantityEditCartItemId: Int? = null,
    val quantityEditInput: String = "",
    val status: String = "Ready",
    val isAuthenticated: Boolean = false,
    val loggedInUser: String? = null,
    val authGate: CashierAuthGate = CashierAuthGate.Checking,
    val idpLoginUrl: String? = null,
    val pinAllowed: Boolean = false,
    val supervisorApprovalRequired: Boolean = true,
    val idpEnabled: Boolean = false,
    val pinInput: String = "",
    val queuedCheckoutCount: Int = 0,
    val queueSyncing: Boolean = false,
    val cashEnabled: Boolean = true,
    val cashMode: String? = null,
    val tillId: Int? = null,
    val posSessionId: Int? = null,
    val receipt: SaleReceipt? = null,
    val receiptPrintMessage: String? = null,
    val receiptPrintProgress: Float = 0f,
) {
    fun selectedCustomer(): StoreCustomer? =
        selectedCustomerId?.let { id -> customers.find { it.id == id } }

    /** True when a linked customer should receive the pre-tax discount. */
    fun customerDiscountActive(): Boolean = selectedCustomerId != null

    fun customerLinked(): Boolean = selectedCustomerId != null

    /** Credit-only shift: exact balance payments only (no cash, no round-up quick amounts). */
    fun creditOnlyPayments(): Boolean = cashMode == "credit_only" || !cashEnabled
}

class PosViewModel(
    private val repository: PosRepository,
    private val queueStore: OfflineQueueStore,
    private val userStore: CashierUserStore,
    private val registerId: String,
) : ViewModel() {
    private data class FreshPos(
        val products: List<Product>,
        val customers: List<StoreCustomer>,
        val cart: CartResponse,
        val sales: List<Sale>,
    )

    private val _state = MutableStateFlow(PosUiState())
    val state: StateFlow<PosUiState> = _state.asStateFlow()
    private var requireFreshIdpLogin = false

    private val _checkoutState = MutableStateFlow(CheckoutUiState())
    val checkoutState: StateFlow<CheckoutUiState> = _checkoutState.asStateFlow()

    private val salesFeeRate = BuildConfig.POS_SALES_FEE_RATE.toDoubleOrNull() ?: 0.0
    private val taxRate = BuildConfig.POS_TAX_RATE.toDoubleOrNull() ?: 0.0

    private var cartRefreshGeneration = 0
    private var cardProcessingJob: Job? = null
    private var finalizeJob: Job? = null
    private var printReceiptJob: Job? = null
    private var approvalPollJob: Job? = null
    private var closePollJob: Job? = null
    private var oidcCompleting = false
    /** True only after Oracle WebView finishes in this app session — blocks stale till resume on launch. */
    private var oidcAuthStepCompletedThisSession = false

    init {
        val storedUser = userStore.get()
        PosIdentityLog.d("init storedUser=${storedUser ?: "null"}")
        _state.update {
            it.copy(
                queuedCheckoutCount = queueStore.all().size,
                loggedInUser = storedUser,
            )
        }
        probeCashierSession()
        viewModelScope.launch {
            state.map { it.isAuthenticated }
                .distinctUntilChanged()
                .collect { authed ->
                    if (!authed) {
                        resetCheckout()
                        _state.update { it.copy(receipt = null) }
                    }
                }
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
                    if (status.startsWith("Sale complete")) {
                        resetCheckout()
                    }
                }
        }
    }

    fun dismissReceipt() {
        printReceiptJob?.cancel()
        printReceiptJob = null
        _state.update { it.copy(receipt = null, receiptPrintMessage = null, receiptPrintProgress = 0f, status = "Ready") }
        refresh()
    }

    fun printReceipt() {
        if (_state.value.receipt == null || printReceiptJob?.isActive == true) return
        printReceiptJob = viewModelScope.launch {
            _state.update { it.copy(receiptPrintMessage = "Printing Receipt", receiptPrintProgress = 0f) }
            repeat(20) { index ->
                delay(100)
                _state.update { it.copy(receiptPrintProgress = (index + 1) / 20f) }
            }
            dismissReceipt()
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
        _checkoutState.value = CheckoutUiState(
            open = true,
            amountInput = "0",
        )
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
        val remainingAmount = balanceDueForMethod(registerTotal, current.payments, method)
        if (remainingAmount <= 0.005) return
        val enteredAmount = parseCashTendered(current.amountInput) ?: run {
            _state.update {
                it.copy(status = "Enter a valid amount for ${paymentMethodLabel(method)}")
            }
            return
        }
        applyCheckoutPayment(method = method, enteredAmount = enteredAmount, remainingAmount = remainingAmount)
    }

    fun applyCardOnFilePayment() {
        val current = _checkoutState.value
        val registerTotal = registerTotal()
        val remainingAmount = balanceDueForMethod(registerTotal, current.payments, "card")
        if (remainingAmount <= 0.005) return
        val enteredAmount = parseCashTendered(current.amountInput) ?: run {
            _state.update {
                it.copy(status = "Enter a valid amount for ${paymentMethodLabel("card")}")
            }
            return
        }
        applyCheckoutPayment(method = "card", enteredAmount = enteredAmount, remainingAmount = remainingAmount)
    }

    private fun applyCheckoutPayment(
        method: String,
        enteredAmount: Double,
        remainingAmount: Double,
    ) {
        val current = _checkoutState.value
        val registerTotal = registerTotal()
        val payment = buildCheckoutPaymentLine(method, enteredAmount, remainingAmount)
        if (payment == null) {
            _state.update {
                it.copy(status = "Enter a valid amount for ${paymentMethodLabel(method)}")
            }
            return
        }
        _checkoutState.update { it.copy(saleItemsLocked = true) }
        if (method == "card") {
            processCardPayment(payment)
        } else {
            val updatedPayments = current.payments + payment
            if (isCheckoutComplete(registerTotal, updatedPayments)) {
                beginFinalize(updatedPayments, registerTotal)
            } else {
                _checkoutState.update {
                    it.copy(payments = updatedPayments, amountInput = "0")
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
                repeat(20) { index ->
                    delay(100)
                    _checkoutState.update { it.copy(paymentProcessingProgress = (index + 1) / 20f) }
                }
                val updatedPayments = _checkoutState.value.payments + payment
                val total = registerTotal()
                if (isCheckoutComplete(total, updatedPayments)) {
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
                        it.copy(payments = updatedPayments, amountInput = "0")
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
        if (!skipStateUpdate) {
            _checkoutState.update {
                it.copy(
                    payments = payments,
                    amountInput = "",
                    pendingCheckoutPayments = payments,
                    pendingCheckoutTotal = registerTotal,
                    processingCheckoutMethod = method,
                    processingDialogMessage = null,
                )
            }
        }
        finalizeJob = viewModelScope.launch {
            _checkoutState.update {
                it.copy(processingDialogMessage = finalizeProcessingMessage(payments))
            }
            setPaymentMethod(method)
            performCheckout(
                payments = payments,
                checkoutTotal = collectedTotal(registerTotal),
            )
            resetCheckout()
        }
    }

    private suspend fun performCheckout(
        payments: List<CheckoutPayment>? = null,
        checkoutTotal: Double? = null,
    ) {
        if (_state.value.cart.isEmpty()) {
            _state.value = _state.value.copy(status = "Cart is empty")
            return
        }

        val snapshotState = _state.value
        val paymentMethod = payments
            ?.takeIf { it.isNotEmpty() }
            ?.let { checkoutFinalizeMethod(it) }
            ?: snapshotState.paymentMethod
        val customerId = snapshotState.selectedCustomerId
        val paymentsUsed = payments.orEmpty()
        val customerName = snapshotState.selectedCustomer()?.let { customer ->
            customerDisplayName(customer, customer.id)
        }
        runCatching { repository.checkout(paymentMethod, customerId, payments, checkoutTotal) }
            .onSuccess { response ->
                val receipt = buildSaleReceipt(
                    cart = snapshotState.cart,
                    customerName = customerName,
                    customerLinked = snapshotState.customerLinked(),
                    customerDiscount = snapshotState.customerDiscountActive(),
                    salesFeeRate = salesFeeRate,
                    taxRate = taxRate,
                    payments = paymentsUsed.ifEmpty {
                        response.payments.orEmpty()
                    },
                    orderNumber = response.orderNumber,
                )
                setSelectedCustomerId(null)
                _state.value = snapshotState.copy(
                    receipt = receipt,
                    status = "Ready",
                    selectedCustomerId = null,
                    selectedCustomerDiscount = false,
                )
                refresh()
            }
            .onFailure { err ->
                val authLost = err is HttpException && err.code() == 401
                if (authLost) {
                    _state.value = _state.value.copy(
                        isAuthenticated = false,
                        status = "Session expired — sign in again",
                    )
                    return
                }

                if (!NetworkErrorLogic.isOfflineLike(err)) {
                    val serverMsg = when (err) {
                        is HttpException -> NetworkErrorLogic.httpErrorMessage(err, "Checkout failed")
                        else -> "Checkout failed: ${err.message ?: "Unknown error"}"
                    }
                    _state.value = _state.value.copy(status = serverMsg)
                    return
                }

                val lines = _state.value.cart.map { QueuedCartLine(it.productId, it.quantity) }
                val offlineSnapshot = _state.value
                val offlineCustomerName = offlineSnapshot.selectedCustomer()?.let { customer ->
                    customerDisplayName(customer, customer.id)
                }
                queueStore.enqueue(paymentMethod, customerId, lines, payments, checkoutTotal)
                val receipt = buildSaleReceipt(
                    cart = offlineSnapshot.cart,
                    customerName = offlineCustomerName,
                    customerLinked = offlineSnapshot.customerLinked(),
                    customerDiscount = offlineSnapshot.customerDiscountActive(),
                    salesFeeRate = salesFeeRate,
                    taxRate = taxRate,
                    payments = paymentsUsed,
                    queuedOffline = true,
                )
                _state.value = offlineSnapshot.copy(
                    receipt = receipt,
                    status = "Sale queued offline — tap Sync queued when online",
                    queuedCheckoutCount = queueStore.all().size,
                    selectedCustomerId = null,
                    selectedCustomerDiscount = false,
                )
            }
    }

    fun syncCashierIdentity() {
        if (!_state.value.isAuthenticated) {
            PosIdentityLog.d("syncCashierIdentity skipped — not authenticated")
            return
        }
        viewModelScope.launch {
            PosIdentityLog.d("syncCashierIdentity fetching /api/cashier/session")
            runCatching { repository.cashierSession() }
                .onSuccess { session ->
                    PosIdentityLog.session("syncCashierIdentity", session)
                    if (!session.ok) {
                        PosIdentityLog.d("syncCashierIdentity session ok=false")
                        return@onSuccess
                    }
                    val user = rememberCashierUserFromSession(session, _state.value)
                        ?: _state.value.loggedInUser
                        ?: userStore.get()
                    PosIdentityLog.resolved(
                        "syncCashierIdentity",
                        user,
                        userStore.get(),
                        _state.value.loggedInUser,
                    )
                    if (!user.isNullOrBlank()) {
                        userStore.save(user)
                    }
                    _state.update {
                        it.copy(
                            loggedInUser = user?.takeIf { name -> !name.isBlank() } ?: it.loggedInUser,
                            cashEnabled = resolveCashEnabled(session),
                            cashMode = session.cashMode,
                            tillId = session.tillId,
                            posSessionId = session.posSessionId,
                        )
                    }
                }
                .onFailure { err ->
                    PosIdentityLog.d("syncCashierIdentity failed: ${err.message}")
                }
        }
    }

    fun refresh() {
        if (!_state.value.isAuthenticated) return
        syncCashierIdentity()
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
                if (authLost) {
                    repository.clearCashierCookies()
                    showSignInGateFromCachedAuth("Session expired — sign in again")
                } else {
                    _state.value = _state.value.copy(
                        loading = false,
                        status = "Error: ${err.message ?: "Unable to connect"}",
                    )
                }
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
        _state.value = _state.value.copy(barcodeInput = value, addItemError = null)
    }

    fun setPinInput(value: String) {
        if (value.length <= 8) {
            _state.value = _state.value.copy(pinInput = value)
        }
    }

    fun openOidcSignIn() {
        if (requireFreshIdpLogin) {
            repository.clearWebViewIdpSession()
        }
        repository.clearPinnedPendingRequest()
        _state.update {
            it.copy(
                authGate = CashierAuthGate.OidcSignIn,
                idpLoginUrl = resolveIdpLoginUrl("/oauth/login"),
                status = "Signing in…",
            )
        }
    }

    fun cancelOidcSignIn() {
        oidcAuthStepCompletedThisSession = false
        _state.update {
            val idpUrl = it.idpLoginUrl ?: resolveIdpLoginUrl("/oauth/login")
            val pinOk = effectivePinAllowedCached(
                pinAllowed = it.pinAllowed,
                supervisorApprovalRequired = it.supervisorApprovalRequired,
                idpEnabled = it.idpEnabled || idpUrl != null,
                idpLoginUrl = idpUrl,
            )
            it.copy(
                authGate = CashierAuthGate.PinSignIn(pinAllowed = pinOk),
                status = "Ready",
            )
        }
    }

    fun onOidcWebViewComplete(completionUrl: String) {
        if (oidcCompleting) return
        oidcCompleting = true
        val isResume = isCashierResumeRedirect(completionUrl)
        val awaitingTill = isAwaitingTillRedirect(completionUrl)
        val pendingToken = when {
            isResume || awaitingTill -> null
            else -> parsePendingRequestToken(completionUrl)
        }
        oidcAuthStepCompletedThisSession = awaitingTill || isResume || !pendingToken.isNullOrBlank()
        if (awaitingTill) {
            repository.clearPinnedPendingRequest()
        }
        if (!pendingToken.isNullOrBlank()) {
            repository.rememberPendingRequestToken(pendingToken)
        }
        _state.update {
            it.copy(
                isAuthenticated = false,
                authGate = CashierAuthGate.Checking,
                idpLoginUrl = resolveIdpLoginUrl("/oauth/login"),
                status = "Completing sign-in…",
            )
        }
        viewModelScope.launch {
            try {
                syncWebViewCookiesWithRetry()
                if (awaitingTill) {
                    repository.clearPinnedPendingRequest()
                    repository.pinAwaitingTillFromWebView()
                } else if (!pendingToken.isNullOrBlank()) {
                    repository.rememberPendingRequestToken(pendingToken)
                }
                runCatching { repository.cashierSession() }
                    .onSuccess { session ->
                        repository.applySessionAuth(session)
                        if (awaitingTill && session.pending) {
                            repository.clearPinnedPendingRequest()
                            repository.pinAwaitingTillFromWebView()
                            val retry = runCatching { repository.cashierSession() }.getOrNull()
                            applySessionProbe(retry ?: session)
                        } else {
                            applySessionProbe(session)
                        }
                    }
                    .onFailure { err ->
                        showSignInGateFromCachedAuth(connectivityMessage(err))
                    }
            } finally {
                oidcCompleting = false
            }
        }
    }

    private fun enterWaitingApprovalFromToken(pendingToken: String?) {
        if (pendingToken.isNullOrBlank() && !repository.hasPendingRequestCookie()) {
            showSignInGateFromCachedAuth("Sign-in incomplete — tap Oracle sign-in again")
            return
        }
        _state.update {
            it.copy(
                isAuthenticated = false,
                authGate = CashierAuthGate.WaitingApproval(
                    email = null,
                    secondsRemaining = null,
                ),
                idpLoginUrl = resolveIdpLoginUrl("/oauth/login"),
                status = "Waiting for supervisor approval",
            )
        }
        startApprovalPoll()
    }

    fun cancelApprovalWait() {
        viewModelScope.launch {
            stopApprovalPoll()
            _state.update { it.copy(status = "Cancelling…") }
            runCatching { repository.cancelApproval() }
            repository.clearCashierCookies()
            showSignInGateFromCachedAuth("Login request cancelled")
        }
    }

    private fun probeCashierSession() {
        viewModelScope.launch {
            _state.update {
                it.copy(
                    authGate = CashierAuthGate.Checking,
                    isAuthenticated = false,
                    loggedInUser = it.loggedInUser ?: userStore.get(),
                    status = "Checking session…",
                )
            }
            PosIdentityLog.d(
                "probeCashierSession hasSessionCookie=${repository.hasCashierSessionCookie()} " +
                    "storedUser=${userStore.get() ?: "null"}",
            )
            repository.syncWebViewCookies()
            runCatching { repository.cashierSession() }
                .onSuccess { session ->
                    repository.applySessionAuth(session)
                    PosIdentityLog.session("probeCashierSession", session)
                    applySessionProbe(session)
                }
                .onFailure { err ->
                    PosIdentityLog.d("probeCashierSession failed: ${err.message}")
                    showSignInGateFromCachedAuth(connectivityMessage(err))
                }
        }
    }

    private suspend fun clearStaleSignInState(status: String) {
        oidcAuthStepCompletedThisSession = false
        repository.clearStaleSignInCookies()
        showSignInGateFromCachedAuth(status)
    }

    private fun resolveLoggedInUser(session: CashierSessionResponse, current: PosUiState): String? {
        session.displayUser()?.let { return it }
        (current.authGate as? CashierAuthGate.WaitingApproval)?.email
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.let { return it }
        userStore.get()?.let { return it }
        return if (session.auth == "pin") "Cashier" else null
    }

    private fun rememberCashierUser(user: String?) {
        val trimmed = user?.trim()?.takeIf { it.isNotEmpty() } ?: return
        PosIdentityLog.d("rememberCashierUser $trimmed")
        userStore.save(trimmed)
        _state.update { it.copy(loggedInUser = trimmed) }
    }

    private fun rememberCashierUserFromSession(session: CashierSessionResponse, current: PosUiState): String? {
        val resolved = resolveLoggedInUser(session, current)
        resolved?.let { userStore.save(it) }
        return resolved ?: current.loggedInUser ?: userStore.get()
    }

    private fun rememberCashierUserFromApproval(email: String?, name: String? = null) {
        listOf(email, name).forEach { candidate ->
            candidate?.trim()?.takeIf { it.isNotEmpty() }?.let {
                rememberCashierUser(it)
                return
            }
        }
    }

    fun noteCashierIdentity(email: String?, name: String? = null) {
        rememberCashierUserFromApproval(email, name)
    }

    private fun resolveCashEnabled(session: CashierSessionResponse): Boolean {
        when (session.cashMode) {
            "credit_only" -> return false
            "cash_and_credit" -> return true
        }
        session.cashEnabled?.let { return it }
        return !session.cashTillEnabled
    }

    private fun waitingApprovalFromSession(session: CashierSessionResponse): CashierAuthGate.WaitingApproval {
        val approval = session.approval
        return CashierAuthGate.WaitingApproval(
            email = approval?.cashierEmail,
            secondsRemaining = approval?.secondsRemaining,
            cashMode = approval?.cashMode,
            expectedOpeningFloat = approval?.expectedOpeningFloat,
            openingCountedFloat = approval?.openingCountedFloat,
            openingVariance = approval?.openingVariance,
        )
    }

    private fun waitingApprovalFromPoll(
        current: CashierAuthGate.WaitingApproval,
        status: com.cloudstore.pos.data.ApprovalStatusResponse,
    ): CashierAuthGate.WaitingApproval = current.copy(
        email = status.email ?: status.cashierEmail ?: current.email,
        secondsRemaining = status.secondsRemaining ?: current.secondsRemaining,
        cashMode = status.cashMode ?: current.cashMode,
        expectedOpeningFloat = status.expectedOpeningFloat ?: current.expectedOpeningFloat,
        openingCountedFloat = status.openingCountedFloat ?: current.openingCountedFloat,
        openingVariance = status.openingVariance ?: current.openingVariance,
    )

    private fun enterOpeningTill(config: TillConfigResponse) {
        stopApprovalPoll()
        _state.update {
            it.copy(
                isAuthenticated = false,
                authGate = CashierAuthGate.OpeningTill(
                    expectedOpeningFloat = config.expectedOpeningFloat,
                    denominations = config.denominations,
                    selectedDenominationId = config.denominations.firstOrNull()?.id,
                ),
                idpLoginUrl = if (it.idpLoginUrl != null) it.idpLoginUrl else resolveIdpLoginUrl("/oauth/login"),
                status = "Count opening till",
            )
        }
    }

    private fun openingTillGate(): CashierAuthGate.OpeningTill? =
        _state.value.authGate as? CashierAuthGate.OpeningTill

    fun selectTillDenomination(denominationId: String) {
        _state.update { state ->
            val gate = state.authGate as? CashierAuthGate.OpeningTill ?: return@update state
            state.copy(authGate = gate.copy(selectedDenominationId = denominationId))
        }
    }

    fun appendTillDigit(digit: Char) {
        val gate = openingTillGate() ?: return
        val id = gate.selectedDenominationId ?: return
        val current = gate.counts[id].orEmpty()
        if (current.length >= 4) return
        val next = if (current == "0") digit.toString() else current + digit
        updateTillCount(id, next)
    }

    fun confirmTillCount() {
        selectNextTillDenomination()
    }

    fun selectNextTillDenomination() {
        advanceTillDenomination()
    }

    fun selectPreviousTillDenomination() {
        _state.update { state ->
            val gate = state.authGate as? CashierAuthGate.OpeningTill ?: return@update state
            val denoms = gate.denominations
            if (denoms.isEmpty()) return@update state
            val currentIdx = denoms.indexOfFirst { it.id == gate.selectedDenominationId }
            val prevIdx = if (currentIdx <= 0) denoms.lastIndex else currentIdx - 1
            state.copy(authGate = gate.copy(selectedDenominationId = denoms[prevIdx].id))
        }
    }

    private fun advanceTillDenomination() {
        _state.update { state ->
            val gate = state.authGate as? CashierAuthGate.OpeningTill ?: return@update state
            val denoms = gate.denominations
            if (denoms.isEmpty()) return@update state
            val currentIdx = denoms.indexOfFirst { it.id == gate.selectedDenominationId }
            val nextIdx = if (currentIdx < 0) 0 else (currentIdx + 1) % denoms.size
            state.copy(authGate = gate.copy(selectedDenominationId = denoms[nextIdx].id))
        }
    }

    fun clearTillCount() {
        val id = openingTillGate()?.selectedDenominationId ?: return
        updateTillCount(id, "")
    }

    fun backspaceTillCount() {
        val gate = openingTillGate() ?: return
        val id = gate.selectedDenominationId ?: return
        updateTillCount(id, gate.counts[id].orEmpty().dropLast(1))
    }

    private fun loadOpeningTillGate() {
        viewModelScope.launch {
            runCatching { repository.tillConfig() }
                .onSuccess { enterOpeningTill(it) }
                .onFailure { err ->
                    showSignInGateFromCachedAuth(connectivityMessage(err))
                }
        }
    }

    fun updateTillCount(denominationId: String, value: String) {
        _state.update { state ->
            val gate = state.authGate as? CashierAuthGate.OpeningTill ?: return@update state
            state.copy(
                authGate = gate.copy(counts = gate.counts + (denominationId to value)),
            )
        }
    }

    fun submitOpeningTill() {
        val gate = _state.value.authGate as? CashierAuthGate.OpeningTill ?: return
        val nonEmptyCounts = gate.counts
            .mapNotNull { (id, raw) ->
                val count = raw.toIntOrNull() ?: 0
                if (count > 0) id to count else null
            }
            .toMap()
        val countedTotal = sumTillCounts(gate.denominations, gate.counts)
        submitTillRequest(
            cashMode = "cash_and_credit",
            denominations = nonEmptyCounts,
            countedTotal = countedTotal,
        )
    }

    fun submitNoCashToday() {
        submitTillRequest(cashMode = "credit_only")
    }

    fun cancelOpeningTill() {
        viewModelScope.launch {
            stopApprovalPoll()
            oidcAuthStepCompletedThisSession = false
            runCatching { repository.cancelOpeningTill() }
            repository.clearCashierCookies()
            repository.clearWebViewIdpSession()
            showSignInGateFromCachedAuth("Sign-in cancelled")
        }
    }

    private fun submitTillRequest(
        cashMode: String,
        denominations: Map<String, Int>? = null,
        countedTotal: Double? = null,
    ) {
        viewModelScope.launch {
            _state.update { state ->
                val gate = state.authGate as? CashierAuthGate.OpeningTill ?: return@launch
                state.copy(authGate = gate.copy(submitting = true), status = "Submitting till count…")
            }
            val result = runCatching { postOpeningTillWithRetry(cashMode, denominations, countedTotal) }
            result.onSuccess { response ->
                if (response.pending) {
                    oidcAuthStepCompletedThisSession = false
                    val gate = openingTillGate()
                    val counted = gate?.let { sumTillCounts(it.denominations, it.counts) }
                    _state.update {
                        it.copy(
                            isAuthenticated = false,
                            authGate = CashierAuthGate.WaitingApproval(
                                email = null,
                                secondsRemaining = null,
                                cashMode = response.cashMode ?: cashMode,
                                expectedOpeningFloat = gate?.expectedOpeningFloat,
                                openingCountedFloat = counted,
                                openingVariance = response.openingVariance
                                    ?: gate?.expectedOpeningFloat?.let { expected ->
                                        counted?.let { value -> value - expected }
                                    },
                            ),
                            status = "Waiting for supervisor approval",
                        )
                    }
                    startApprovalPoll()
                    return@onSuccess
                }
                if (response.ok) {
                    runCatching { repository.cashierSession() }
                        .onSuccess { session ->
                            repository.applySessionAuth(session)
                            applySessionProbe(session)
                        }
                        .onFailure { err ->
                            _state.update { state ->
                                val gate = state.authGate as? CashierAuthGate.OpeningTill ?: return@onFailure
                                state.copy(
                                    authGate = gate.copy(submitting = false),
                                    status = connectivityMessage(err),
                                )
                            }
                        }
                } else {
                    _state.update { state ->
                        val gate = state.authGate as? CashierAuthGate.OpeningTill ?: return@onSuccess
                        state.copy(
                            authGate = gate.copy(submitting = false),
                            status = response.error ?: "Till submit failed",
                        )
                    }
                }
            }.onFailure { err ->
                if (err is HttpException && err.code() == 401) {
                    showSignInGateFromCachedAuth("Sign-in expired — sign in with Oracle again")
                    return@onFailure
                }
                if (err is HttpException && err.code() == 409) {
                    repository.clearCashierCookies()
                    showSignInGateFromCachedAuth(registerInUseMessage(err))
                    return@onFailure
                }
                _state.update { state ->
                    val gate = state.authGate as? CashierAuthGate.OpeningTill ?: return@onFailure
                    state.copy(
                        authGate = gate.copy(submitting = false),
                        status = connectivityMessage(err),
                    )
                }
            }
        }
    }

    private suspend fun postOpeningTillWithRetry(
        cashMode: String,
        denominations: Map<String, Int>?,
        countedTotal: Double?,
    ): com.cloudstore.pos.data.SubmitOpeningTillResponse {
        repository.prepareForTillSubmit()
        val body = com.cloudstore.pos.data.SubmitOpeningTillRequest(
            cashMode = cashMode,
            denominations = denominations,
            countedTotal = countedTotal,
            awaitingTillToken = repository.awaitingTillTokenForSubmit(),
        )
        return try {
            repository.submitOpeningTill(body)
        } catch (err: HttpException) {
            if (err.code() != 401) throw err
            repository.prepareForTillSubmit()
            repository.submitOpeningTill(
                body.copy(awaitingTillToken = repository.awaitingTillTokenForSubmit()),
            )
        }
    }

    private fun applySessionProbe(session: CashierSessionResponse) {
        val idpUrl = if (session.idpEnabled) resolveIdpLoginUrl(session.idpLoginUrl) else null
        when {
            session.awaitingTill -> {
                if (oidcAuthStepCompletedThisSession) {
                    oidcAuthStepCompletedThisSession = false
                    repository.applySessionAuth(session)
                    loadOpeningTillGate()
                } else {
                    viewModelScope.launch {
                        clearStaleSignInState("Sign in with Oracle to open your till")
                    }
                }
            }
            session.ok -> {
                oidcAuthStepCompletedThisSession = false
                requireFreshIdpLogin = false
                stopApprovalPoll()
                val resolvedUser = rememberCashierUserFromSession(session, _state.value)
                    ?: _state.value.loggedInUser
                    ?: userStore.get()
                PosIdentityLog.resolved(
                    "applySessionProbe",
                    resolvedUser,
                    userStore.get(),
                    _state.value.loggedInUser,
                )
                _state.update {
                    it.copy(
                        isAuthenticated = true,
                        loggedInUser = resolvedUser,
                        authGate = CashierAuthGate.SignedIn,
                        idpLoginUrl = idpUrl,
                        pinAllowed = effectivePinAllowed(session),
                        supervisorApprovalRequired = session.supervisorApprovalRequired,
                        idpEnabled = session.idpEnabled,
                        pinInput = "",
                        cashEnabled = resolveCashEnabled(session),
                        cashMode = session.cashMode,
                        tillId = session.tillId,
                        posSessionId = session.posSessionId,
                        status = "Signed in",
                    )
                }
                refresh()
                syncCashierIdentity()
                flushOfflineQueue()
            }
            session.pending -> {
                if (oidcAuthStepCompletedThisSession) {
                    oidcAuthStepCompletedThisSession = false
                    rememberCashierUserFromApproval(
                        session.approval?.cashierEmail,
                        session.approval?.cashierName,
                    )
                    _state.update {
                        it.copy(
                            isAuthenticated = false,
                            authGate = waitingApprovalFromSession(session),
                            idpLoginUrl = idpUrl,
                            pinAllowed = effectivePinAllowed(session),
                            supervisorApprovalRequired = session.supervisorApprovalRequired,
                            idpEnabled = session.idpEnabled,
                            status = "Waiting for supervisor approval",
                        )
                    }
                    startApprovalPoll()
                } else {
                    viewModelScope.launch {
                        clearStaleSignInState("Sign in with Oracle to continue")
                    }
                }
            }
            else -> {
                oidcAuthStepCompletedThisSession = false
                val baseStatus = when {
                    _state.value.status.startsWith("Signed off") -> _state.value.status
                    _state.value.status == "Signed out" ->
                        if (session.supervisorApprovalRequired) {
                            "Signed off — sign in with your credentials"
                        } else {
                            "Signed off"
                        }
                    else -> "Ready"
                }
                configureSignInGateFromSession(session, baseStatus)
            }
        }
    }

    private fun effectivePinAllowed(session: CashierSessionResponse): Boolean =
        session.pinAllowed && !session.supervisorApprovalRequired

    /** Cached/error paths — hide PIN when Model B / IdP sign-in is required. */
    private fun effectivePinAllowedCached(
        pinAllowed: Boolean,
        supervisorApprovalRequired: Boolean,
        idpEnabled: Boolean,
        idpLoginUrl: String?,
    ): Boolean {
        if (supervisorApprovalRequired || idpEnabled || !idpLoginUrl.isNullOrBlank()) return false
        return pinAllowed
    }

    private fun configureSignInGateFromSession(session: CashierSessionResponse, status: String) {
        val idpUrl = if (session.idpEnabled) resolveIdpLoginUrl(session.idpLoginUrl) else null
        showSignInGate(
            pinAllowed = effectivePinAllowed(session),
            idpLoginUrl = idpUrl,
            status = status,
            supervisorApprovalRequired = session.supervisorApprovalRequired,
            idpEnabled = session.idpEnabled,
        )
    }

    private fun showSignInGateFromCachedAuth(status: String) {
        val current = _state.value
        val idpUrl = when {
            current.idpLoginUrl != null -> current.idpLoginUrl
            current.idpEnabled || current.supervisorApprovalRequired ->
                resolveIdpLoginUrl("/oauth/login")
            else -> null
        }
        val idpEnabled = current.idpEnabled || idpUrl != null
        val pinOk = effectivePinAllowedCached(
            pinAllowed = current.pinAllowed,
            supervisorApprovalRequired = current.supervisorApprovalRequired,
            idpEnabled = idpEnabled,
            idpLoginUrl = idpUrl,
        )
        showSignInGate(
            pinAllowed = pinOk,
            idpLoginUrl = idpUrl,
            status = status,
            supervisorApprovalRequired = current.supervisorApprovalRequired,
            idpEnabled = idpEnabled,
        )
    }

    private fun showSignInGate(
        pinAllowed: Boolean,
        idpLoginUrl: String?,
        status: String,
        supervisorApprovalRequired: Boolean = _state.value.supervisorApprovalRequired,
        idpEnabled: Boolean = _state.value.idpEnabled,
        clearStoredUser: Boolean = true,
    ) {
        stopApprovalPoll()
        if (clearStoredUser) {
            userStore.clear()
        }
        _state.update {
            it.copy(
                isAuthenticated = false,
                loggedInUser = if (clearStoredUser) null else it.loggedInUser,
                authGate = CashierAuthGate.PinSignIn(pinAllowed = pinAllowed),
                idpLoginUrl = idpLoginUrl,
                pinAllowed = pinAllowed,
                supervisorApprovalRequired = supervisorApprovalRequired,
                idpEnabled = idpEnabled,
                pinInput = "",
                status = status,
            )
        }
    }

    private fun resolveIdpLoginUrl(relative: String?): String? {
        if (relative.isNullOrBlank()) return null
        val base = BuildConfig.API_BASE_URL.trimEnd('/')
        val url = if (relative.startsWith("http://") || relative.startsWith("https://")) {
            relative
        } else {
            val path = if (relative.startsWith("/")) relative else "/$relative"
            "$base$path"
        }
        val params = mutableListOf<String>()
        if (!url.contains("client_kind=")) {
            params.add("client_kind=tablet")
        }
        if (!url.contains("register_id=") && registerId.isNotBlank()) {
            params.add("register_id=${Uri.encode(registerId)}")
        }
        if (requireFreshIdpLogin && !url.contains("prompt=")) {
            params.add("prompt=login")
        }
        if (params.isEmpty()) return url
        val sep = if (url.contains('?')) '&' else '?'
        return url + sep + params.joinToString("&")
    }

    private fun startApprovalPoll() {
        approvalPollJob?.cancel()
        approvalPollJob = viewModelScope.launch {
            pollApprovalOnce()
            while (true) {
                delay(APPROVAL_POLL_MS)
                pollApprovalOnce()
            }
        }
    }

    private fun stopApprovalPoll() {
        approvalPollJob?.cancel()
        approvalPollJob = null
    }

    private suspend fun syncWebViewCookiesWithRetry() {
        repository.syncWebViewCookies()
        delay(150)
        repository.syncWebViewCookies()
    }

    private suspend fun pollApprovalOnce() {
        if (_state.value.authGate !is CashierAuthGate.WaitingApproval) return

        val statusResult = runCatching { repository.pollApprovalStatus() }
        if (statusResult.isFailure) {
            handleApprovalPollFailure(statusResult.exceptionOrNull() ?: return)
            return
        }
        val status = statusResult.getOrThrow()

        when (status.status.lowercase()) {
            "approved" -> {
                if (status.ok) {
                    rememberCashierUserFromApproval(
                        status.email ?: status.cashierEmail,
                        status.name ?: status.cashierName,
                    )
                    completeApprovedLogin()
                }
            }
            "pending" -> {
                val approvalEmail = status.email ?: status.cashierEmail
                val approvalName = status.name ?: status.cashierName
                rememberCashierUserFromApproval(approvalEmail, approvalName)
                _state.update {
                    val gate = it.authGate
                    it.copy(
                        authGate = if (gate is CashierAuthGate.WaitingApproval) {
                            waitingApprovalFromPoll(
                                gate.copy(
                                    email = approvalEmail ?: gate.email,
                                    secondsRemaining = status.secondsRemaining,
                                ),
                                status,
                            )
                        } else {
                            gate
                        },
                        status = "Waiting for supervisor approval",
                    )
                }
            }
            "denied", "expired", "cancelled" -> {
                stopApprovalPoll()
                repository.clearCashierCookies()
                val msg = when (status.status.lowercase()) {
                    "denied" -> status.reason ?: "Supervisor denied login"
                    "expired" -> "Login request expired — sign in again"
                    else -> "Login request cancelled"
                }
                showSignInGateFromCachedAuth(msg)
            }
            else -> {
                if (status.error != null) {
                    _state.update { it.copy(status = status.error) }
                }
            }
        }
    }

    private fun handleApprovalPollFailure(err: Throwable) {
        if (err is CancellationException) return
        when {
            err is HttpException && err.code() == 401 -> {
                stopApprovalPoll()
                showSignInGateFromCachedAuth("No pending login request — sign in again")
            }
            else -> {
                _state.update {
                    it.copy(status = "Waiting for supervisor approval — ${connectivityMessage(err)}")
                }
            }
        }
    }

    /** Finish login on a fresh coroutine — do not cancel the poll job before this runs. */
    private fun completeApprovedLogin() {
        viewModelScope.launch {
            applyApprovedSession()
        }
        stopApprovalPoll()
    }

    /** Poll response should have set cashier_session; confirm before loading POS. */
    private suspend fun applyApprovedSession() {
        runCatching { repository.cashierSession() }
            .onSuccess { session ->
                if (session.ok) {
                    applySessionProbe(session)
                } else {
                    showSignInGateFromCachedAuth("Approved but session did not persist — sign in again")
                }
            }
            .onFailure { err ->
                if (err is CancellationException) return@onFailure
                showSignInGateFromCachedAuth(connectivityMessage(err))
            }
    }

    private fun connectivityMessage(err: Throwable): String =
        when (err) {
            is CancellationException -> "Connection failed"
            is HttpException -> when (err.code()) {
                409 -> registerInUseMessage(err)
                else -> "Server error (${err.code()})"
            }
            is IOException -> "Cannot reach server — check Wi‑Fi and API URL (${BuildConfig.API_BASE_URL})"
            else -> err.message ?: "Connection failed"
        }

    private fun registerInUseMessage(err: HttpException): String {
        val body = err.response()?.errorBody()?.string().orEmpty()
        val match = Regex(""""error"\s*:\s*"([^"]+)"""").find(body)
        return match?.groupValues?.getOrNull(1)
            ?: "This tablet is in use — the current cashier must sign off first"
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
                .onSuccess { session ->
                    if (session.awaitingTill) {
                        loadOpeningTillGate()
                    } else {
                        applySessionProbe(session)
                    }
                }
                .onFailure { err ->
                    val msg = when (err) {
                        is HttpException -> when (err.code()) {
                            401 -> "Invalid PIN"
                            403 -> "Supervisor approval required — use Oracle sign-in"
                            404 -> "Server needs update (missing login API)"
                            else -> "Server error (${err.code()})"
                        }
                        else -> when {
                            err.message?.contains("did not persist", ignoreCase = true) == true ->
                                err.message!!
                            else -> connectivityMessage(err)
                        }
                    }
                    _state.value = _state.value.copy(
                        isAuthenticated = false,
                        status = msg,
                    )
                }
        }
    }

    fun signOutForBreak() {
        viewModelScope.launch {
            stopApprovalPoll()
            stopClosePoll()
            runCatching { repository.logoutCashier() }
            repository.clearWebViewIdpSession()
            requireFreshIdpLogin = true
            userStore.clear()
            val authHints = _state.value
            _state.value = PosUiState(
                isAuthenticated = false,
                authGate = CashierAuthGate.Checking,
                supervisorApprovalRequired = authHints.supervisorApprovalRequired,
                idpEnabled = authHints.idpEnabled,
                idpLoginUrl = resolveIdpLoginUrl("/oauth/login"),
                pinAllowed = authHints.pinAllowed && !authHints.supervisorApprovalRequired,
                pinInput = "",
                barcodeInput = "",
                queuedCheckoutCount = queueStore.all().size,
                status = "Signed out — sign in with your credentials",
            )
            probeCashierSession()
        }
    }

    fun beginCloseTill() {
        viewModelScope.launch {
            _state.update { it.copy(status = "Loading close till…") }
            runCatching { repository.closeTillPreview() }
                .onSuccess { preview ->
                    if (!preview.ok) {
                        _state.update { it.copy(status = preview.error ?: "Cannot close till") }
                        return@onSuccess
                    }
                    if (preview.cartBlocked) {
                        _state.update { it.copy(status = "Clear the cart before closing the till") }
                        return@onSuccess
                    }
                    if (preview.creditOnly) {
                        enterClosingCreditOnly()
                    } else {
                        enterClosingTill(preview)
                    }
                }
                .onFailure { err ->
                    _state.update { it.copy(status = connectivityMessage(err)) }
                }
        }
    }

    private fun enterClosingCreditOnly() {
        stopClosePoll()
        _state.update {
            it.copy(
                authGate = CashierAuthGate.ClosingCreditOnly(),
                status = "Close credit-only shift",
            )
        }
    }

    private fun enterClosingTill(preview: CloseTillPreviewResponse) {
        stopClosePoll()
        _state.update {
            it.copy(
                authGate = CashierAuthGate.ClosingTill(
                    expectedCloseFloat = preview.expectedCloseFloat,
                    openingCountedFloat = preview.openingCountedFloat,
                    cashSalesTotal = preview.cashSalesTotal,
                    changeGivenTotal = preview.changeGivenTotal,
                    denominations = preview.denominations,
                    selectedDenominationId = preview.denominations.firstOrNull()?.id,
                ),
                status = "Count closing till",
            )
        }
    }

    fun submitClosingCreditOnly() {
        submitCloseTillRequest(cashMode = "credit_only")
    }

    fun submitClosingTill() {
        val gate = _state.value.authGate as? CashierAuthGate.ClosingTill ?: return
        val nonEmptyCounts = gate.counts
            .mapNotNull { (id, raw) ->
                val count = raw.toIntOrNull() ?: 0
                if (count > 0) id to count else null
            }
            .toMap()
        val countedTotal = sumTillCounts(gate.denominations, gate.counts)
        submitCloseTillRequest(
            cashMode = "cash_and_credit",
            denominations = nonEmptyCounts,
            countedTotal = countedTotal,
        )
    }

    fun cancelCloseTill() {
        viewModelScope.launch {
            stopClosePoll()
            runCatching { repository.cancelCloseTill() }
            _state.update {
                it.copy(
                    isAuthenticated = true,
                    authGate = CashierAuthGate.SignedIn,
                    status = "Close till cancelled",
                )
            }
        }
    }

    private fun submitCloseTillRequest(
        cashMode: String,
        denominations: Map<String, Int>? = null,
        countedTotal: Double? = null,
    ) {
        viewModelScope.launch {
            _state.update { state ->
                when (val gate = state.authGate) {
                    is CashierAuthGate.ClosingTill ->
                        state.copy(authGate = gate.copy(submitting = true), status = "Submitting close…")
                    is CashierAuthGate.ClosingCreditOnly ->
                        state.copy(authGate = gate.copy(submitting = true), status = "Submitting close…")
                    else -> return@launch
                }
            }
            runCatching {
                repository.submitCloseTill(
                    SubmitCloseTillRequest(
                        cashMode = cashMode,
                        denominations = denominations,
                        countedTotal = countedTotal,
                    ),
                )
            }.onSuccess { response ->
                if (response.approved) {
                    finishCloseTillSignedOff()
                    return@onSuccess
                }
                if (response.pending) {
                    _state.update {
                        it.copy(
                            isAuthenticated = false,
                            authGate = CashierAuthGate.WaitingCloseApproval(
                                closeToken = response.closeToken,
                                cashMode = response.cashMode,
                                expectedCloseFloat = response.expectedCloseFloat,
                                countedCloseFloat = response.countedCloseFloat,
                                closeVariance = response.closeVariance,
                            ),
                            status = "Waiting for supervisor to approve close",
                        )
                    }
                    startClosePoll()
                    return@onSuccess
                }
                resetCloseSubmitting(response.error ?: "Close till failed")
            }.onFailure { err ->
                resetCloseSubmitting(connectivityMessage(err))
            }
        }
    }

    private fun resetCloseSubmitting(message: String) {
        _state.update { state ->
            when (val gate = state.authGate) {
                is CashierAuthGate.ClosingTill ->
                    state.copy(authGate = gate.copy(submitting = false), status = message)
                is CashierAuthGate.ClosingCreditOnly ->
                    state.copy(authGate = gate.copy(submitting = false), status = message)
                else -> state.copy(status = message)
            }
        }
    }

    private fun finishCloseTillSignedOff() {
        stopClosePoll()
        requireFreshIdpLogin = true
        userStore.clear()
        repository.clearWebViewIdpSession()
        val authHints = _state.value
        _state.value = PosUiState(
            isAuthenticated = false,
            authGate = CashierAuthGate.Checking,
            supervisorApprovalRequired = authHints.supervisorApprovalRequired,
            idpEnabled = authHints.idpEnabled,
            idpLoginUrl = resolveIdpLoginUrl("/oauth/login"),
            pinAllowed = authHints.pinAllowed && !authHints.supervisorApprovalRequired,
            queuedCheckoutCount = queueStore.all().size,
            status = "Till closed — sign in with your credentials",
        )
        viewModelScope.launch {
            repository.clearCashierCookies()
            probeCashierSession()
        }
    }

    private fun startClosePoll() {
        closePollJob?.cancel()
        closePollJob = viewModelScope.launch {
            pollCloseOnce()
            while (true) {
                delay(APPROVAL_POLL_MS)
                pollCloseOnce()
            }
        }
    }

    private fun stopClosePoll() {
        closePollJob?.cancel()
        closePollJob = null
    }

    private suspend fun pollCloseOnce() {
        val gate = _state.value.authGate as? CashierAuthGate.WaitingCloseApproval ?: return
        val statusResult = runCatching { repository.closeTillStatus(gate.closeToken) }
        if (statusResult.isFailure) return
        val status = statusResult.getOrThrow()
        when (status.status) {
            "approved" -> finishCloseTillSignedOff()
            "denied" -> {
                stopClosePoll()
                _state.update {
                    it.copy(
                        isAuthenticated = true,
                        authGate = CashierAuthGate.SignedIn,
                        status = status.reason?.let { r -> "Close denied: $r" } ?: "Supervisor denied close",
                    )
                }
            }
            "pending" -> {
                _state.update { state ->
                    val gate = state.authGate as? CashierAuthGate.WaitingCloseApproval ?: return@update state
                    state.copy(
                        authGate = gate.copy(
                            secondsRemaining = status.secondsRemaining,
                            expectedCloseFloat = status.expectedCloseFloat ?: gate.expectedCloseFloat,
                            countedCloseFloat = status.countedCloseFloat ?: gate.countedCloseFloat,
                            closeVariance = status.closeVariance ?: gate.closeVariance,
                        ),
                    )
                }
            }
        }
    }

    private fun closingTillGate(): CashierAuthGate.ClosingTill? =
        _state.value.authGate as? CashierAuthGate.ClosingTill

    fun selectClosingDenomination(denominationId: String) {
        _state.update { state ->
            val gate = state.authGate as? CashierAuthGate.ClosingTill ?: return@update state
            state.copy(authGate = gate.copy(selectedDenominationId = denominationId))
        }
    }

    fun appendClosingTillDigit(digit: Char) {
        val gate = closingTillGate() ?: return
        val id = gate.selectedDenominationId ?: return
        val current = gate.counts[id].orEmpty()
        if (current.length >= 4) return
        val next = if (current == "0") digit.toString() else current + digit
        updateClosingTillCount(id, next)
    }

    fun clearClosingTillCount() {
        val id = closingTillGate()?.selectedDenominationId ?: return
        updateClosingTillCount(id, "")
    }

    fun backspaceClosingTillCount() {
        val gate = closingTillGate() ?: return
        val id = gate.selectedDenominationId ?: return
        val current = gate.counts[id].orEmpty()
        updateClosingTillCount(id, current.dropLast(1))
    }

    fun selectPreviousClosingDenomination() {
        _state.update { state ->
            val gate = state.authGate as? CashierAuthGate.ClosingTill ?: return@update state
            val denoms = gate.denominations
            if (denoms.isEmpty()) return@update state
            val currentIdx = denoms.indexOfFirst { it.id == gate.selectedDenominationId }
            val prevIdx = if (currentIdx <= 0) denoms.lastIndex else currentIdx - 1
            state.copy(authGate = gate.copy(selectedDenominationId = denoms[prevIdx].id))
        }
    }

    fun selectNextClosingDenomination() {
        _state.update { state ->
            val gate = state.authGate as? CashierAuthGate.ClosingTill ?: return@update state
            val denoms = gate.denominations
            if (denoms.isEmpty()) return@update state
            val currentIdx = denoms.indexOfFirst { it.id == gate.selectedDenominationId }
            val nextIdx = if (currentIdx < 0 || currentIdx >= denoms.lastIndex) 0 else currentIdx + 1
            state.copy(authGate = gate.copy(selectedDenominationId = denoms[nextIdx].id))
        }
    }

    private fun updateClosingTillCount(id: String, value: String) {
        _state.update { state ->
            val gate = state.authGate as? CashierAuthGate.ClosingTill ?: return@update state
            state.copy(authGate = gate.copy(counts = gate.counts + (id to value)))
        }
    }

    private fun addItemErrorMessage(err: Throwable, label: String): String = when {
        err is HttpException && err.code() == 401 -> "Session expired — sign in again"
        err is HttpException && err.code() == 404 -> "Product not found: $label"
        err is HttpException && err.code() == 409 -> err.message?.takeIf { it.isNotBlank() }
            ?: "Insufficient stock"
        else -> "Add failed: ${err.message ?: "Unable to add item"}"
    }

    fun addProduct(productId: Int) {
        viewModelScope.launch {
            val cid = _state.value.selectedCustomerId
            val product = _state.value.products.find { it.id == productId }
            if (product == null) {
                _state.value = _state.value.copy(addItemError = "Product not found: ID $productId")
                return@launch
            }
            if (!product.inStock) {
                val stockMsg = product.quantityOnHand?.let { qty -> " (qty $qty)" }.orEmpty()
                _state.value = _state.value.copy(addItemError = "${product.name} is out of stock$stockMsg")
                return@launch
            }
            runCatching { repository.addProduct(productId, cid) }
                .onSuccess {
                    applyCartResponse(it, _state.value.customerDiscountActive())
                    _state.value = _state.value.copy(addItemError = null)
                }
                .onFailure { err ->
                    val authLost = err is HttpException && err.code() == 401
                    _state.value = _state.value.copy(
                        isAuthenticated = !authLost,
                        addItemError = addItemErrorMessage(err, "ID $productId"),
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
            _state.value = _state.value.copy(addItemError = "Enter barcode or product ID")
            return
        }

        val asId = cleaned.toIntOrNull()
        val treatAsId = asId != null && cleaned.length <= 6

        // Scan field adds products when the ID matches a product (even if the same number is a customer ID).
        // Link customers via Find customer when IDs overlap (e.g. product 2 and customer 2).
        if (treatAsId) {
            val product = _state.value.products.find { it.id == asId }
            val hasCustomer = _state.value.customers.any { it.id == asId }
            if (product == null && hasCustomer) {
                linkCustomerById(asId)
                _state.value = _state.value.copy(barcodeInput = "")
                return
            }
            if (product == null) {
                _state.value = _state.value.copy(addItemError = "Product not found: ID $cleaned")
                return
            }
            if (!product.inStock) {
                val stockMsg = product.quantityOnHand?.let { qty -> " (qty $qty)" }.orEmpty()
                _state.value = _state.value.copy(addItemError = "${product.name} is out of stock$stockMsg")
                return
            }
        }

        if (!treatAsId) {
            val product = _state.value.products.find { it.barcode == cleaned }
            if (product != null && !product.inStock) {
                val stockMsg = product.quantityOnHand?.let { qty -> " (qty $qty)" }.orEmpty()
                _state.value = _state.value.copy(addItemError = "${product.name} is out of stock$stockMsg")
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
                        addItemError = null,
                    )
                }
                .onFailure { err ->
                    val authLost = err is HttpException && err.code() == 401
                    val label = if (treatAsId) "ID $cleaned" else cleaned
                    _state.value = _state.value.copy(
                        isAuthenticated = !authLost,
                        addItemError = addItemErrorMessage(err, label),
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

    fun checkout(
        payments: List<CheckoutPayment>? = null,
        checkoutTotal: Double? = null,
    ) {
        viewModelScope.launch {
            performCheckout(payments = payments, checkoutTotal = checkoutTotal)
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
                    val err = result.exceptionOrNull() ?: continue
                    val retryable = NetworkErrorLogic.isRetryableSyncError(err)
                    if (retryable) {
                        remaining.add(pending)
                    } else {
                        droppedPermanent++
                    }
                    lastError = when (err) {
                        is HttpException -> NetworkErrorLogic.httpErrorMessage(err, "Server error")
                        else -> err.message
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

    override fun onCleared() {
        stopApprovalPoll()
        stopClosePoll()
        super.onCleared()
    }

}

class PosViewModelFactory(
    private val repository: PosRepository,
    private val queueStore: OfflineQueueStore,
    private val userStore: CashierUserStore,
    private val registerId: String,
) : ViewModelProvider.Factory {
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(PosViewModel::class.java)) {
            @Suppress("UNCHECKED_CAST")
            return PosViewModel(repository, queueStore, userStore, registerId) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class")
    }
}
