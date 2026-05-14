package com.cloudstore.pos.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.cloudstore.pos.data.CartItem
import com.cloudstore.pos.data.CartResponse
import com.cloudstore.pos.data.OfflineQueueStore
import com.cloudstore.pos.data.PendingCheckout
import com.cloudstore.pos.data.PosRepository
import com.cloudstore.pos.data.Product
import com.cloudstore.pos.data.Sale
import com.cloudstore.pos.data.StoreCustomer
import kotlinx.coroutines.launch

data class PosUiState(
    val loading: Boolean = false,
    val products: List<Product> = emptyList(),
    val customers: List<StoreCustomer> = emptyList(),
    val selectedCustomerId: Int? = null,
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
)

class PosViewModel(
    private val repository: PosRepository,
    private val queueStore: OfflineQueueStore,
    private val expectedPin: String,
) : ViewModel() {
    private data class FreshPos(
        val products: List<Product>,
        val customers: List<StoreCustomer>,
        val cart: CartResponse,
        val sales: List<Sale>,
    )

    var state = androidx.compose.runtime.mutableStateOf(PosUiState())
        private set

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
                    cart = cartResp.items,
                    subtotalPreMember = cartResp.subtotalPreMember,
                    subtotalPayable = cartResp.subtotalPayable,
                    memberDiscountPreTax = cartResp.memberDiscountPreTax,
                    linked893Cart = cartResp.linked893,
                    recentSales = sales,
                    status = "Ready",
                )
            }.onFailure { err ->
                state.value = state.value.copy(
                    loading = false,
                    status = "Error: ${err.message ?: "Unable to connect"}",
                )
            }
        }
    }

    fun setSelectedCustomerId(id: Int?) {
        state.value = state.value.copy(selectedCustomerId = id)
        refresh()
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
        if (entered != expectedPin) {
            state.value = state.value.copy(status = "Invalid PIN")
            return
        }
        state.value = state.value.copy(isAuthenticated = true, pinInput = "", status = "Signed in")
        refresh()
        flushOfflineQueue()
    }

    fun lock() {
        state.value = PosUiState(
            isAuthenticated = false,
            pinInput = "",
            barcodeInput = "",
            queuedCheckoutCount = queueStore.all().size,
            status = "Signed out",
        )
    }

    fun addProduct(productId: Int) {
        viewModelScope.launch {
            val cid = state.value.selectedCustomerId
            runCatching { repository.addProduct(productId, cid) }
                .onSuccess { applyCartResponse(it) }
                .onFailure { state.value = state.value.copy(status = "Add failed: ${it.message}") }
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

        viewModelScope.launch {
            val cid = state.value.selectedCustomerId
            runCatching {
                if (treatAsId) repository.addProduct(asId!!, cid) else repository.addProductByBarcode(cleaned, cid)
            }
                .onSuccess { resp ->
                    applyCartResponse(resp)
                    state.value = state.value.copy(
                        barcodeInput = "",
                        status = if (treatAsId) "Added by id $cleaned" else "Scanned $cleaned",
                    )
                }
                .onFailure { state.value = state.value.copy(status = "Add failed: ${it.message}") }
        }
    }

    private fun applyCartResponse(resp: CartResponse) {
        state.value = state.value.copy(
            cart = resp.items,
            subtotalPreMember = resp.subtotalPreMember,
            subtotalPayable = resp.subtotalPayable,
            memberDiscountPreTax = resp.memberDiscountPreTax,
            linked893Cart = resp.linked893,
        )
    }

    fun removeCartItem(cartItemId: Int) {
        viewModelScope.launch {
            val cid = state.value.selectedCustomerId
            runCatching { repository.removeCartItem(cartItemId, cid) }
                .onSuccess { applyCartResponse(it) }
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
                        if (receipt.linked893 == true) add("893 member")
                        receipt.memberDiscountPreTax?.takeIf { it > 0.001 }?.let { add("−${"%.2f".format(it)} pre-tax") }
                    }.joinToString(" · ").takeIf { it.isNotEmpty() }
                    val msg = listOfNotNull("Sale complete: ${receipt.orderNumber}", extra).joinToString(" — ")
                    state.value = state.value.copy(status = msg)
                    refresh()
                }
                .onFailure {
                    queueStore.enqueue(paymentMethod, customerId)
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
                state.value = state.value.copy(queuedCheckoutCount = 0)
                return@launch
            }

            val remaining = mutableListOf<PendingCheckout>()
            for (pending in queued) {
                val result = runCatching { repository.checkout(pending.paymentMethod, pending.customerId) }
                if (result.isFailure) {
                    remaining.add(pending)
                }
            }

            queueStore.replace(remaining)
            state.value = state.value.copy(
                queuedCheckoutCount = remaining.size,
                status = if (remaining.isEmpty()) "Queued checkouts synced" else "Some queued checkouts pending",
            )
            refresh()
        }
    }

}

class PosViewModelFactory(
    private val repository: PosRepository,
    private val queueStore: OfflineQueueStore,
    private val expectedPin: String,
) : ViewModelProvider.Factory {
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(PosViewModel::class.java)) {
            @Suppress("UNCHECKED_CAST")
            return PosViewModel(repository, queueStore, expectedPin) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class")
    }
}
