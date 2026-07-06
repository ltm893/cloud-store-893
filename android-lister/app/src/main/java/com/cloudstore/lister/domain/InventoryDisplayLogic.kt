package com.cloudstore.lister.domain

object InventoryDisplayLogic {
    fun stockLabel(
        trackInventory: Boolean,
        quantityOnHand: Int?,
        inStock: Boolean,
        lowStock: Boolean,
    ): String {
        if (!trackInventory) return "Not tracked"
        val qty = quantityOnHand ?: return "—"
        if (!inStock) return "Out of stock"
        if (lowStock) return "$qty (low)"
        return qty.toString()
    }

    fun priceDetail(regularPrice: Double, onSale: Boolean, salePrice: Double?): String {
        if (onSale && salePrice != null) {
            return "Sale $%.2f (was $%.2f)".format(salePrice, regularPrice)
        }
        return "$%.2f".format(regularPrice)
    }
}
