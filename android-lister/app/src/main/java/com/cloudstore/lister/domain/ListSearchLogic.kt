package com.cloudstore.lister.domain

import com.cloudstore.lister.data.InventoryListItem

object ListSearchLogic {
    /** Case-insensitive substring match across all searchable [InventoryListItem] fields. */
    fun filtered(items: List<InventoryListItem>, query: String): List<InventoryListItem> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return items
        return items.filter { matches(it, trimmed) }
    }

    fun matches(item: InventoryListItem, query: String): Boolean {
        val needle = query.trim()
        if (needle.isEmpty()) return true
        return searchableValues(item).any { it.contains(needle, ignoreCase = true) }
    }

    private fun searchableValues(item: InventoryListItem): List<String> {
        return listOfNotNull(
            item.name.takeIf { it.isNotEmpty() },
            item.productType?.takeIf { it.isNotEmpty() },
            item.manufacturer?.takeIf { it.isNotEmpty() },
            item.barcode?.takeIf { it.isNotEmpty() },
            item.productId.toString(),
            item.priceLabel.takeIf { it.isNotEmpty() },
            item.stockLabel.takeIf { it.isNotEmpty() },
            item.pullCount.toString(),
        )
    }
}
