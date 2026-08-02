package com.cloudstore.lister.domain

import com.cloudstore.lister.data.InventoryListItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ListSearchLogicTest {

    private fun item(
        productId: Int = 100,
        barcode: String? = "012345678905",
        name: String = "Widget",
        productType: String? = "General",
        manufacturer: String? = "Acme",
        priceLabel: String = "$9.99",
        stockLabel: String = "5 in stock",
        pullCount: Int = 2,
    ) = InventoryListItem(
        productId = productId,
        barcode = barcode,
        name = name,
        productType = productType,
        manufacturer = manufacturer,
        priceLabel = priceLabel,
        stockLabel = stockLabel,
        stockEmphasis = false,
        pullCount = pullCount,
    )

    @Test
    fun emptyQueryReturnsAll() {
        val items = listOf(item(name = "A"), item(name = "B"))
        assertEquals(listOf("A", "B"), ListSearchLogic.filtered(items, "").map { it.name })
        assertEquals(listOf("A", "B"), ListSearchLogic.filtered(items, "   ").map { it.name })
    }

    @Test
    fun matchesNameCaseInsensitive() {
        val items = listOf(item(name = "Blue Widget"), item(name = "Red Gadget"))
        assertEquals(listOf("Blue Widget"), ListSearchLogic.filtered(items, "widget").map { it.name })
    }

    @Test
    fun matchesProductIdBarcodeManufacturerTypePriceStockPull() {
        val target = item(
            productId = 4242,
            barcode = "998877",
            name = "Keep",
            productType = "Beverage",
            manufacturer = "Northstar",
            priceLabel = "$12.50",
            stockLabel = "Out of stock",
            pullCount = 7,
        )
        val other = item(productId = 1, barcode = "000", name = "Other", productType = "X", manufacturer = "Y")
        val items = listOf(target, other)

        assertEquals(listOf("Keep"), ListSearchLogic.filtered(items, "4242").map { it.name })
        assertEquals(listOf("Keep"), ListSearchLogic.filtered(items, "998877").map { it.name })
        assertEquals(listOf("Keep"), ListSearchLogic.filtered(items, "north").map { it.name })
        assertEquals(listOf("Keep"), ListSearchLogic.filtered(items, "bever").map { it.name })
        assertEquals(listOf("Keep"), ListSearchLogic.filtered(items, "12.50").map { it.name })
        assertEquals(listOf("Keep"), ListSearchLogic.filtered(items, "out of").map { it.name })
        assertEquals(listOf("Keep"), ListSearchLogic.filtered(items, "7").map { it.name })
    }

    @Test
    fun noMatchesReturnsEmpty() {
        assertTrue(ListSearchLogic.filtered(listOf(item(name = "Only")), "zzz").isEmpty())
    }
}
