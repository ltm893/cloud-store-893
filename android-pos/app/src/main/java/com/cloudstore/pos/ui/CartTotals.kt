package com.cloudstore.pos.ui

import com.cloudstore.pos.data.CartItem
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.round

fun roundMoney(amount: Double): Double = round(amount * 100.0) / 100.0

fun formatMoney(amount: Double): String = "\$${"%.2f".format(amount)}"

/** Cash: round down to nearest $0.05 (no pennies). e.g. $19.06 → $19.05, $19.08 → $19.05 */
fun roundToNickel(amount: Double): Double = roundMoney(floor(amount * 20.0) / 20.0)

/** Next up to 3 standard bills that cover [amountDue] (e.g. $4.50 → $5, $10, $20). Credit-only uses exact amount only. */
fun cashQuickDenominations(amountDue: Double, cashEnabled: Boolean = true): List<Int> {
    if (!cashEnabled || amountDue <= 0.005) return emptyList()
    val bills = listOf(5, 10, 20, 50, 100)
    val start = bills.indexOfFirst { it >= amountDue - 0.001 }
    if (start < 0) return listOf(100)
    return bills.drop(start).take(3)
}

/** When no customer discount, reset lines to public shelf prices (fixes stale discounted lines). */
fun normalizeCartItems(items: List<CartItem>, customerDiscount: Boolean): List<CartItem> {
    if (customerDiscount) return items
    return items.map { item ->
        if (abs(item.lineSubtotalPayable - item.lineSubtotalPublic) <= 0.005) {
            item
        } else {
            item.copy(
                unitPricePayable = item.unitPricePublic,
                lineSubtotalPayable = item.lineSubtotalPublic,
            )
        }
    }
}

data class CartTotals(
    val itemCount: Int,
    val shelfSubtotal: Double,
    val itemPreTax: Double,
    val memberDiscount: Double,
    val saleSavings: Double,
    val linked893: Boolean,
) {
    val showMemberPricing: Boolean get() = linked893
    val showDiscount: Boolean get() = linked893 && memberDiscount > 0.005
}

/** Shelf savings from product sale prices (list − sale), before customer discount. */
fun computeSaleSavings(cart: List<CartItem>): Double {
    val raw = cart
        .filter { it.onSale && it.salePrice != null }
        .sumOf { item ->
            roundMoney(item.regularPrice) * item.quantity - item.lineSubtotalPublic
        }
    return roundMoney(raw.coerceAtLeast(0.0))
}

/** Cart line totals; [customerDiscount] drives member pricing and sets [CartTotals.linked893]. */
fun computeCartTotals(cart: List<CartItem>, customerDiscount: Boolean): CartTotals {
    val shelf = cart.sumOf { it.lineSubtotalPublic }
    val preTax = if (customerDiscount) {
        cart.sumOf { it.lineSubtotalPayable }
    } else {
        shelf
    }
    val discount = if (customerDiscount) roundMoney(shelf - preTax) else 0.0
    return CartTotals(
        itemCount = cart.sumOf { it.quantity },
        shelfSubtotal = roundMoney(shelf),
        itemPreTax = roundMoney(preTax),
        memberDiscount = discount,
        saleSavings = computeSaleSavings(cart),
        linked893 = customerDiscount,
    )
}

/** Grand total (pre-tax + sales fee + tax) for checkout / cash tendered. */
fun computeSaleGrandTotal(
    cart: List<CartItem>,
    customerLinked: Boolean,
    customerDiscount: Boolean,
    salesFeeRate: Double,
    taxRate: Double,
): Double {
    val items = if (customerLinked) normalizeCartItems(cart, customerDiscount) else cart
    val totals = computeCartTotals(items, customerLinked && customerDiscount)
    val salesFee = totals.itemPreTax * salesFeeRate
    val taxable = totals.itemPreTax + salesFee
    val taxAmt = taxable * taxRate
    return roundMoney(taxable + taxAmt)
}

/** Tax-inclusive total rounded down to nickel — use for cash tendered / change only. */
fun computeCashAmountDue(
    cart: List<CartItem>,
    customerLinked: Boolean,
    customerDiscount: Boolean,
    salesFeeRate: Double,
    taxRate: Double,
): Double = collectedTotal(
    computeSaleGrandTotal(cart, customerLinked, customerDiscount, salesFeeRate, taxRate),
)

fun collectedTotal(registerTotal: Double): Double = roundToNickel(registerTotal)

fun remainingCashAmountDue(registerTotal: Double, nonCashPaid: Double): Double {
    val collected = collectedTotal(registerTotal)
    return roundToNickel(roundMoney((collected - nonCashPaid).coerceAtLeast(0.0)))
}
