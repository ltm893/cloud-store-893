package com.cloudstore.pos.data

import android.webkit.CookieManager
import okhttp3.Cookie
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** Copy cookies set by a WebView OIDC flow into [MemoryCookieJar] for Retrofit API calls. */
object WebViewCookieSync {
    fun sync(baseUrl: String, cookieJar: MemoryCookieJar) {
        CookieManager.getInstance().flush()
        val httpUrl = baseUrl.trim().let { url ->
            val normalized = if (url.endsWith("/")) url else "$url/"
            normalized.toHttpUrlOrNull()
        } ?: return
        val cookieHeader = CookieManager.getInstance().getCookie(httpUrl.toString()) ?: return
        for (part in cookieHeader.split(';')) {
            val trimmed = part.trim()
            if (trimmed.isEmpty()) continue
            Cookie.parse(httpUrl, trimmed)?.let { cookie ->
                cookieJar.saveFromResponse(httpUrl, listOf(cookie))
            }
        }
    }
}
