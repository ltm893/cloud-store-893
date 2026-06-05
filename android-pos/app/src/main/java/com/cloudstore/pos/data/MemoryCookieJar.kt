package com.cloudstore.pos.data

import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl

/**
 * In-memory cookie jar for POS API calls.
 * Prefer over [okhttp3.JavaNetCookieJar] on Android — Java's CookieManager often
 * drops HttpOnly session cookies for LAN IP hosts.
 *
 * [pinnedPendingToken] is set from the OIDC redirect URL and must not be overwritten
 * by stale WebView cookie sync while waiting for supervisor approval.
 */
class MemoryCookieJar : CookieJar {
    private val store = mutableMapOf<String, MutableList<Cookie>>()

    /** Pending token from ?request_token= on OIDC redirect; wins over WebView sync. */
    var pinnedPendingToken: String? = null
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
                    } else if (pinnedPendingToken == null) {
                        pinnedPendingToken = cookie.value
                    }
                }
                "cashier_session" -> {
                    if (cookie.expiresAt != 0L && cookie.expiresAt <= now) {
                        manualSessionId = null
                    } else {
                        manualSessionId = cookie.value
                        pinnedPendingToken = null
                    }
                }
            }
            bucket.removeAll { it.name == cookie.name }
            if (cookie.expiresAt != 0L && cookie.expiresAt <= now) continue
            bucket.add(cookie)
        }
    }

    fun clearHost(host: String) {
        store.remove(host)
        pinnedPendingToken = null
        manualSessionId = null
    }

    fun clearAll() {
        store.clear()
        pinnedPendingToken = null
        manualSessionId = null
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val hostKey = url.host
        val bucket = store[hostKey] ?: mutableListOf()
        val now = System.currentTimeMillis()
        val valid = bucket.filter { it.matches(url) && (it.expiresAt == 0L || it.expiresAt > now) }
        store[hostKey] = valid.toMutableList()

        val merged = valid.toMutableList()
        merged.removeAll { it.name == "cashier_pending" }
        pinnedPendingToken?.let { token ->
            merged.add(buildCookie(url, "cashier_pending", token))
        }
        manualSessionId?.let { sessionId ->
            if (merged.none { it.name == "cashier_session" }) {
                merged.add(buildCookie(url, "cashier_session", sessionId))
            }
        }
        return merged
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
