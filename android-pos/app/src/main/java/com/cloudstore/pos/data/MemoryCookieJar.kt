package com.cloudstore.pos.data

import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl

/**
 * In-memory cookie jar for POS API calls.
 * Prefer over [okhttp3.JavaNetCookieJar] on Android — Java's CookieManager often
 * drops HttpOnly session cookies for LAN IP hosts.
 */
class MemoryCookieJar : CookieJar {
    private val store = mutableMapOf<String, MutableList<Cookie>>()

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        if (cookies.isEmpty()) return
        val hostKey = url.host
        val bucket = store.getOrPut(hostKey) { mutableListOf() }
        val now = System.currentTimeMillis()
        for (cookie in cookies) {
            bucket.removeAll { it.name == cookie.name }
            if (cookie.expiresAt != 0L && cookie.expiresAt <= now) continue
            bucket.add(cookie)
        }
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val hostKey = url.host
        val bucket = store[hostKey] ?: return emptyList()
        val now = System.currentTimeMillis()
        val valid = bucket.filter { it.matches(url) && (it.expiresAt == 0L || it.expiresAt > now) }
        store[hostKey] = valid.toMutableList()
        return valid
    }
}
