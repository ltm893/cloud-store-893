package com.cloudstore.pos.data

import com.squareup.moshi.Json

data class Product(
    val id: Int,
    val barcode: String?,
    val name: String,
    @Json(name = "regularPrice") val regularPrice: Double,
    @Json(name = "salePrice") val salePrice: Double? = null,
    @Json(name = "onSale") val onSale: Boolean = false,
)

data class StoreCustomer(
    val id: Int,
    val name: String,
    val email: String? = null,
    val phone: String? = null,
    @Json(name = "memberCode") val memberCode: String? = null,
    @Json(name = "is893") val is893: Boolean = false,
    @Json(name = "hasCardOnFile") val hasCardOnFile: Boolean = false,
    @Json(name = "cardLast4") val cardLast4: String? = null,
)

data class CartItem(
    val id: Int,
    @Json(name = "productId") val productId: Int,
    val name: String,
    @Json(name = "regularPrice") val regularPrice: Double,
    @Json(name = "salePrice") val salePrice: Double? = null,
    @Json(name = "onSale") val onSale: Boolean = false,
    val quantity: Int,
    @Json(name = "unitPricePublic") val unitPricePublic: Double,
    @Json(name = "unitPricePayable") val unitPricePayable: Double,
    @Json(name = "lineSubtotalPublic") val lineSubtotalPublic: Double,
    @Json(name = "lineSubtotalPayable") val lineSubtotalPayable: Double,
)

data class CartResponse(
    val items: List<CartItem>,
    @Json(name = "subtotalPreMember") val subtotalPreMember: Double,
    @Json(name = "subtotalPayable") val subtotalPayable: Double,
    @Json(name = "memberDiscountPreTax") val memberDiscountPreTax: Double,
    @Json(name = "linked893") val linked893: Boolean,
)

data class Sale(
    val id: Int,
    @Json(name = "orderNumber") val orderNumber: String,
    val total: Double,
    @Json(name = "paymentMethod") val paymentMethod: String,
    @Json(name = "linked893") val linked893: Boolean = false,
    @Json(name = "memberDiscountPreTax") val memberDiscountPreTax: Double = 0.0,
    @Json(name = "subtotalPreMember") val subtotalPreMember: Double = 0.0,
)

data class UnlockResponse(
    val ok: Boolean = false,
)

data class CartLineQuantity(
    @Json(name = "productId") val productId: Int,
    val quantity: Int,
)

data class CartReplaceRequest(
    val items: List<CartLineQuantity>,
    @Json(name = "customerId") val customerId: Int? = null,
)

data class CheckoutPayment(
    val method: String,
    val amount: Double,
    @Json(name = "tenderedAmount") val tenderedAmount: Double? = null,
    @Json(name = "changeGiven") val changeGiven: Double? = null,
)

data class CheckoutRequest(
    @Json(name = "paymentMethod") val paymentMethod: String,
    @Json(name = "customerId") val customerId: Int? = null,
    val payments: List<CheckoutPayment>? = null,
    @Json(name = "checkoutTotal") val checkoutTotal: Double? = null,
)

data class CheckoutResponse(
    val ok: Boolean,
    @Json(name = "orderNumber") val orderNumber: String,
    val total: Double,
    @Json(name = "paymentMethod") val paymentMethod: String? = null,
    @Json(name = "subtotalPreMember") val subtotalPreMember: Double? = null,
    @Json(name = "memberDiscountPreTax") val memberDiscountPreTax: Double? = null,
    @Json(name = "linked893") val linked893: Boolean? = null,
    @Json(name = "customerId") val customerId: Int? = null,
    val payments: List<CheckoutPayment>? = null,
)
