package com.cloudstore.lister.data

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import java.util.UUID

@JsonClass(generateAdapter = true)
data class InventoryProduct(
    val id: Int,
    val barcode: String? = null,
    val name: String,
    @Json(name = "regularPrice") val regularPrice: Double,
    @Json(name = "salePrice") val salePrice: Double? = null,
    @Json(name = "onSale") val onSale: Boolean = false,
    @Json(name = "taxExempt") val taxExempt: Boolean = false,
    @Json(name = "inStock") val inStock: Boolean = true,
    @Json(name = "quantityOnHand") val quantityOnHand: Int? = null,
    @Json(name = "trackInventory") val trackInventory: Boolean = false,
    @Json(name = "productType") val productType: String? = null,
    val manufacturer: String? = null,
    @Json(name = "reorderPoint") val reorderPoint: Int? = null,
    @Json(name = "lowStock") val lowStock: Boolean = false,
)

@JsonClass(generateAdapter = true)
data class InventoryLookupErrorResponse(val error: String? = null)

@JsonClass(generateAdapter = true)
data class CashierSessionResponse(
    val ok: Boolean = false,
    val auth: String? = null,
    val email: String? = null,
    val name: String? = null,
    val user: String? = null,
    @Json(name = "cashierEmail") val cashierEmail: String? = null,
    @Json(name = "idpEnabled") val idpEnabled: Boolean = false,
    val error: String? = null,
) {
    val displayUser: String?
        get() {
            if (!ok) return null
            sequenceOf(user, email, cashierEmail, name).forEach { candidate ->
                val trimmed = candidate?.trim().orEmpty()
                if (trimmed.isNotEmpty()) return trimmed
            }
            return null
        }
}

@JsonClass(generateAdapter = true)
data class OkResponse(val ok: Boolean? = null)

@JsonClass(generateAdapter = true)
data class InventoryListItem(
    val id: String = UUID.randomUUID().toString(),
    val productId: Int,
    val barcode: String?,
    val name: String,
    val productType: String?,
    val manufacturer: String?,
    val priceLabel: String,
    val stockLabel: String,
    val stockEmphasis: Boolean,
    val pullCount: Int = 1,
) {
    companion object {
        fun fromProduct(product: InventoryProduct): InventoryListItem {
            return InventoryListItem(
                productId = product.id,
                barcode = product.barcode,
                name = product.name,
                productType = product.productType,
                manufacturer = product.manufacturer,
                priceLabel = com.cloudstore.lister.domain.InventoryDisplayLogic.priceDetail(
                    product.regularPrice,
                    product.onSale,
                    product.salePrice,
                ),
                stockLabel = com.cloudstore.lister.domain.InventoryDisplayLogic.stockLabel(
                    product.trackInventory,
                    product.quantityOnHand,
                    product.inStock,
                    product.lowStock,
                ),
                stockEmphasis = product.lowStock || !product.inStock,
            )
        }
    }

    fun refreshed(product: InventoryProduct, pullCount: Int? = null): InventoryListItem {
        return fromProduct(product).copy(id = id, pullCount = pullCount ?: this.pullCount)
    }

    fun withLookupFailure(message: String): InventoryListItem {
        return copy(stockLabel = message, stockEmphasis = true)
    }
}

@JsonClass(generateAdapter = true)
data class InventoryNamedList(
    val id: String,
    var name: String,
    var items: List<InventoryListItem>,
    var isDefault: Boolean = false,
)

object InventoryListDefaults {
    const val MY_LIST_ID = "A0000000-0000-4000-8000-000000000001"
    const val MY_LIST_NAME = "MyList"
}

data class ListDiffResult(
    val listAName: String,
    val listBName: String,
    val common: List<InventoryListItem>,
    val onlyInA: List<InventoryListItem>,
    val onlyInB: List<InventoryListItem>,
)
