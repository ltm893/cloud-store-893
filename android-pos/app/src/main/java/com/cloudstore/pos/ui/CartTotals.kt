package com.cloudstore.pos.ui

import com.cloudstore.pos.data.CartItem
import kotlin.math.abs
import kotlin.math.round

fun roundMoney(amount: Double): Double = round(amount * 100.0) / 100.0

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
    val linked893: Boolean,
) {
    val showMemberPricing: Boolean get() = linked893
    val showDiscount: Boolean get() = linked893 && memberDiscount > 0.005
}

/** Linked customer present — show full pricing breakdown (guest discount may be $0). */
fun computeCartTotalsForLinkedCustomer(cart: List<CartItem>, customerDiscount: Boolean): CartTotals {
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
        linked893 = customerDiscount,
    )
}

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
        linked893 = customerDiscount,
    )
}
