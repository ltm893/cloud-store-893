package com.cloudstore.pos.data

import android.webkit.CookieManager
import okhttp3.Cookie
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** Copy cookies set by a WebView OIDC flow into [MemoryCookieJar] for Retrofit API calls. */
object WebViewCookieSync {
    fun sync(baseUrl: String, cookieJar: MemoryCookieJar) {
        CookieManager.getInstance().flush()
        val root = baseUrl.trim().trimEnd('/')
        val urls = listOf(
            "$root/",
            "$root/?approval=pending",
            "$root/oauth/callback",
        )
        for (url in urls) {
            val httpUrl = url.toHttpUrlOrNull() ?: continue
            val cookieHeader = CookieManager.getInstance().getCookie(httpUrl.toString()) ?: continue
            ingestCookieHeader(httpUrl, cookieHeader, cookieJar)
        }
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
