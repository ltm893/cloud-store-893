package com.cloudstore.pos.ui

import com.cloudstore.pos.data.CheckoutPayment

data class CheckoutUiState(
    val open: Boolean = false,
    val amountInput: String = "",
    val payments: List<CheckoutPayment> = emptyList(),
    val saleItemsLocked: Boolean = false,
    val processingCardPayment: CheckoutPayment? = null,
    val processingCheckoutMethod: String? = null,
    val processingDialogMessage: String? = null,
    val paymentProcessingProgress: Float = 0f,
    val pendingCheckoutPayments: List<CheckoutPayment>? = null,
    val pendingCheckoutTotal: Double? = null,
)
