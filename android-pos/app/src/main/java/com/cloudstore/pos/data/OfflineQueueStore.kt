package com.cloudstore.pos.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class PendingCheckout(
    val paymentMethod: String,
    val customerId: Int? = null,
    val createdAtMs: Long,
)

class OfflineQueueStore(context: Context) {
    private val prefs = context.getSharedPreferences("pos_offline_queue", Context.MODE_PRIVATE)
    private val key = "pending_checkouts"

    fun all(): List<PendingCheckout> {
        val raw = prefs.getString(key, "[]") ?: "[]"
        val arr = JSONArray(raw)
        val result = mutableListOf<PendingCheckout>()
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            val customerId = when {
                !obj.has("customerId") || obj.isNull("customerId") -> null
                else -> obj.getInt("customerId")
            }
            result.add(
                PendingCheckout(
                    paymentMethod = obj.getString("paymentMethod"),
                    customerId = customerId,
                    createdAtMs = obj.getLong("createdAtMs"),
                )
            )
        }
        return result
    }

    fun enqueue(paymentMethod: String, customerId: Int?) {
        val current = all().toMutableList()
        current.add(PendingCheckout(paymentMethod = paymentMethod, customerId = customerId, createdAtMs = System.currentTimeMillis()))
        save(current)
    }

    fun replace(items: List<PendingCheckout>) {
        save(items)
    }

    private fun save(items: List<PendingCheckout>) {
        val arr = JSONArray()
        items.forEach { item ->
            arr.put(
                JSONObject().apply {
                    put("paymentMethod", item.paymentMethod)
                    if (item.customerId != null) {
                        put("customerId", item.customerId)
                    } else {
                        put("customerId", JSONObject.NULL)
                    }
                    put("createdAtMs", item.createdAtMs)
                }
            )
        }
        prefs.edit().putString(key, arr.toString()).apply()
    }
}
