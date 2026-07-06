package com.cloudstore.lister.domain

import com.cloudstore.lister.data.InventoryListItem
import java.io.File

object ListExportLogic {
    data class Summary(val itemCount: Int, val totalPullCount: Int)

    fun summary(items: List<InventoryListItem>): Summary {
        return Summary(
            itemCount = items.size,
            totalPullCount = items.sumOf { it.pullCount },
        )
    }

    fun buildCsv(items: List<InventoryListItem>): String {
        val header = "Name,Type,Product ID,Barcode,Price,Stock,Pull Count\n"
        val rows = items.joinToString("\n") { item ->
            listOf(
                csvQuoted(item.name),
                csvQuoted(item.productType.orEmpty()),
                csvQuoted(item.productId.toString()),
                csvQuoted(item.barcode.orEmpty()),
                csvQuoted(item.priceLabel),
                csvQuoted(item.stockLabel),
                item.pullCount.toString(),
            ).joinToString(",")
        }
        return header + rows + if (rows.isEmpty()) "" else "\n"
    }

    fun writeCsvFile(cacheDir: File, listName: String, items: List<InventoryListItem>): File? {
        return runCatching {
            val safeName = sanitizedFileName(listName)
            val file = File(cacheDir, "${safeName}_${System.currentTimeMillis()}.csv")
            file.writeText(buildCsv(items))
            file
        }.getOrNull()
    }

    fun sanitizedFileName(name: String): String {
        val noSpaces = name.replace(' ', '_')
        val cleaned = noSpaces.filter { it.isLetterOrDigit() || it == '-' || it == '_' }
        return cleaned.ifEmpty { "list" }
    }

    private fun csvQuoted(value: String): String {
        return "\"${value.replace("\"", "\"\"")}\""
    }
}

object ListQueryLogic {
    fun resultListName(sourceName: String, customName: String): String {
        val trimmed = customName.trim()
        return trimmed.ifEmpty { "$sourceName-BQ" }
    }

    fun setItems(items: List<InventoryListItem>, forListId: String, lists: List<com.cloudstore.lister.data.InventoryNamedList>): List<com.cloudstore.lister.data.InventoryNamedList> {
        val index = lists.indexOfFirst { it.id == forListId }
        if (index < 0) return lists
        return lists.toMutableList().also { it[index] = it[index].copy(items = items) }
    }
}
