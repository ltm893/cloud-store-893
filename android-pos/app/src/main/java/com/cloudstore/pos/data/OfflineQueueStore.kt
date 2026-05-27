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
    val payments: List<CheckoutPayment>? = null,
    val checkoutTotal: Double? = null,
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
            val payments: List<CheckoutPayment>? = when {
                !obj.has("payments") || obj.isNull("payments") -> null
                else -> {
                    val paymentArr = obj.getJSONArray("payments")
                    buildList<CheckoutPayment> {
                        for (j in 0 until paymentArr.length()) {
                            val payment = paymentArr.getJSONObject(j)
                            add(
                                CheckoutPayment(
                                    method = payment.getString("method"),
                                    amount = payment.getDouble("amount"),
                                    tenderedAmount = when {
                                        !payment.has("tenderedAmount") || payment.isNull("tenderedAmount") -> null
                                        else -> payment.getDouble("tenderedAmount")
                                    },
                                    changeGiven = when {
                                        !payment.has("changeGiven") || payment.isNull("changeGiven") -> null
                                        else -> payment.getDouble("changeGiven")
                                    },
                                ),
                            )
                        }
                    }
                }
            }
            val checkoutTotal = when {
                !obj.has("checkoutTotal") || obj.isNull("checkoutTotal") -> null
                else -> obj.getDouble("checkoutTotal")
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
                    payments = payments,
                    checkoutTotal = checkoutTotal,
                    customerId = customerId,
                    createdAtMs = obj.getLong("createdAtMs"),
                    cartLines = lines,
                ),
            )
        }
        return result
    }

    fun enqueue(
        paymentMethod: String,
        customerId: Int?,
        cartLines: List<QueuedCartLine>,
        payments: List<CheckoutPayment>? = null,
        checkoutTotal: Double? = null,
    ) {
        val current = all().toMutableList()
        current.add(
            PendingCheckout(
                paymentMethod = paymentMethod,
                payments = payments,
                checkoutTotal = checkoutTotal,
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
            val paymentArr = JSONArray()
            item.payments?.forEach { payment ->
                paymentArr.put(
                    JSONObject().apply {
                        put("method", payment.method)
                        put("amount", payment.amount)
                        if (payment.tenderedAmount != null) {
                            put("tenderedAmount", payment.tenderedAmount)
                        } else {
                            put("tenderedAmount", JSONObject.NULL)
                        }
                        if (payment.changeGiven != null) {
                            put("changeGiven", payment.changeGiven)
                        } else {
                            put("changeGiven", JSONObject.NULL)
                        }
                    },
                )
            }
            arr.put(
                JSONObject().apply {
                    put("paymentMethod", item.paymentMethod)
                    if (item.payments != null) {
                        put("payments", paymentArr)
                    } else {
                        put("payments", JSONObject.NULL)
                    }
                    if (item.checkoutTotal != null) {
                        put("checkoutTotal", item.checkoutTotal)
                    } else {
                        put("checkoutTotal", JSONObject.NULL)
                    }
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
