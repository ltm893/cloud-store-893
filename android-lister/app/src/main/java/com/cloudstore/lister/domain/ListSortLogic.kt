package com.cloudstore.lister.domain

import com.cloudstore.lister.data.InventoryListItem
import com.cloudstore.lister.data.InventoryNamedList

enum class ListSortField(val label: String) {
    Name("Name"),
    ProductType("Type"),
    ProductId("Product ID"),
    Barcode("Barcode"),
    Price("Price"),
    Stock("Stock"),
    PullCount("Pull Count"),
}

object ListSortLogic {
    fun sortList(
        id: String,
        field: ListSortField,
        ascending: Boolean,
        lists: List<InventoryNamedList>,
    ): List<InventoryNamedList>? {
        val index = lists.indexOfFirst { it.id == id }
        if (index < 0 || lists[index].items.isEmpty()) return null
        return lists.toMutableList().also {
            it[index] = it[index].copy(items = sorted(it[index].items, field, ascending))
        }
    }

    fun sorted(items: List<InventoryListItem>, field: ListSortField, ascending: Boolean): List<InventoryListItem> {
        return items.sortedWith { lhs, rhs ->
            val cmp = compare(lhs, rhs, field)
            when {
                cmp == 0 -> lhs.productId.compareTo(rhs.productId)
                ascending -> cmp
                else -> -cmp
            }
        }
    }

    private fun compare(lhs: InventoryListItem, rhs: InventoryListItem, field: ListSortField): Int {
        return when (field) {
            ListSortField.Name -> lhs.name.compareTo(rhs.name, ignoreCase = true)
            ListSortField.ProductType -> (lhs.productType ?: "").compareTo(rhs.productType ?: "", ignoreCase = true)
            ListSortField.ProductId -> lhs.productId.compareTo(rhs.productId)
            ListSortField.Barcode -> (lhs.barcode ?: "").compareTo(rhs.barcode ?: "", ignoreCase = true)
            ListSortField.Price -> lhs.priceLabel.compareTo(rhs.priceLabel, ignoreCase = true)
            ListSortField.Stock -> lhs.stockLabel.compareTo(rhs.stockLabel, ignoreCase = true)
            ListSortField.PullCount -> lhs.pullCount.compareTo(rhs.pullCount)
        }
    }
}
