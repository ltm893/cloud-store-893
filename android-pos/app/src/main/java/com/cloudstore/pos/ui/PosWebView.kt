package com.cloudstore.pos.ui

import android.webkit.WebSettings

/**
 * WebView zoom for Oracle sign-in / admin (percent; 100 = default).
 *
 * Samsung's keyboard **Size and transparency** setting often does not apply in
 * landscape WebView — use this to enlarge the IdP page (fields + labels) instead.
 */
internal const val PosWebViewTextZoomPercent = 140

internal fun WebSettings.configureForPosWebView(
    textZoomPercent: Int = PosWebViewTextZoomPercent,
) {
    javaScriptEnabled = true
    domStorageEnabled = true
    loadWithOverviewMode = true
    useWideViewPort = true
    textZoom = textZoomPercent
}
