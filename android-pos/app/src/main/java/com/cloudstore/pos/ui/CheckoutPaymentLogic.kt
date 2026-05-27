package com.cloudstore.pos.ui

import com.cloudstore.pos.data.CheckoutPayment

fun paymentMethodLabel(method: String): String = when (method) {
    "card" -> "Card"
    "cash" -> "Cash"
    "split" -> "Split"
    else -> method
}

fun checkoutFinalizeMethod(payments: List<CheckoutPayment>): String =
    if (payments.size == 1) payments.first().method else "split"

fun cardTerminalMessage(amount: Double): String =
    "Sending ${formatMoney(amount)} to Credit Terminal"

fun checkoutChangeTotal(payments: List<CheckoutPayment>): Double =
    roundMoney(payments.sumOf { it.changeGiven ?: 0.0 })

fun finalizeProcessingMessage(payments: List<CheckoutPayment>): String {
    val change = checkoutChangeTotal(payments)
    val method = checkoutFinalizeMethod(payments)
    val completion = when {
        payments.size > 1 -> "Completing sale"
        method == "cash" -> "Printing Receipt"
        else -> "Processing Card Payment"
    }
    return if (change > 0.005) {
        "Give change ${formatMoney(change)}\n$completion"
    } else {
        completion
    }
}

fun buildCheckoutPaymentLine(
    method: String,
    enteredAmount: Double,
    balanceDue: Double,
): CheckoutPayment? {
    if (enteredAmount <= 0.0 || balanceDue <= 0.005) return null
    if (method == "card" && enteredAmount > balanceDue + 0.005) return null
    val appliedAmount = roundMoney(
        when (method) {
            "cash" -> minOf(enteredAmount, balanceDue)
            else -> enteredAmount
        },
    )
    if (appliedAmount <= 0.0) return null
    val changeGiven = if (method == "cash") {
        roundMoney((enteredAmount - balanceDue).coerceAtLeast(0.0))
    } else {
        0.0
    }
    return CheckoutPayment(
        method = method,
        amount = appliedAmount,
        tenderedAmount = enteredAmount,
        changeGiven = changeGiven.takeIf { it > 0.005 },
    )
}
