package com.cloudstore.pos.data

import android.content.Context

class CashierUserStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun get(): String? = prefs.getString(KEY_EMAIL, null)?.trim()?.takeIf { it.isNotEmpty() }

    fun save(email: String) {
        val trimmed = email.trim()
        if (trimmed.isEmpty()) return
        prefs.edit().putString(KEY_EMAIL, trimmed).apply()
    }

    fun clear() {
        prefs.edit().remove(KEY_EMAIL).apply()
    }

    companion object {
        private const val PREFS_NAME = "pos_cashier_user"
        private const val KEY_EMAIL = "email"
    }
}
