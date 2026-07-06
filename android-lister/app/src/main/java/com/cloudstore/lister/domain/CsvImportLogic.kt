package com.cloudstore.lister.domain

import com.cloudstore.lister.data.InventoryListItem
import com.cloudstore.lister.data.InventoryNamedList

sealed class CsvImportError(message: String) : Exception(message) {
    data object EmptyFile : CsvImportError("The file is empty.")
    data object MissingProductIdColumn : CsvImportError("Select which column contains Product ID.")
    data object NoValidRows : CsvImportError("No rows with a valid Product ID were found.")
}

enum class CsvImportableField(val label: String) {
    ProductId("Product ID"),
    Barcode("Barcode"),
    Name("Name"),
    ProductType("Type"),
    Manufacturer("Manufacturer"),
    Price("Price"),
    Stock("Stock"),
    PullCount("Pull Count"),
    ;

    companion object {
        val optionalFields: List<CsvImportableField> = entries.filter { it != ProductId }
    }
}

data class ParsedCsv(
    val headers: List<String>,
    val rows: List<List<String>>,
)

data class CsvFieldMapping(
    var productIdColumn: String? = null,
    val enabledFields: MutableSet<CsvImportableField> = mutableSetOf(),
    val columnByField: MutableMap<CsvImportableField, String> = mutableMapOf(),
)

object CsvImportLogic {
    fun parseCsv(content: String): ParsedCsv? {
        val lines = nonEmptyLines(content)
        if (lines.isEmpty()) return null
        val firstFields = parseCsvLine(lines.first())
        return if (looksLikeHeader(firstFields)) {
            ParsedCsv(
                headers = firstFields,
                rows = lines.drop(1).map(::parseCsvLine),
            )
        } else {
            val width = firstFields.size
            val headers = (0 until width).map { "Column ${it + 1}" }
            ParsedCsv(headers = headers, rows = lines.map(::parseCsvLine))
        }
    }

    fun parseCsvLine(line: String): List<String> {
        val fields = mutableListOf<String>()
        val current = StringBuilder()
        var inQuotes = false
        for (char in line) {
            when {
                char == '"' -> inQuotes = !inQuotes
                char == ',' && !inQuotes -> {
                    fields.add(current.toString().trim())
                    current.clear()
                }
                else -> current.append(char)
            }
        }
        fields.add(current.toString().trim())
        return fields
    }

    fun suggestedMapping(parsed: ParsedCsv): CsvFieldMapping {
        val mapping = CsvFieldMapping(productIdColumn = guessProductIdColumn(parsed.headers))
        CsvImportableField.optionalFields.forEach { field ->
            guessColumn(field, parsed.headers)?.let { column ->
                mapping.enabledFields.add(field)
                mapping.columnByField[field] = column
            }
        }
        return mapping
    }

    fun buildItems(parsed: ParsedCsv, mapping: CsvFieldMapping): List<InventoryListItem> {
        val productIdColumn = mapping.productIdColumn
            ?: throw CsvImportError.MissingProductIdColumn
        val productIdIndex = parsed.headers.indexOf(productIdColumn)
        if (productIdIndex < 0) throw CsvImportError.MissingProductIdColumn

        val items = mutableListOf<InventoryListItem>()
        for (row in parsed.rows) {
            if (productIdIndex >= row.size) continue
            val productId = parseProductId(row[productIdIndex]) ?: continue
            val pullCount = maxOf(1, intValue(CsvImportableField.PullCount, row, parsed, mapping) ?: 1)
            val stockLabel = stringValue(CsvImportableField.Stock, row, parsed, mapping) ?: "—"
            val stockEmphasis = stockLabel.contains("out", ignoreCase = true)
            items.add(
                InventoryListItem(
                    productId = productId,
                    barcode = stringValue(CsvImportableField.Barcode, row, parsed, mapping),
                    name = stringValue(CsvImportableField.Name, row, parsed, mapping).orEmpty(),
                    productType = stringValue(CsvImportableField.ProductType, row, parsed, mapping),
                    manufacturer = stringValue(CsvImportableField.Manufacturer, row, parsed, mapping),
                    priceLabel = stringValue(CsvImportableField.Price, row, parsed, mapping) ?: "—",
                    stockLabel = stockLabel,
                    stockEmphasis = stockEmphasis,
                    pullCount = pullCount,
                ),
            )
        }
        if (items.isEmpty()) throw CsvImportError.NoValidRows
        return items
    }

    fun applyImport(
        items: List<InventoryListItem>,
        toListId: String,
        lists: List<InventoryNamedList>,
    ): List<InventoryNamedList> {
        var updated = lists
        for (item in items) {
            updated = ListStoreLogic.addItem(item, toListId, updated)
        }
        return updated
    }

    fun guessColumn(field: CsvImportableField, headers: List<String>): String? {
        val candidates = when (field) {
            CsvImportableField.ProductId -> return guessProductIdColumn(headers)
            CsvImportableField.Barcode -> listOf("barcode", "upc", "ean", "sku")
            CsvImportableField.Name -> listOf("name", "product name", "description")
            CsvImportableField.ProductType -> listOf("type", "product type", "category")
            CsvImportableField.Manufacturer -> listOf("manufacturer", "mfr", "brand")
            CsvImportableField.Price -> listOf("price", "regular price", "sale price")
            CsvImportableField.Stock -> listOf("stock", "qty", "quantity", "on hand")
            CsvImportableField.PullCount -> listOf("pull count", "pull", "count")
        }
        return headers.firstOrNull { header ->
            val normalized = normalizeHeader(header)
            candidates.any { normalized == it }
        }
    }

    private fun nonEmptyLines(content: String): List<String> =
        content.lines().map { it.trim() }.filter { it.isNotEmpty() }

    private fun looksLikeHeader(fields: List<String>): Boolean {
        val normalized = fields.map(::normalizeHeader)
        if (normalized.any { it.contains("product") && it.contains("id") }) return true
        val keywords = listOf("name", "barcode", "type", "manufacturer", "price", "stock", "pull")
        return normalized.any { field -> keywords.any { field.contains(it) } }
    }

    private fun guessProductIdColumn(headers: List<String>): String? =
        headers.firstOrNull { header ->
            val normalized = normalizeHeader(header)
            normalized == "productid" ||
                normalized == "product id" ||
                normalized == "id" ||
                (normalized.contains("product") && normalized.contains("id"))
        }

    private fun normalizeHeader(header: String): String =
        header.lowercase().replace('_', ' ').replace('-', ' ').trim()

    private fun parseProductId(raw: String): Int? {
        val trimmed = raw.trim()
        trimmed.toIntOrNull()?.let { return it }
        val digits = trimmed.filter { it.isDigit() }
        return digits.toIntOrNull()
    }

    private fun stringValue(
        field: CsvImportableField,
        row: List<String>,
        parsed: ParsedCsv,
        mapping: CsvFieldMapping,
    ): String? {
        if (!mapping.enabledFields.contains(field)) return null
        val column = mapping.columnByField[field] ?: return null
        val index = parsed.headers.indexOf(column)
        if (index < 0 || index >= row.size) return null
        val value = row[index].trim()
        return value.ifEmpty { null }
    }

    private fun intValue(
        field: CsvImportableField,
        row: List<String>,
        parsed: ParsedCsv,
        mapping: CsvFieldMapping,
    ): Int? = stringValue(field, row, parsed, mapping)?.filter { it.isDigit() }?.toIntOrNull()
}
