package com.cloudstore.pos.ui

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
    if (trimmed.isEmpty() || trimmed == ".") return null
    return trimmed.toDoubleOrNull()
}

internal fun appendCashDigit(current: String, digit: Char): String {
    if (digit == '.') {
        if (current.contains('.')) return current
        return if (current.isEmpty()) "0." else "$current."
    }
    if (current.contains('.')) {
        val frac = current.substringAfter('.')
        if (frac.length >= 2) return current
    } else if (current.length >= 7) {
        return current
    }
    return current + digit
}

/** When [maxAmount] is set (credit-only card), reject digits that would exceed the balance due. */
internal fun appendCashDigitLimited(current: String, digit: Char, maxAmount: Double?): String {
    val next = appendCashDigit(current, digit)
    if (maxAmount == null || maxAmount <= 0.005) return next
    val parsed = parseCashTendered(next) ?: return next
    if (parsed > maxAmount + 0.005) return current
    return next
}
