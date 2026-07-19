package com.cloudstore.lister.domain

import com.cloudstore.lister.data.InventoryListDefaults
import com.cloudstore.lister.data.InventoryListItem
import com.cloudstore.lister.data.InventoryNamedList
import com.cloudstore.lister.data.ListDiffResult
import kotlin.math.ceil

object ListStoreLogic {
    fun defaultList(): InventoryNamedList = InventoryNamedList(
        id = InventoryListDefaults.MY_LIST_ID,
        name = InventoryListDefaults.MY_LIST_NAME,
        items = emptyList(),
        isDefault = true,
    )

    fun bootstrapLists(saved: List<InventoryNamedList>?): List<InventoryNamedList> {
        var lists = saved.orEmpty()
        if (lists.isEmpty()) return listOf(defaultList())
        val index = lists.indexOfFirst { it.id == InventoryListDefaults.MY_LIST_ID }
        if (index >= 0) {
            lists = lists.toMutableList()
            lists[index] = lists[index].copy(isDefault = true, name = InventoryListDefaults.MY_LIST_NAME)
            return lists
        }
        val legacyIndex = lists.indexOfFirst { it.isDefault || it.name == InventoryListDefaults.MY_LIST_NAME }
        if (legacyIndex >= 0) {
            val items = lists[legacyIndex].items
            val updated = lists.toMutableList()
            updated.removeAt(legacyIndex)
            updated.add(0, defaultList().copy(items = items))
            return updated
        }
        return listOf(defaultList()) + lists
    }

    fun resolveActiveListId(saved: String?, lists: List<InventoryNamedList>): String {
        if (!saved.isNullOrBlank() && lists.any { it.id == saved }) return saved
        return lists.firstOrNull()?.id ?: InventoryListDefaults.MY_LIST_ID
    }

    fun renameList(id: String, to: String, lists: List<InventoryNamedList>): List<InventoryNamedList>? {
        val index = lists.indexOfFirst { it.id == id }
        if (index < 0 || lists[index].isDefault) return null
        val trimmed = to.trim()
        if (trimmed.isEmpty()) return null
        return lists.toMutableList().also { it[index] = it[index].copy(name = trimmed) }
    }

    fun deleteList(id: String, lists: List<InventoryNamedList>): List<InventoryNamedList> {
        val index = lists.indexOfFirst { it.id == id }
        if (index < 0) return lists
        if (lists[index].isDefault) {
            return lists.toMutableList().also { it[index] = it[index].copy(items = emptyList()) }
        }
        return lists.filter { it.id != id }
    }

    fun createList(name: String, lists: List<InventoryNamedList>): Pair<List<InventoryNamedList>, String> {
        val trimmed = name.trim()
        val base = trimmed.ifEmpty { "New List" }
        val listName = uniqueListName(base, lists)
        val newList = InventoryNamedList(
            id = java.util.UUID.randomUUID().toString(),
            name = listName,
            items = emptyList(),
            isDefault = false,
        )
        return lists + newList to newList.id
    }

    fun uniqueListName(base: String, lists: List<InventoryNamedList>): String {
        val existing = lists.map { it.name }.toSet()
        if (!existing.contains(base)) return base
        var index = 2
        while (existing.contains("$base-$index")) index++
        return "$base-$index"
    }

    fun addItem(item: InventoryListItem, toListId: String, lists: List<InventoryNamedList>): List<InventoryNamedList> {
        val listIndex = lists.indexOfFirst { it.id == toListId }
        if (listIndex < 0) return lists
        val updated = lists.toMutableList()
        val items = updated[listIndex].items.toMutableList()
        val existingIndex = items.indexOfFirst { it.productId == item.productId }
        if (existingIndex >= 0) {
            items[existingIndex] = items[existingIndex].copy(pullCount = items[existingIndex].pullCount + 1)
        } else {
            items.add(item)
        }
        updated[listIndex] = updated[listIndex].copy(items = items)
        return updated
    }

    /**
     * Copies [item] into [targetListId] (new id). Same product on target increments pull count.
     * Returns null if target is missing or equals the source (active) list.
     */
    fun copyItem(
        lists: List<InventoryNamedList>,
        activeListId: String,
        item: InventoryListItem,
        targetListId: String,
    ): List<InventoryNamedList>? {
        if (targetListId == activeListId) return null
        if (lists.none { it.id == targetListId }) return null
        val clone = item.copy(id = java.util.UUID.randomUUID().toString())
        return addItem(clone, targetListId, lists)
    }

