package com.cloudstore.pos.data

import com.squareup.moshi.Json

data class Product(
    val id: Int,
    val barcode: String?,
    val name: String,
    val price: Double,
)

data class CartItem(
    val id: Int,
    @Json(name = "product_id") val productId: Int,
    val name: String,
    val price: Double,
    val quantity: Int,
)

data class Sale(
    val id: Int,
    @Json(name = "order_number") val orderNumber: String,
    val total: Double,
    @Json(name = "payment_method") val paymentMethod: String,
)

data class CheckoutRequest(
    @Json(name = "paymentMethod") val paymentMethod: String,
)

data class CheckoutResponse(
    val ok: Boolean,
    @Json(name = "orderNumber") val orderNumber: String,
    val total: Double,
)
