package com.cloudstore.lister.ui.auth

import android.view.View
import android.webkit.WebSettings
import android.webkit.WebView
import androidx.core.view.ViewCompat

/** Oracle IdP pages need DOM storage; match android-pos WebView defaults. */
internal const val ListerWebViewTextZoomPercent = 140

internal fun WebSettings.configureForListerWebView(
    textZoomPercent: Int = ListerWebViewTextZoomPercent,
) {
    javaScriptEnabled = true
    domStorageEnabled = true
    loadWithOverviewMode = true
    useWideViewPort = true
    textZoom = textZoomPercent
    // Some IdPs render a blank page when the WebView user-agent includes "; wv)".
    userAgentString = userAgentString
        ?.replace("; wv)", ")")
        ?: userAgentString
}

internal fun WebView.configureForListerAutofill() {
    ViewCompat.setImportantForAutofill(this, View.IMPORTANT_FOR_AUTOFILL_YES)
}