    /**
     * Moves [item] from the active list into [targetListId].
     * Returns null if the transfer is invalid.
     */
    fun moveItem(
        lists: List<InventoryNamedList>,
        activeListId: String,
        item: InventoryListItem,
        targetListId: String,
    ): List<InventoryNamedList>? {
        val source = lists.firstOrNull { it.id == activeListId } ?: return null
        if (source.items.none { it.id == item.id }) return null
        val copied = copyItem(lists, activeListId, item, targetListId) ?: return null
        return copied.map { list ->
            if (list.id != activeListId) list
            else list.copy(items = list.items.filter { it.id != item.id })
        }
    }

    fun incrementPullCount(itemId: String, items: List<InventoryListItem>): List<InventoryListItem> {
        val index = items.indexOfFirst { it.id == itemId }
        if (index < 0) return items
        return items.toMutableList().also { it[index] = it[index].copy(pullCount = it[index].pullCount + 1) }
    }

    fun decrementPullCount(itemId: String, items: List<InventoryListItem>): List<InventoryListItem> {
        val index = items.indexOfFirst { it.id == itemId }
        if (index < 0) return items
        val updated = items.toMutableList()
        val next = updated[index].pullCount - 1
        if (next <= 0) updated.removeAt(index) else updated[index] = updated[index].copy(pullCount = next)
        return updated
    }

    fun unionLists(ids: List<String>, into: String, lists: List<InventoryNamedList>): Pair<List<InventoryNamedList>, String>? {
        if (ids.size < 2) return null
        val merged = linkedMapOf<Int, InventoryListItem>()
        ids.forEach { id ->
            lists.firstOrNull { it.id == id }?.items?.forEach { item ->
                val existing = merged[item.productId]
                if (existing == null) merged[item.productId] = item
                else merged[item.productId] = existing.copy(pullCount = existing.pullCount + item.pullCount)
            }
        }
        val base = into.trim().ifEmpty { "Union List" }
        val listName = uniqueListName(base, lists)
        val newList = InventoryNamedList(
            id = java.util.UUID.randomUUID().toString(),
            name = listName,
            items = merged.values.toList(),
            isDefault = false,
        )
        return (lists + newList) to newList.id
    }

    fun diffLists(aId: String, bId: String, lists: List<InventoryNamedList>): ListDiffResult? {
        val listA = lists.firstOrNull { it.id == aId } ?: return null
        val listB = lists.firstOrNull { it.id == bId } ?: return null
        val idsA = listA.items.map { it.productId }.toSet()
        val idsB = listB.items.map { it.productId }.toSet()
        return ListDiffResult(
            listAName = listA.name,
            listBName = listB.name,
            common = listA.items.filter { idsB.contains(it.productId) },
            onlyInA = listA.items.filter { !idsB.contains(it.productId) },
            onlyInB = listB.items.filter { !idsA.contains(it.productId) },
        )
    }

    enum class SplitMode {
        ByNumberOfLists,
        ByItemsPerList,
    }

    fun splitList(
        id: String,
        mode: SplitMode,
        count: Int,
        prefix: String,
        lists: List<InventoryNamedList>,
    ): Pair<List<InventoryNamedList>, String>? {
        val source = lists.firstOrNull { it.id == id } ?: return null
        if (source.items.isEmpty()) return null
        val items = source.items
        val chunkSize = when (mode) {
            SplitMode.ByNumberOfLists -> ceil(items.size.toDouble() / maxOf(1, count)).toInt()
            SplitMode.ByItemsPerList -> maxOf(1, count)
        }
        val cleanPrefix = prefix.trim().ifEmpty { source.name }
        var updated = lists.toMutableList()
        var offset = 0
        var partIndex = 1
        var lastId: String? = null
        while (offset < items.size) {
            val slice = items.subList(offset, minOf(offset + chunkSize, items.size))
            val rawName = "$cleanPrefix-$partIndex"
            val listName = uniqueListName(rawName, updated)
            val newList = InventoryNamedList(
                id = java.util.UUID.randomUUID().toString(),
                name = listName,
                items = slice,
                isDefault = false,
            )
            updated.add(newList)
            lastId = newList.id
            offset += chunkSize
            partIndex++
        }
        return updated to (lastId ?: return null)
    }
}
