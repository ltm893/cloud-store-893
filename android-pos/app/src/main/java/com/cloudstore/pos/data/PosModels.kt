package com.cloudstore.pos.data

import com.squareup.moshi.Json

data class Product(
    val id: Int,
    val barcode: String?,
    val name: String,
    @Json(name = "regularPrice") val regularPrice: Double,
    @Json(name = "salePrice") val salePrice: Double? = null,
    @Json(name = "onSale") val onSale: Boolean = false,
    @Json(name = "inStock") val inStock: Boolean = true,
    @Json(name = "quantityOnHand") val quantityOnHand: Int? = null,
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

data class OkResponse(
    val ok: Boolean = false,
)

/** @deprecated Use [CashierSessionResponse] for session probe. */
typealias UnlockResponse = OkResponse

data class PendingApprovalInfo(
    @Json(name = "requestToken") val requestToken: String? = null,
    val status: String? = null,
    @Json(name = "expiresAt") val expiresAt: String? = null,
    @Json(name = "cashierEmail") val cashierEmail: String? = null,
    @Json(name = "cashierName") val cashierName: String? = null,
    @Json(name = "secondsRemaining") val secondsRemaining: Int? = null,
)

data class CashierSessionResponse(
    val ok: Boolean = false,
    val pending: Boolean = false,
    val auth: String? = null,
    val sub: String? = null,
    val email: String? = null,
    val name: String? = null,
    val user: String? = null,
    @Json(name = "cashierEmail") val cashierEmail: String? = null,
    @Json(name = "supervisorApprovalRequired") val supervisorApprovalRequired: Boolean = false,
    @Json(name = "idpEnabled") val idpEnabled: Boolean = false,
    @Json(name = "idpLoginUrl") val idpLoginUrl: String? = null,
    @Json(name = "pinAllowed") val pinAllowed: Boolean = true,
    val approval: PendingApprovalInfo? = null,
    val error: String? = null,
) {
    fun displayUser(): String? {
        if (!ok) return null
        listOf(
            user,
            email,
            cashierEmail,
            approval?.cashierEmail,
            name,
            approval?.cashierName,
            sub?.takeIf { it.contains("@") },
        ).forEach { candidate ->
            candidate?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        }
        return if (auth == "pin") "Cashier" else null
    }
}

data class ApprovalStatusResponse(
    val status: String,
    val ok: Boolean = false,
    val email: String? = null,
    @Json(name = "cashierEmail") val cashierEmail: String? = null,
    val name: String? = null,
    @Json(name = "cashierName") val cashierName: String? = null,
    val reason: String? = null,
    @Json(name = "secondsRemaining") val secondsRemaining: Int? = null,
    @Json(name = "expiresAt") val expiresAt: String? = null,
    val error: String? = null,
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
