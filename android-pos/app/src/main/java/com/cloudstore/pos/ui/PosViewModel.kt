package com.cloudstore.pos.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.cloudstore.pos.data.CartItem
import com.cloudstore.pos.data.CartResponse
import com.cloudstore.pos.data.OfflineQueueStore
import com.cloudstore.pos.data.PendingCheckout
import com.cloudstore.pos.data.QueuedCartLine
import com.cloudstore.pos.data.PosRepository
import com.cloudstore.pos.data.Product
import com.cloudstore.pos.data.Sale
import com.cloudstore.pos.data.StoreCustomer
import com.cloudstore.pos.BuildConfig
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

    var state = androidx.compose.runtime.mutableStateOf(PosUiState())
        private set

    private var cartRefreshGeneration = 0

    init {
        state.value = state.value.copy(queuedCheckoutCount = queueStore.all().size)
    }

    fun refresh() {
        if (!state.value.isAuthenticated) return
        viewModelScope.launch {
            state.value = state.value.copy(loading = true, status = "Loading...")
            runCatching {
                val products = repository.products()
                val customers = repository.customers()
                val cartResp = repository.cart(state.value.selectedCustomerId)
                val sales = repository.recentSales()
                FreshPos(products, customers, cartResp, sales)
            }.onSuccess { result ->
                val (products, customers, cartResp, sales) = result
                state.value = state.value.copy(
                    loading = false,
                    products = products,
                    customers = customers,
                    recentSales = sales,
                )
                applyCartResponse(cartResp, state.value.customerDiscountActive())
            }.onFailure { err ->
                val authLost = err is HttpException && err.code() == 401
                state.value = state.value.copy(
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
        val customer = id?.let { cid -> state.value.customers.find { it.id == cid } }
        state.value = state.value.copy(
            selectedCustomerId = id,
            selectedCustomerDiscount = id != null,
        )
        refreshCart()
    }

    fun linkCustomerById(customerId: Int) {
        val customer = state.value.customers.find { it.id == customerId }
        if (customer == null) {
            state.value = state.value.copy(status = "Unknown customer id $customerId")
            return
        }
        setSelectedCustomerId(customerId)
        state.value = state.value.copy(
            status = "Linked ${customer.name} — customer discount",
        )
    }

    /** Reload cart lines and totals for the current (or cleared) customer link. */
    fun refreshCart() {
        if (!state.value.isAuthenticated) return
        val customerId = state.value.selectedCustomerId
        val discountAtRequest = state.value.customerDiscountActive()
        val generation = ++cartRefreshGeneration
        viewModelScope.launch {
            state.value = state.value.copy(loading = true)
            runCatching { repository.cart(customerId) }
                .onSuccess { resp ->
                    if (generation != cartRefreshGeneration) return@onSuccess
                    applyCartResponse(resp, discountAtRequest)
                }
                .onFailure { err ->
                    if (generation != cartRefreshGeneration) return@onFailure
                    val authLost = err is HttpException && err.code() == 401
                    state.value = state.value.copy(
                        isAuthenticated = !authLost,
                        status = when {
                            authLost -> "Session expired — sign in again"
                            else -> "Cart refresh failed: ${err.message ?: "Unable to connect"}"
                        },
                    )
                }
            if (generation == cartRefreshGeneration) {
                state.value = state.value.copy(loading = false)
            }
        }
    }

    fun setPaymentMethod(method: String) {
        state.value = state.value.copy(paymentMethod = method)
    }

    fun setBarcodeInput(value: String) {
        state.value = state.value.copy(barcodeInput = value)
    }

    fun setPinInput(value: String) {
        if (value.length <= 8) {
            state.value = state.value.copy(pinInput = value)
        }
    }

    fun unlock() {
        val entered = state.value.pinInput
        if (entered.isBlank()) {
            state.value = state.value.copy(status = "Enter PIN")
            return
        }
        viewModelScope.launch {
            state.value = state.value.copy(status = "Signing in...")
            runCatching { repository.unlockCashier(entered) }
                .onSuccess {
                    state.value = state.value.copy(
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
                    state.value = state.value.copy(
                        isAuthenticated = false,
                        status = msg,
                    )
                }
        }
    }

    fun lock() {
        viewModelScope.launch {
            runCatching { repository.logoutCashier() }
            state.value = PosUiState(
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
            val cid = state.value.selectedCustomerId
            runCatching { repository.addProduct(productId, cid) }
                .onSuccess { applyCartResponse(it, state.value.customerDiscountActive()) }
                .onFailure { err ->
                    val authLost = err is HttpException && err.code() == 401
                    state.value = state.value.copy(
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
        addByBarcodeValue(state.value.barcodeInput)
    }

    fun addByBarcodeValue(input: String) {
        val cleaned = input.trim()
        if (cleaned.isEmpty()) {
            state.value = state.value.copy(status = "Enter barcode or product ID")
            return
        }

        val asId = cleaned.toIntOrNull()
        val treatAsId = asId != null && cleaned.length <= 6

        // Scan field adds products when the ID matches a product (even if the same number is a customer ID).
        // Link customers via Find customer when IDs overlap (e.g. product 2 and customer 2).
        if (treatAsId) {
            val hasProduct = state.value.products.any { it.id == asId }
            val hasCustomer = state.value.customers.any { it.id == asId }
            if (!hasProduct && hasCustomer) {
                linkCustomerById(asId)
                state.value = state.value.copy(barcodeInput = "")
                return
            }
        }

        viewModelScope.launch {
            val cid = state.value.selectedCustomerId
            runCatching {
                if (treatAsId) repository.addProduct(asId!!, cid) else repository.addProductByBarcode(cleaned, cid)
            }
                .onSuccess { resp ->
                    applyCartResponse(resp, state.value.customerDiscountActive())
                    state.value = state.value.copy(
                        barcodeInput = "",
                        status = if (treatAsId) "Added by id $cleaned" else "Scanned $cleaned",
                    )
                }
                .onFailure { err ->
                    val authLost = err is HttpException && err.code() == 401
                    state.value = state.value.copy(
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
        customerDiscount: Boolean = state.value.customerDiscountActive(),
    ) {
        val items = normalizeCartItems(resp.items, customerDiscount)
        val totals = computeCartTotals(items, customerDiscount)
        val status = when {
            customerDiscount && !resp.linked893 ->
                "Customer linked — pricing may be stale; try Unlink and link again"
            customerDiscount && totals.memberDiscount < 0.005 && items.isNotEmpty() ->
                "Customer linked — no discount on cart lines yet"
            customerDiscount -> "Customer discount applied"
            state.value.status == "Loading..." -> "Ready"
            else -> state.value.status
        }
        state.value = state.value.copy(
            cart = items,
            subtotalPreMember = totals.shelfSubtotal,
            subtotalPayable = totals.itemPreTax,
            memberDiscountPreTax = totals.memberDiscount,
            linked893Cart = customerDiscount && resp.linked893,
            status = status,
        )
    }

    fun removeCartItem(cartItemId: Int) {
        viewModelScope.launch {
            val cid = state.value.selectedCustomerId
            runCatching { repository.removeCartItem(cartItemId, cid) }
                .onSuccess { applyCartResponse(it, state.value.customerDiscountActive()) }
                .onFailure { state.value = state.value.copy(status = "Remove failed: ${it.message}") }
        }
    }

    fun checkout() {
        viewModelScope.launch {
            if (state.value.cart.isEmpty()) {
                state.value = state.value.copy(status = "Cart is empty")
                return@launch
            }

            val paymentMethod = state.value.paymentMethod
            val customerId = state.value.selectedCustomerId
            runCatching { repository.checkout(paymentMethod, customerId) }
                .onSuccess { receipt ->
                    val extra = buildList {
                        if (receipt.linked893 == true) add("customer discount")
                        receipt.memberDiscountPreTax?.takeIf { it > 0.001 }?.let { add("−${"%.2f".format(it)} pre-tax") }
                    }.joinToString(" · ").takeIf { it.isNotEmpty() }
                    val msg = listOfNotNull("Sale complete: ${receipt.orderNumber}", extra).joinToString(" — ")
                    state.value = state.value.copy(status = msg)
                    refresh()
                }
                .onFailure {
                    val lines = state.value.cart.map { QueuedCartLine(it.productId, it.quantity) }
                    queueStore.enqueue(paymentMethod, customerId, lines)
                    state.value = state.value.copy(
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
                state.value = state.value.copy(queuedCheckoutCount = 0, status = "No queued checkouts")
                return@launch
            }

            state.value = state.value.copy(queueSyncing = true, status = "Syncing ${queued.size} queued…")

            var synced = 0
            var droppedStale = 0
            val remaining = mutableListOf<PendingCheckout>()
            var lastError: String? = null

            for (pending in queued) {
                if (pending.cartLines.isEmpty()) {
                    droppedStale++
                    continue
                }
                val result = runCatching {
                    repository.replaceCart(pending.cartLines, pending.customerId)
                    repository.checkout(pending.paymentMethod, pending.customerId)
                }
                if (result.isSuccess) {
                    synced++
                } else {
                    remaining.add(pending)
                    lastError = result.exceptionOrNull()?.message
                }
            }

            queueStore.replace(remaining)
            val msg = buildString {
                if (synced > 0) append("Synced $synced sale(s)")
                if (droppedStale > 0) {
                    if (isNotEmpty()) append(" · ")
                    append("dropped $droppedStale old entries (no cart saved)")
                }
                if (remaining.isNotEmpty()) {
                    if (isNotEmpty()) append(" · ")
                    append("${remaining.size} still pending")
                    lastError?.let { append(": $it") }
                }
                if (isEmpty()) append("Nothing to sync")
            }

            refresh()
            state.value = state.value.copy(
                queueSyncing = false,
                queuedCheckoutCount = remaining.size,
                status = msg,
            )
        }
    }

    fun clearOfflineQueue() {
        queueStore.clear()
        state.value = state.value.copy(
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
