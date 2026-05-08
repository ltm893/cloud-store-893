package com.cloudstore.pos.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.cloudstore.pos.data.CartItem
import com.cloudstore.pos.data.OfflineQueueStore
import com.cloudstore.pos.data.PendingCheckout
import com.cloudstore.pos.data.PosRepository
import com.cloudstore.pos.data.Product
import com.cloudstore.pos.data.Sale
import kotlinx.coroutines.launch

data class PosUiState(
    val loading: Boolean = false,
    val products: List<Product> = emptyList(),
    val cart: List<CartItem> = emptyList(),
    val recentSales: List<Sale> = emptyList(),
    val paymentMethod: String = "card",
    val barcodeInput: String = "",
    val status: String = "Ready",
    val isAuthenticated: Boolean = false,
    val pinInput: String = "",
    val queuedCheckoutCount: Int = 0,
) {
    val total: Double = cart.sumOf { it.price * it.quantity }
}

class PosViewModel(
    private val repository: PosRepository,
    private val queueStore: OfflineQueueStore,
    private val expectedPin: String,
) : ViewModel() {
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
                val cart = repository.cart()
                val sales = repository.recentSales()
                Triple(products, cart, sales)
            }.onSuccess { result ->
                val (products, cart, sales) = result
                state.value = state.value.copy(
                    loading = false,
                    products = products,
                    cart = cart,
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

    fun addProduct(productId: Int) {
        viewModelScope.launch {
            runCatching { repository.addProduct(productId) }
                .onSuccess { refresh() }
                .onFailure { state.value = state.value.copy(status = "Add failed: ${it.message}") }
        }
    }

    fun addByBarcode() {
        val barcode = state.value.barcodeInput.trim()
        addByBarcodeValue(barcode)
    }

    fun addByBarcodeValue(barcode: String) {
        if (barcode.isEmpty()) {
            state.value = state.value.copy(status = "Enter barcode")
            return
        }

        viewModelScope.launch {
            runCatching { repository.addProductByBarcode(barcode) }
                .onSuccess {
                    state.value = state.value.copy(barcodeInput = "", status = "Scanned $barcode")
                    refresh()
                }
                .onFailure { state.value = state.value.copy(status = "Scan failed: ${it.message}") }
        }
    }

    fun removeCartItem(cartItemId: Int) {
        viewModelScope.launch {
            runCatching { repository.removeCartItem(cartItemId) }
                .onSuccess { refresh() }
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
            runCatching { repository.checkout(paymentMethod) }
                .onSuccess { receipt ->
                    state.value = state.value.copy(status = "Sale complete: ${receipt.orderNumber}")
                    refresh()
                }
                .onFailure {
                    queueStore.enqueue(paymentMethod)
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
                val result = runCatching { repository.checkout(pending.paymentMethod) }
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
