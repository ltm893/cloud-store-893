package com.cloudstore.lister.domain

import com.cloudstore.lister.data.InventoryListDefaults
import com.cloudstore.lister.data.InventoryListItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ListStoreLogicCopyMoveTest {

    @Test
    fun copyItemAddsCloneAndKeepsSource() {
        var lists = ListStoreLogic.bootstrapLists(null)
        val (withTarget, targetId) = ListStoreLogic.createList("Target", lists)
        lists = withTarget
        val source = sampleItem(productId = 1, name = "Widget", pullCount = 2)
        lists = ListStoreLogic.addItem(source, InventoryListDefaults.MY_LIST_ID, lists)
        val stored = lists.first { it.id == InventoryListDefaults.MY_LIST_ID }.items.first()

        val updated = ListStoreLogic.copyItem(lists, InventoryListDefaults.MY_LIST_ID, stored, targetId)!!

        val sourceList = updated.first { it.id == InventoryListDefaults.MY_LIST_ID }
        val targetList = updated.first { it.id == targetId }
        assertEquals(1, sourceList.items.size)
        assertEquals(1, targetList.items.size)
        assertEquals(1, targetList.items.first().productId)
        assertNotEquals(stored.id, targetList.items.first().id)
        assertEquals(2, targetList.items.first().pullCount)
    }

    @Test
    fun copyItemIncrementsPullWhenProductExistsOnTarget() {
        var lists = ListStoreLogic.bootstrapLists(null)
        val (withTarget, targetId) = ListStoreLogic.createList("Target", lists)
        lists = withTarget
        lists = ListStoreLogic.addItem(sampleItem(1, pullCount = 1), InventoryListDefaults.MY_LIST_ID, lists)
        lists = ListStoreLogic.addItem(sampleItem(1, pullCount = 3), targetId, lists)
        val stored = lists.first { it.id == InventoryListDefaults.MY_LIST_ID }.items.first()

        val updated = ListStoreLogic.copyItem(lists, InventoryListDefaults.MY_LIST_ID, stored, targetId)!!

        assertEquals(1, updated.first { it.id == targetId }.items.size)
        assertEquals(4, updated.first { it.id == targetId }.items.first().pullCount)
    }

    @Test
    fun copyItemReturnsNullWhenDestinationIsActiveList() {
        var lists = ListStoreLogic.bootstrapLists(null)
        lists = ListStoreLogic.addItem(sampleItem(1), InventoryListDefaults.MY_LIST_ID, lists)
        val stored = lists.first().items.first()
        assertNull(ListStoreLogic.copyItem(lists, InventoryListDefaults.MY_LIST_ID, stored, InventoryListDefaults.MY_LIST_ID))
    }

    @Test
    fun moveItemRemovesFromSource() {
        var lists = ListStoreLogic.bootstrapLists(null)
        val (withTarget, targetId) = ListStoreLogic.createList("Target", lists)
        lists = withTarget
        lists = ListStoreLogic.addItem(sampleItem(1, name = "Widget"), InventoryListDefaults.MY_LIST_ID, lists)
        val stored = lists.first { it.id == InventoryListDefaults.MY_LIST_ID }.items.first()

        val updated = ListStoreLogic.moveItem(lists, InventoryListDefaults.MY_LIST_ID, stored, targetId)!!

        assertTrue(updated.first { it.id == InventoryListDefaults.MY_LIST_ID }.items.isEmpty())
        assertEquals(1, updated.first { it.id == targetId }.items.size)
        assertEquals(1, updated.first { it.id == targetId }.items.first().productId)
    }

    @Test
    fun moveItemReturnsNullForUnknownDestination() {
        var lists = ListStoreLogic.bootstrapLists(null)
        lists = ListStoreLogic.addItem(sampleItem(1), InventoryListDefaults.MY_LIST_ID, lists)
        val stored = lists.first().items.first()
        assertNull(ListStoreLogic.moveItem(lists, InventoryListDefaults.MY_LIST_ID, stored, "missing-id"))
    }

    @Test
    fun createListWithItemsClonesIntoNewList() {
        var lists = ListStoreLogic.bootstrapLists(null)
        lists = ListStoreLogic.addItem(sampleItem(1, name = "Widget", pullCount = 3), InventoryListDefaults.MY_LIST_ID, lists)
        lists = ListStoreLogic.addItem(sampleItem(2, name = "Gadget"), InventoryListDefaults.MY_LIST_ID, lists)
        val sourceItems = lists.first { it.id == InventoryListDefaults.MY_LIST_ID }.items

        val (updated, newId) = ListStoreLogic.createListWithItems("Diff Common", sourceItems, lists)

        val newList = updated.first { it.id == newId }
        assertEquals("Diff Common", newList.name)
        assertEquals(2, newList.items.size)
        assertEquals(3, newList.items.first { it.productId == 1 }.pullCount)
        assertNotEquals(sourceItems.first().id, newList.items.first { it.productId == 1 }.id)
        assertEquals(2, updated.first { it.id == InventoryListDefaults.MY_LIST_ID }.items.size)
    }

    private fun sampleItem(productId: Int, name: String = "Sample", pullCount: Int = 1) =
        InventoryListItem(
            productId = productId,
            barcode = null,
            name = name,
            productType = "Retail",
            manufacturer = null,
            priceLabel = "$9.99",
            stockLabel = "5",
            stockEmphasis = false,
            pullCount = pullCount,
        )
}
