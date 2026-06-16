package com.cloudstore.pos.domain.checkout

import com.cloudstore.pos.data.CheckoutPayment
import com.cloudstore.pos.domain.pricing.collectedTotal
import com.cloudstore.pos.domain.pricing.formatMoney
import com.cloudstore.pos.domain.pricing.remainingCashAmountDue
import com.cloudstore.pos.domain.pricing.roundMoney
import com.cloudstore.pos.domain.pricing.roundToNickel

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

fun isCardOnlyCheckout(payments: List<CheckoutPayment>): Boolean =
    payments.isNotEmpty() && payments.all { it.method == "card" }

fun isCashOnlyCheckout(payments: List<CheckoutPayment>): Boolean =
    payments.isNotEmpty() && payments.all { it.method == "cash" }

fun finalizeProcessingMessage(payments: List<CheckoutPayment>): String {
    val change = checkoutChangeTotal(payments)
    val completion = when {
        payments.size > 1 -> "Completing sale"
        isCardOnlyCheckout(payments) -> "Processing Card Payment"
        else -> "Completing sale"
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

fun exactBalanceDue(registerTotal: Double, payments: List<CheckoutPayment>): Double {
    val paid = roundMoney(payments.sumOf { it.amount })
    return roundMoney((collectedTotal(registerTotal) - paid).coerceAtLeast(0.0))
}

fun cashBalanceDue(registerTotal: Double, payments: List<CheckoutPayment>): Double {
    val cardPaid = roundMoney(payments.filter { it.method == "card" }.sumOf { it.amount })
    val cashPaid = roundMoney(payments.filter { it.method == "cash" }.sumOf { it.amount })
    val cashDue = remainingCashAmountDue(registerTotal, cardPaid)
    return roundMoney((cashDue - cashPaid).coerceAtLeast(0.0))
}

fun balanceDueForMethod(
    registerTotal: Double,
    payments: List<CheckoutPayment>,
    method: String,
): Double {
    val exact = exactBalanceDue(registerTotal, payments)
    return roundToNickel(exact)
}

fun expectedCollectedTotal(registerTotal: Double, payments: List<CheckoutPayment>): Double =
    collectedTotal(registerTotal)

fun isCheckoutComplete(registerTotal: Double, payments: List<CheckoutPayment>): Boolean {
    val paid = roundMoney(payments.sumOf { it.amount })
    return paid + 0.005 >= collectedTotal(registerTotal)
}
