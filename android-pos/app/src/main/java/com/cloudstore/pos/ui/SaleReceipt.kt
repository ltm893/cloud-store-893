package com.cloudstore.pos.ui

import com.cloudstore.pos.data.CartItem
import com.cloudstore.pos.data.CheckoutPayment
import com.cloudstore.pos.data.StoreCustomer
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

data class ReceiptLine(
    val productId: Int,
    val quantity: Int,
    val name: String,
    val lineTotal: Double,
)

data class SaleReceipt(
    val orderNumber: String?,
    val completedAtMillis: Long,
    val customerName: String?,
    val lines: List<ReceiptLine>,
    val itemCount: Int,
    val subtotal: Double,
    val savings: Double,
    val tax: Double,
    val grandTotal: Double,
    val collectedTotal: Double,
    val payments: List<CheckoutPayment>,
    val changeTotal: Double,
    val queuedOffline: Boolean = false,
) {
    fun formattedTimestamp(): String {
        val formatter = DateTimeFormatter.ofPattern("MMM d, yyyy  h:mm a")
        return Instant.ofEpochMilli(completedAtMillis)
            .atZone(ZoneId.systemDefault())
            .format(formatter)
    }

    fun orderLabel(): String = when {
        queuedOffline -> "Queued for sync"
        !orderNumber.isNullOrBlank() -> orderNumber
        else -> "Sale complete"
    }
}

fun customerDisplayName(customer: StoreCustomer?, customerId: Int): String {
    if (customer != null) {
        return customer.name
    }
    return "Customer #$customerId"
}

fun buildSaleReceipt(
    cart: List<CartItem>,
    customerName: String?,
    customerLinked: Boolean,
    customerDiscount: Boolean,
    salesFeeRate: Double,
    taxRate: Double,
    payments: List<CheckoutPayment>,
    orderNumber: String? = null,
    queuedOffline: Boolean = false,
    completedAtMillis: Long = System.currentTimeMillis(),
): SaleReceipt {
    val items = if (customerLinked) normalizeCartItems(cart, customerDiscount) else cart
    val totals = computeCartTotals(items, customerLinked && customerDiscount)
    val salesFee = totals.itemPreTax * salesFeeRate
    val taxable = totals.itemPreTax + salesFee
    val taxAmt = roundMoney(taxable * taxRate)
    val grandTotal = roundMoney(taxable + taxAmt)
    val collectedTotal = roundMoney(payments.sumOf { it.amount })

    return SaleReceipt(
        orderNumber = orderNumber,
        completedAtMillis = completedAtMillis,
        customerName = customerName,
        lines = items.map { item ->
            ReceiptLine(
                productId = item.productId,
                quantity = item.quantity,
                name = item.name,
                lineTotal = roundMoney(item.lineSubtotalPayable),
            )
        },
        itemCount = totals.itemCount,
        subtotal = totals.itemPreTax,
        savings = totals.saleSavings,
        tax = taxAmt,
        grandTotal = grandTotal,
        collectedTotal = collectedTotal,
        payments = payments,
        changeTotal = checkoutChangeTotal(payments),
        queuedOffline = queuedOffline,
    )
}
