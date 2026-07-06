package com.cloudstore.lister.data

import android.webkit.CookieManager
import com.cloudstore.lister.domain.ListerOidcRedirectLogic
import kotlinx.coroutines.delay
import okhttp3.Cookie
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

fun clearIdpWebViewCookies() {
    val manager = CookieManager.getInstance()
    manager.removeAllCookies(null)
    manager.flush()
}

object WebViewCookieSync {
    suspend fun syncWithRetry(baseUrl: String, cookieJar: ListerCookieJar) {
        sync(baseUrl, cookieJar)
        delay(150)
        sync(baseUrl, cookieJar)
        pinCashierSessionFromWebView(baseUrl, cookieJar)
    }

    fun sync(baseUrl: String, cookieJar: ListerCookieJar) {
        CookieManager.getInstance().flush()
        probeUrls(baseUrl).forEach { url ->
            val httpUrl = url.toHttpUrlOrNull() ?: return@forEach
            val header = CookieManager.getInstance().getCookie(httpUrl.toString()) ?: return@forEach
            ingestCookieHeader(httpUrl, header, cookieJar)
        }
    }

    fun pinCashierSessionFromWebView(baseUrl: String, cookieJar: ListerCookieJar): Boolean {
        CookieManager.getInstance().flush()
        for (url in probeUrls(baseUrl)) {
            val httpUrl = url.toHttpUrlOrNull() ?: continue
            val header = CookieManager.getInstance().getCookie(httpUrl.toString()) ?: continue
            val sessionValue = extractCookieValue(header, "cashier_session") ?: continue
            cookieJar.pinSessionId(sessionValue)
            cookieJar.saveFromResponse(httpUrl, listOf(buildSessionCookie(httpUrl, sessionValue)))
            return true
        }
        return false
    }

    private fun probeUrls(baseUrl: String): List<String> {
        val urls = ListerOidcRedirectLogic.syncProbeUrls(baseUrl).toMutableList()
        val base = baseUrl.trimEnd('/')
        urls.add("$base/oauth/login")
        return urls.distinct()
    }

    private fun ingestCookieHeader(
        httpUrl: HttpUrl,
        cookieHeader: String,
        cookieJar: ListerCookieJar,
    ) {
        extractCookieValue(cookieHeader, "cashier_session")?.let { value ->
            cookieJar.pinSessionId(value)
            cookieJar.saveFromResponse(httpUrl, listOf(buildSessionCookie(httpUrl, value)))
        }
        cookieHeader.split(';').forEach { part ->
            val trimmed = part.trim()
            if (trimmed.isEmpty() || trimmed.startsWith("cashier_session=", ignoreCase = true)) return@forEach
            Cookie.parse(httpUrl, trimmed)?.let { cookieJar.saveFromResponse(httpUrl, listOf(it)) }
        }
    }

    private fun extractCookieValue(cookieHeader: String, name: String): String? {
        val prefix = "$name="
        for (part in cookieHeader.split(';')) {
            val trimmed = part.trim()
            if (trimmed.startsWith(prefix, ignoreCase = true)) {
                return trimmed.substring(prefix.length).trim().takeIf { it.isNotEmpty() }
            }
        }
        return null
    }

    private fun buildSessionCookie(httpUrl: HttpUrl, value: String): Cookie =
        Cookie.Builder()
            .name("cashier_session")
            .value(value)
            .domain(httpUrl.host)
            .path("/")
            .httpOnly()
            .apply { if (httpUrl.isHttps) secure() }
            .build()
}
