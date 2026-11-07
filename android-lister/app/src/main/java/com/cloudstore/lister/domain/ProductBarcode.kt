package com.cloudstore.lister.domain

/**
 * Chooses the barcode the product catalog can match.
 *
 * A bottle often carries a UPC and a longer Code 128. The camera reports
 * whichever it decodes first. A 13-digit EAN that starts with 0 is a UPC-A
 * (`0080432500170` is UPC `080432500170`).
 */
object ProductBarcode {
    enum class Symbology(val label: String, val retail: Boolean) {
        UPC_A("UPC-A", true),
        UPC_E("UPC-E", true),
        EAN_13("EAN-13", true),
        EAN_8("EAN-8", true),
        CODE_128("Code 128", false),
        PDF417("PDF417", false),
        QR("QR", false),
        OTHER("Other", false)
    }

    data class Read(val symbology: Symbology, val value: String)

    data class Selection(
        val symbology: Symbology,
        val value: String,
        val ignored: List<Read>
    ) {
        fun logMessage(): String {
            val skipped = ignored.joinToString(", ") { "${it.value} (${it.symbology.label})" }
            val extra = if (skipped.isEmpty()) "" else "; ignored $skipped"
            return "Barcode scanned: $value (${symbology.label})$extra"
        }
    }

    enum class Decision { Accept, Wait }

    /** How long a Code 128 (or other non-UPC) is held so a UPC in the next frames can win. */
    const val NON_RETAIL_HOLD_MS = 450L

    fun preferred(reads: List<Read>): Selection? {
        val usable = reads.mapNotNull { read ->
            val value = read.value.trim()
            if (value.isEmpty()) null else read.copy(value = value)
        }
        val index = usable.indices.minByOrNull { rank(usable[it].symbology) } ?: return null
        val best = usable[index]
        val value = catalogValue(best.symbology, best.value)
        val reported = if (best.symbology == Symbology.EAN_13 && value.length == 12) {
            Symbology.UPC_A
        } else {
            best.symbology
        }
        val ignored = usable.filterIndexed { offset, _ -> offset != index }
        return Selection(reported, value, ignored)
    }

    /** A retail code is used immediately. Anything else waits [NON_RETAIL_HOLD_MS] for a UPC to appear. */
    fun decide(symbology: Symbology, pendingSinceMs: Long?, nowMs: Long): Decision {
        if (symbology.retail) return Decision.Accept
        val pending = pendingSinceMs ?: return Decision.Wait
        return if (nowMs - pending >= NON_RETAIL_HOLD_MS) Decision.Accept else Decision.Wait
    }

    fun catalogValue(symbology: Symbology, raw: String): String {
        var text = raw.trim()
        if (text.startsWith("'")) text = text.drop(1)
        if (symbology == Symbology.EAN_13 || symbology == Symbology.UPC_A) {
            val digits = text.filter { it.isDigit() }
            if (symbology == Symbology.EAN_13 && digits.length == 13 && digits.startsWith("0")) {
                return digits.drop(1)
            }
            if (digits.isNotEmpty()) return digits
        }
        return text
    }

    private fun rank(symbology: Symbology): Int = when (symbology) {
        Symbology.UPC_A -> 0
        Symbology.EAN_13 -> 1
        Symbology.UPC_E -> 2
        Symbology.EAN_8 -> 3
        Symbology.CODE_128 -> 4
        Symbology.PDF417 -> 5
        Symbology.QR -> 6
        Symbology.OTHER -> 7
    }
}
