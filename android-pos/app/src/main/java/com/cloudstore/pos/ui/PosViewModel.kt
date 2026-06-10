package com.cloudstore.pos.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.cloudstore.pos.data.CartItem
import com.cloudstore.pos.data.CartResponse
import com.cloudstore.pos.data.CashierSessionResponse
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
        val pinAllowed: Boolean = true,
    ) : CashierAuthGate()
    data class WaitingApproval(
        val email: String? = null,
        val secondsRemaining: Int? = null,
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
    val pinAllowed: Boolean = true,
    val pinInput: String = "",
    val queuedCheckoutCount: Int = 0,
    val queueSyncing: Boolean = false,
    val receipt: SaleReceipt? = null,
    val receiptPrintMessage: String? = null,
    val receiptPrintProgress: Float = 0f,
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
    private val userStore: CashierUserStore,
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
    private var printReceiptJob: Job? = null
    private var approvalPollJob: Job? = null
    private var oidcCompleting = false

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
            repeat(25) { index ->
                delay(100)
                _state.update { it.copy(receiptPrintProgress = (index + 1) / 25f) }
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
                it.copy(processingDialogMessage = null, paymentProcessingProgress = 0f)
            }
            setPaymentMethod(method)
            checkout(payments = payments, checkoutTotal = registerTotal)
            resetCheckout()
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
                        _state.update { it.copy(loggedInUser = user) }
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
                    showSignInGate(
                        pinAllowed = _state.value.pinAllowed,
                        idpLoginUrl = _state.value.idpLoginUrl,
                        status = "Session expired — sign in again",
                    )
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
        _state.update { it.copy(authGate = CashierAuthGate.OidcSignIn) }
    }

    fun cancelOidcSignIn() {
        _state.update {
            it.copy(
                authGate = CashierAuthGate.PinSignIn(pinAllowed = it.pinAllowed),
                status = "Ready",
            )
        }
    }

    fun onOidcWebViewComplete(completionUrl: String) {
        if (oidcCompleting) return
        oidcCompleting = true
        val pendingToken = parsePendingRequestToken(completionUrl)
        if (!pendingToken.isNullOrBlank()) {
            repository.rememberPendingRequestToken(pendingToken)
        }
        // Dismiss WebView immediately — show native waiting screen, not server web POS.
        _state.update {
            it.copy(
                isAuthenticated = false,
                authGate = CashierAuthGate.WaitingApproval(
                    email = null,
                    secondsRemaining = null,
                ),
                idpLoginUrl = resolveIdpLoginUrl("/oauth/login"),
                status = "Completing sign-in…",
            )
        }
        startApprovalPoll()
        viewModelScope.launch {
            try {
                syncWebViewCookiesWithRetry()
                if (!pendingToken.isNullOrBlank()) {
                    repository.rememberPendingRequestToken(pendingToken)
                }
                runCatching { repository.cashierSession() }
                    .onSuccess { session ->
                        when {
                            session.ok -> applySessionProbe(session)
                            session.pending -> applySessionProbe(session)
                            pendingToken.isNullOrBlank() && !repository.hasPendingRequestCookie() ->
                                showSignInGate(
                                    pinAllowed = session.pinAllowed,
                                    idpLoginUrl = if (session.idpEnabled) {
                                        resolveIdpLoginUrl(session.idpLoginUrl)
                                    } else {
                                        null
                                    },
                                    status = "Sign-in incomplete — tap Oracle sign-in again",
                                )
                        }
                    }
                    .onFailure { err ->
                        if (pendingToken.isNullOrBlank() && !repository.hasPendingRequestCookie()) {
                            stopApprovalPoll()
                            showSignInGate(
                                pinAllowed = _state.value.pinAllowed,
                                idpLoginUrl = _state.value.idpLoginUrl,
                                status = connectivityMessage(err),
                            )
                        }
                    }
            } finally {
                oidcCompleting = false
            }
        }
    }

    private fun enterWaitingApprovalFromToken(pendingToken: String?) {
        if (pendingToken.isNullOrBlank() && !repository.hasPendingRequestCookie()) {
            showSignInGate(
                pinAllowed = _state.value.pinAllowed,
                idpLoginUrl = resolveIdpLoginUrl("/oauth/login"),
                status = "Sign-in incomplete — tap Oracle sign-in again",
            )
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
            showSignInGate(
                pinAllowed = _state.value.pinAllowed,
                idpLoginUrl = _state.value.idpLoginUrl,
                status = "Login request cancelled",
            )
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
            runCatching { repository.cashierSession() }
                .onSuccess { session ->
                    PosIdentityLog.session("probeCashierSession", session)
                    applySessionProbe(session)
                }
                .onFailure { err ->
                    PosIdentityLog.d("probeCashierSession failed: ${err.message}")
                    showSignInGate(
                        pinAllowed = true,
                        idpLoginUrl = null,
                        status = connectivityMessage(err),
                    )
                }
        }
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

    private fun applySessionProbe(session: CashierSessionResponse) {
        val idpUrl = if (session.idpEnabled) resolveIdpLoginUrl(session.idpLoginUrl) else null
        when {
            session.ok -> {
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
                        pinAllowed = session.pinAllowed,
                        pinInput = "",
                        status = "Signed in",
                    )
                }
                refresh()
                syncCashierIdentity()
                flushOfflineQueue()
            }
            session.pending -> {
                rememberCashierUserFromApproval(
                    session.approval?.cashierEmail,
                    session.approval?.cashierName,
                )
                _state.update {
                    it.copy(
                        isAuthenticated = false,
                        authGate = CashierAuthGate.WaitingApproval(
                            email = session.approval?.cashierEmail,
                            secondsRemaining = session.approval?.secondsRemaining,
                        ),
                        idpLoginUrl = idpUrl,
                        pinAllowed = session.pinAllowed,
                        status = "Waiting for supervisor approval",
                    )
                }
                startApprovalPoll()
            }
            else -> {
                showSignInGate(
                    pinAllowed = session.pinAllowed,
                    idpLoginUrl = idpUrl,
                    status = "Ready",
                )
            }
        }
    }

    private fun showSignInGate(
        pinAllowed: Boolean,
        idpLoginUrl: String?,
        status: String,
    ) {
        stopApprovalPoll()
        userStore.clear()
        _state.update {
            it.copy(
                isAuthenticated = false,
                loggedInUser = null,
                authGate = CashierAuthGate.PinSignIn(pinAllowed = pinAllowed),
                idpLoginUrl = idpLoginUrl,
                pinAllowed = pinAllowed,
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
        if (url.contains("client_kind=")) return url
        val sep = if (url.contains('?')) '&' else '?'
        return "$url${sep}client_kind=tablet"
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
                            gate.copy(
                                email = approvalEmail ?: gate.email,
                                secondsRemaining = status.secondsRemaining,
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
                showSignInGate(
                    pinAllowed = _state.value.pinAllowed,
                    idpLoginUrl = _state.value.idpLoginUrl,
                    status = msg,
                )
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
                showSignInGate(
                    pinAllowed = _state.value.pinAllowed,
                    idpLoginUrl = _state.value.idpLoginUrl,
                    status = "No pending login request — sign in again",
                )
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
                    showSignInGate(
                        pinAllowed = _state.value.pinAllowed,
                        idpLoginUrl = _state.value.idpLoginUrl,
                        status = "Approved but session did not persist — sign in again",
                    )
                }
            }
            .onFailure { err ->
                if (err is CancellationException) return@onFailure
                showSignInGate(
                    pinAllowed = _state.value.pinAllowed,
                    idpLoginUrl = _state.value.idpLoginUrl,
                    status = connectivityMessage(err),
                )
            }
    }

    private fun connectivityMessage(err: Throwable): String =
        when (err) {
            is CancellationException -> "Connection failed"
            is HttpException -> "Server error (${err.code()})"
            is IOException -> "Cannot reach server — check Wi‑Fi and API URL (${BuildConfig.API_BASE_URL})"
            else -> err.message ?: "Connection failed"
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
                    val session = runCatching { repository.cashierSession() }.getOrNull()
                    val loggedInUser = session?.let { rememberCashierUserFromSession(it, _state.value) }
                        ?: "Cashier".also { userStore.save(it) }
                    _state.value = _state.value.copy(
                        isAuthenticated = true,
                        loggedInUser = loggedInUser,
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

    fun lock() {
        viewModelScope.launch {
            stopApprovalPoll()
            runCatching { repository.logoutCashier() }
            userStore.clear()
            _state.value = PosUiState(
                isAuthenticated = false,
                authGate = CashierAuthGate.PinSignIn(pinAllowed = _state.value.pinAllowed),
                idpLoginUrl = _state.value.idpLoginUrl,
                pinAllowed = _state.value.pinAllowed,
                pinInput = "",
                barcodeInput = "",
                queuedCheckoutCount = queueStore.all().size,
                status = "Signed out",
            )
            probeCashierSession()
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
            if (_state.value.cart.isEmpty()) {
                _state.value = _state.value.copy(status = "Cart is empty")
                return@launch
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
                    val snapshotState = _state.value
                    val customerName = snapshotState.selectedCustomer()?.let { customer ->
                        customerDisplayName(customer, customer.id)
                    }
                    queueStore.enqueue(paymentMethod, customerId, lines, payments, checkoutTotal)
                    val receipt = buildSaleReceipt(
                        cart = snapshotState.cart,
                        customerName = customerName,
                        customerLinked = snapshotState.customerLinked(),
                        customerDiscount = snapshotState.customerDiscountActive(),
                        salesFeeRate = salesFeeRate,
                        taxRate = taxRate,
                        payments = paymentsUsed,
                        queuedOffline = true,
                    )
                    _state.value = snapshotState.copy(
                        receipt = receipt,
                        status = "Ready",
                        queuedCheckoutCount = queueStore.all().size,
                        selectedCustomerId = null,
                        selectedCustomerDiscount = false,
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

    override fun onCleared() {
        stopApprovalPoll()
        super.onCleared()
    }

}

class PosViewModelFactory(
    private val repository: PosRepository,
    private val queueStore: OfflineQueueStore,
    private val userStore: CashierUserStore,
) : ViewModelProvider.Factory {
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(PosViewModel::class.java)) {
            @Suppress("UNCHECKED_CAST")
            return PosViewModel(repository, queueStore, userStore) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class")
    }
}
