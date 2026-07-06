package com.cloudstore.lister.domain

object ApiConfigLogic {
    fun normalizeBaseUrl(raw: String): String {
        val trimmed = raw.trim()
        return if (trimmed.endsWith("/")) trimmed else "$trimmed/"
    }

    fun oidcLoginUrl(baseUrl: String, registerId: String, freshLogin: Boolean = false): String {
        val base = normalizeBaseUrl(baseUrl).trimEnd('/')
        val params = buildList {
            add("client_kind=lister")
            add("register_id=${java.net.URLEncoder.encode(registerId, Charsets.UTF_8.name())}")
            if (freshLogin) add("prompt=login")
        }
        return "$base/oauth/login?${params.joinToString("&")}"
    }

    fun inventoryLookupUrl(baseUrl: String, query: String): String {
        val base = normalizeBaseUrl(baseUrl).trimEnd('/')
        val q = java.net.URLEncoder.encode(query, Charsets.UTF_8.name())
        return "$base/api/inventory/lookup?q=$q"
    }
}
