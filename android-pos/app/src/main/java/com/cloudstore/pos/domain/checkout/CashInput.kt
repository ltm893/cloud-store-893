package com.cloudstore.pos.domain.checkout

import com.cloudstore.pos.domain.pricing.roundMoney

internal fun formatCashEntry(amount: Double): String {
    val rounded = roundMoney(amount)
    return if (rounded == rounded.toLong().toDouble()) {
        rounded.toLong().toString()
    } else {
        "%.2f".format(rounded)
    }
}

internal fun parseCashTendered(raw: String): Double? {
    val trimmed = raw.trim()
    if (trimmed.isEmpty() || trimmed == "." || trimmed == "0") return null
    return trimmed.toDoubleOrNull()
}

/** Strip leading zeros while keeping a single keypad value (not a running total). */
internal fun normalizeCashEntryInput(raw: String): String {
    val trimmed = raw.trim()
    if (trimmed.isEmpty()) return "0"
    if (trimmed == ".") return "0."
    if (trimmed.contains('.')) {
        val parts = trimmed.split('.', limit = 2)
        val whole = parts[0].trimStart('0').ifEmpty { "0" }
        val frac = parts.getOrNull(1).orEmpty()
        return if (frac.isEmpty()) "$whole." else "$whole.$frac"
    }
    return trimmed.trimStart('0').ifEmpty { "0" }
}

internal fun appendCashDigit(current: String, digit: Char): String {
    val base = normalizeCashEntryInput(current.ifBlank { "0" })
    if (digit == '.') {
        if (base.contains('.')) return base
        return if (base == "0") "0." else "$base."
    }
    if (base.contains('.')) {
        val frac = base.substringAfter('.')
        if (frac.length >= 2) return base
        return normalizeCashEntryInput("$base$digit")
    }
    if (base == "0") {
        return if (digit == '0') "0" else digit.toString()
    }
    if (base.length >= 7) return base
    return normalizeCashEntryInput(base + digit)
}

/** When [maxAmount] is set (credit-only card), reject digits that would exceed the balance due. */
internal fun appendCashDigitLimited(current: String, digit: Char, maxAmount: Double?): String {
    val next = appendCashDigit(current, digit)
    if (maxAmount == null || maxAmount <= 0.005) return next
    val parsed = parseCashTendered(next) ?: return next
    if (parsed > maxAmount + 0.005) return normalizeCashEntryInput(current.ifBlank { "0" })
    return next
}

internal fun backspaceCashEntry(current: String): String {
    val base = current.trim().ifBlank { "0" }
    if (base.length <= 1) return "0"
    return normalizeCashEntryInput(base.dropLast(1))
}

internal fun displayCashEntry(raw: String): String {
    val trimmed = raw.trim()
    if (trimmed.isEmpty() || trimmed == ".") return "—"
    return "\$${normalizeCashEntryInput(trimmed)}"
}
