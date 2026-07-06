package com.cloudstore.lister.domain

object BarcodeNormalizeLogic {
    fun ean13CheckDigit(data12: String): String? {
        val digits = data12.filter { it.isDigit() }
        if (digits.length != 12) return null
        var sum = 0
        digits.forEachIndexed { index, char ->
            val n = char.digitToInt()
            sum += if (index % 2 == 0) n else n * 3
        }
        return ((10 - (sum % 10)) % 10).toString()
    }

    fun lookupCandidates(raw: String): List<String> {
        val value = raw.trim()
        if (value.isEmpty()) return emptyList()
        if (!value.all { it.isDigit() }) return listOf(value)

        val candidates = linkedSetOf<String>()
        fun add(code: String) {
            if (code.isNotEmpty()) candidates.add(code)
        }

        add(value)

        when (value.length) {
            13 -> {
                add(value.take(12))
                if (value.startsWith("0")) add(value.drop(1))
            }
            12 -> {
                ean13CheckDigit(value)?.let { add(value + it) }
                add("0$value")
            }
            11 -> {
                val padded = value.padStart(12, '0')
                ean13CheckDigit(padded)?.let { add(padded + it) }
                add(padded)
            }
        }

        return candidates.toList()
    }
}
