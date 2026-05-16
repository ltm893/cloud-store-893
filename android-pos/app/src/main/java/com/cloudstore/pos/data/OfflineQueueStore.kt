package com.cloudstore.pos.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class QueuedCartLine(
    val productId: Int,
    val quantity: Int,
)

data class PendingCheckout(
    val paymentMethod: String,
    val customerId: Int? = null,
    val createdAtMs: Long,
    val cartLines: List<QueuedCartLine> = emptyList(),
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
            val lines = mutableListOf<QueuedCartLine>()
            if (obj.has("cartLines") && !obj.isNull("cartLines")) {
                val lineArr = obj.getJSONArray("cartLines")
                for (j in 0 until lineArr.length()) {
                    val line = lineArr.getJSONObject(j)
                    lines.add(
                        QueuedCartLine(
                            productId = line.getInt("productId"),
                            quantity = line.getInt("quantity"),
                        ),
                    )
                }
            }
            result.add(
                PendingCheckout(
                    paymentMethod = obj.getString("paymentMethod"),
                    customerId = customerId,
                    createdAtMs = obj.getLong("createdAtMs"),
                    cartLines = lines,
                ),
            )
        }
        return result
    }

    fun enqueue(paymentMethod: String, customerId: Int?, cartLines: List<QueuedCartLine>) {
        val current = all().toMutableList()
        current.add(
            PendingCheckout(
                paymentMethod = paymentMethod,
                customerId = customerId,
                createdAtMs = System.currentTimeMillis(),
                cartLines = cartLines,
            ),
        )
        save(current)
    }

    fun replace(items: List<PendingCheckout>) {
        save(items)
    }

    fun clear() {
        save(emptyList())
    }

    private fun save(items: List<PendingCheckout>) {
        val arr = JSONArray()
        items.forEach { item ->
            val lineArr = JSONArray()
            item.cartLines.forEach { line ->
                lineArr.put(
                    JSONObject().apply {
                        put("productId", line.productId)
                        put("quantity", line.quantity)
                    },
                )
            }
            arr.put(
                JSONObject().apply {
                    put("paymentMethod", item.paymentMethod)
                    if (item.customerId != null) {
                        put("customerId", item.customerId)
                    } else {
                        put("customerId", JSONObject.NULL)
                    }
                    put("createdAtMs", item.createdAtMs)
                    put("cartLines", lineArr)
                },
            )
        }
        prefs.edit().putString(key, arr.toString()).apply()
    }
}
