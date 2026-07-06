package com.cloudstore.lister.data

import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import java.net.URLDecoder

/** In-memory cashier session cookie for lister API calls (mirrors android-pos MemoryCookieJar). */
class ListerCookieJar : CookieJar {
    private val store = mutableMapOf<String, MutableList<Cookie>>()
    var manualSessionId: String? = null

    fun pinSessionId(rawValue: String?) {
        val trimmed = rawValue?.trim().orEmpty()
        if (trimmed.isEmpty()) {
            manualSessionId = null
            return
        }
        manualSessionId = decodeCookieValue(trimmed)
    }

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        if (cookies.isEmpty()) return
        val bucket = store.getOrPut(url.host) { mutableListOf() }
        val now = System.currentTimeMillis()
        cookies.forEach { cookie ->
            if (cookie.name == "cashier_session") {
                manualSessionId = if (cookie.expiresAt != 0L && cookie.expiresAt <= now) {
                    null
                } else {
                    cookie.value
                }
            }
            bucket.removeAll { it.name == cookie.name }
            if (cookie.expiresAt == 0L || cookie.expiresAt > now) bucket.add(cookie)
        }
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val now = System.currentTimeMillis()
        val bucket = store[url.host].orEmpty().filter { it.expiresAt == 0L || it.expiresAt > now }
        val merged = bucket.filter { it.name != "cashier_session" }.toMutableList()
        resolveSessionCookie(url, bucket)?.let { merged.add(it) }
        return merged
    }

    fun hasCashierSession(): Boolean {
        if (!manualSessionId.isNullOrBlank()) return true
        return store.values.flatten().any { it.name == "cashier_session" }
    }

    fun clearHost(host: String) {
        store.remove(host)
        manualSessionId = null
    }

    private fun resolveSessionCookie(url: HttpUrl, bucket: List<Cookie>): Cookie? {
        val pinned = manualSessionId
        if (!pinned.isNullOrBlank()) {
            return buildSessionCookie(url, pinned)
        }
        return bucket.firstOrNull { it.name == "cashier_session" && it.matches(url) }
    }

    private fun buildSessionCookie(url: HttpUrl, value: String): Cookie =
        Cookie.Builder()
            .name("cashier_session")
            .value(value)
            .domain(url.host)
            .path("/")
            .httpOnly()
            .apply { if (url.isHttps) secure() }
            .build()

    private fun decodeCookieValue(value: String): String =
        runCatching { URLDecoder.decode(value, Charsets.UTF_8.name()) }.getOrDefault(value)
}
