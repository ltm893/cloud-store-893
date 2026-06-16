package com.cloudstore.pos.data

import android.webkit.CookieManager
import okhttp3.Cookie
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** Clear IdP / WebView cookies so the next sign-in requires credentials. */
fun clearIdpWebViewCookies() {
    val manager = CookieManager.getInstance()
    manager.removeAllCookies(null)
    manager.flush()
}

/** Copy cookies set by a WebView OIDC flow into [MemoryCookieJar] for Retrofit API calls. */
object WebViewCookieSync {
    fun sync(baseUrl: String, cookieJar: MemoryCookieJar) {
        CookieManager.getInstance().flush()
        val root = baseUrl.trim().trimEnd('/')
        val urls = listOf(
            "$root/",
            "$root/?approval=pending",
            "$root/?awaiting_till=1",
            "$root/?cashier_resume=1",
            "$root/oauth/callback",
        )
        for (url in urls) {
            val httpUrl = url.toHttpUrlOrNull() ?: continue
            val cookieHeader = CookieManager.getInstance().getCookie(httpUrl.toString()) ?: continue
            ingestCookieHeader(httpUrl, cookieHeader, cookieJar)
        }
    }

    /** Pin opening-till cookie from WebView; clears stale pending so session probe shows till count. */
    fun pinAwaitingTillFromWebView(baseUrl: String, cookieJar: MemoryCookieJar): Boolean {
        CookieManager.getInstance().flush()
        val root = baseUrl.trim().trimEnd('/')
        val urls = listOf(
            "$root/",
            "$root/?awaiting_till=1",
            "$root/oauth/callback",
            "$root/oauth/login",
        )
        for (url in urls) {
            val httpUrl = url.toHttpUrlOrNull() ?: continue
            val cookieHeader = CookieManager.getInstance().getCookie(httpUrl.toString()) ?: continue
            for (part in cookieHeader.split(';')) {
                val trimmed = part.trim()
                if (trimmed.isEmpty() || !trimmed.startsWith("cashier_awaiting_till=")) continue
                val cookie = Cookie.parse(httpUrl, trimmed) ?: continue
                cookieJar.clearPinnedPendingToken()
                cookieJar.saveFromResponse(httpUrl, listOf(cookie))
                return true
            }
        }
        return false
    }

    private fun ingestCookieHeader(
        httpUrl: okhttp3.HttpUrl,
        cookieHeader: String,
        cookieJar: MemoryCookieJar,
    ) {
        for (part in cookieHeader.split(';')) {
            val trimmed = part.trim()
            if (trimmed.isEmpty()) continue
            Cookie.parse(httpUrl, trimmed)?.let { cookie ->
                cookieJar.saveFromResponse(httpUrl, listOf(cookie))
            }
        }
    }
}
