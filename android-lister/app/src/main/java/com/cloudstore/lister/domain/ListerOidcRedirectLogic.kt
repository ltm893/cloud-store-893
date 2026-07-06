package com.cloudstore.lister.domain

object ListerOidcRedirectLogic {
    /**
     * OIDC complete when the server redirects after callback.
     * Uses `/?lister_signed_in=1` (see lib/oidc-pos.js). No custom app URI scheme.
     */
    fun isOidcComplete(completionUrl: String, apiBaseUrl: String): Boolean {
        if (completionUrl == "about:blank") return false
        val base = apiBaseUrl.trimEnd('/')
        if (!completionUrl.startsWith(base)) return false
        if (completionUrl.contains("lister_signed_in=", ignoreCase = true)) return true
        if (completionUrl.contains("/oauth/", ignoreCase = true)) return false
        return false
    }

    fun syncProbeUrls(baseUrl: String): List<String> {
        val base = baseUrl.trimEnd('/')
        return listOf(
            "$base/",
            "$base/?lister_signed_in=1",
            "$base/oauth/callback",
        )
    }
}
