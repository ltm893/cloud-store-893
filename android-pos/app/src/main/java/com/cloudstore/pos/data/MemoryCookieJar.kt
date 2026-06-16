package com.cloudstore.pos.data

import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl

private val AUTH_COOKIE_NAMES = setOf(
    "cashier_session",
    "cashier_pending",
    "cashier_awaiting_till",
)

/**
 * In-memory cookie jar for POS API calls.
 * Prefer over [okhttp3.JavaNetCookieJar] on Android — Java's CookieManager often
 * drops HttpOnly session cookies for LAN IP hosts.
 *
 * Pinned tokens survive [loadForRequest] when bucket sync is incomplete; bucket
 * cookies are used as fallback when pins are unset.
 */
class MemoryCookieJar : CookieJar {
    private val store = mutableMapOf<String, MutableList<Cookie>>()

    var pinnedPendingToken: String? = null
        set(value) {
            field = value?.trim()?.takeIf { it.isNotEmpty() }
        }

    var pinnedAwaitingTillToken: String? = null
        set(value) {
            field = value?.trim()?.takeIf { it.isNotEmpty() }
        }

    var manualSessionId: String? = null
        set(value) {
            field = value?.trim()?.takeIf { it.isNotEmpty() }
        }

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        if (cookies.isEmpty()) return
        val hostKey = url.host
        val bucket = store.getOrPut(hostKey) { mutableListOf() }
        val now = System.currentTimeMillis()
        for (cookie in cookies) {
            when (cookie.name) {
                "cashier_pending" -> {
                    if (cookie.expiresAt != 0L && cookie.expiresAt <= now) {
                        if (pinnedPendingToken == cookie.value) pinnedPendingToken = null
                    } else {
                        pinnedAwaitingTillToken = null
                        pinnedPendingToken = cookie.value
                    }
                }
                "cashier_awaiting_till" -> {
                    if (cookie.expiresAt != 0L && cookie.expiresAt <= now) {
                        if (pinnedAwaitingTillToken == cookie.value) pinnedAwaitingTillToken = null
                    } else {
                        pinnedPendingToken = null
                        pinnedAwaitingTillToken = cookie.value
                    }
                }
                "cashier_session" -> {
                    if (cookie.expiresAt != 0L && cookie.expiresAt <= now) {
                        manualSessionId = null
                    } else {
                        manualSessionId = cookie.value
                        pinnedPendingToken = null
                        pinnedAwaitingTillToken = null
                    }
                }
            }
            bucket.removeAll { it.name == cookie.name }
            if (cookie.expiresAt != 0L && cookie.expiresAt <= now) continue
            bucket.add(cookie)
        }
    }

    fun clearPinnedPendingToken() {
        pinnedPendingToken = null
        val now = System.currentTimeMillis()
        for ((host, bucket) in store) {
            bucket.removeAll { it.name == "cashier_pending" }
            store[host] = bucket.filter { it.expiresAt == 0L || it.expiresAt > now }.toMutableList()
        }
    }

    fun clearPinnedAwaitingTillToken() {
        pinnedAwaitingTillToken = null
        val now = System.currentTimeMillis()
        for ((host, bucket) in store) {
            bucket.removeAll { it.name == "cashier_awaiting_till" }
            store[host] = bucket.filter { it.expiresAt == 0L || it.expiresAt > now }.toMutableList()
        }
    }

    fun clearHost(host: String) {
        store.remove(host)
        pinnedPendingToken = null
        pinnedAwaitingTillToken = null
        manualSessionId = null
    }

    fun clearAll() {
        store.clear()
        pinnedPendingToken = null
        pinnedAwaitingTillToken = null
        manualSessionId = null
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val hostKey = url.host
        val bucket = store[hostKey] ?: mutableListOf()
        val now = System.currentTimeMillis()
        val valid = bucket.filter { it.matches(url) && (it.expiresAt == 0L || it.expiresAt > now) }
        store[hostKey] = valid.toMutableList()

        val merged = valid.filter { it.name !in AUTH_COOKIE_NAMES }.toMutableList()

        resolveAuthCookie(url, valid, "cashier_awaiting_till", pinnedAwaitingTillToken)?.let {
            merged.add(it)
        }

        if (pinnedAwaitingTillToken == null) {
            resolveAuthCookie(url, valid, "cashier_pending", pinnedPendingToken)?.let {
                merged.add(it)
            }
        }

        resolveAuthCookie(url, valid, "cashier_session", manualSessionId)?.let {
            merged.add(it)
        }

        return merged
    }

    private fun resolveAuthCookie(
        url: HttpUrl,
        bucket: List<Cookie>,
        name: String,
        pinnedValue: String?,
    ): Cookie? {
        if (!pinnedValue.isNullOrBlank()) {
            return buildCookie(url, name, pinnedValue)
        }
        return bucket.firstOrNull { it.name == name }
    }

    private fun buildCookie(url: HttpUrl, name: String, value: String): Cookie =
        Cookie.Builder()
            .name(name)
            .value(value)
            .domain(url.host)
            .path("/")
            .httpOnly()
            .build()
}
