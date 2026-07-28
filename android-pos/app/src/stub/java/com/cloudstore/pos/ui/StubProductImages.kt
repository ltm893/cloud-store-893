package com.cloudstore.pos.ui

/** Stub flavor: maps dance-shop catalog IDs to local drawables. */
object StubProductImages {
    fun drawableNameFor(productId: Int): String? = when (productId) {
        1 -> "product_ballet_leotard"
        2 -> "product_tutu_skirt"
        3 -> "product_jazz_shoes"
        4 -> "product_ballet_slippers"
        5 -> "product_character_skirt"
        6 -> "product_dance_tights"
        7 -> "product_competition_dress"
        8 -> "product_bun_net"
        9 -> "product_warmup_booties"
        10 -> "product_gift_card"
        else -> null
    }
}
