package com.cloudstore.pos.ui

import android.view.View
import android.webkit.WebSettings
import android.webkit.WebView
import androidx.core.view.ViewCompat

/**
 * WebView zoom for Oracle sign-in / admin (percent; 100 = default).
 *
 * Samsung's keyboard **Size and transparency** setting often does not apply in
 * landscape WebView — use this to enlarge the IdP page (fields + labels) instead.
 */
internal const val PosWebViewTextZoomPercent = 140

private val POS_LOGIN_AUTOFILL_JS = """
(function() {
  try {
    var passInputs = document.querySelectorAll('input[type="password"]');
    passInputs.forEach(function(pass) {
      pass.setAttribute('autocomplete', 'current-password');
      if (!pass.getAttribute('name')) pass.setAttribute('name', 'password');
    });
    var userInputs = document.querySelectorAll(
      'input[type="email"], input[type="text"], input[name*="user"], input[name*="User"], input[id*="user"], input[id*="User"]'
    );
    userInputs.forEach(function(user) {
      if (user.type === 'password') return;
      user.setAttribute('autocomplete', 'username');
      user.setAttribute('autocapitalize', 'none');
      if (!user.getAttribute('name')) user.setAttribute('name', 'username');
    });
  } catch (e) {}
})();
""".trimIndent()

internal fun WebSettings.configureForPosWebView(
    textZoomPercent: Int = PosWebViewTextZoomPercent,
) {
    javaScriptEnabled = true
    domStorageEnabled = true
    loadWithOverviewMode = true
    useWideViewPort = true
    textZoom = textZoomPercent
}

/** Let Gboard / Samsung Pass detect and save WebView login fields (API 26+). */
internal fun WebView.configureForPosAutofill() {
    ViewCompat.setImportantForAutofill(this, View.IMPORTANT_FOR_AUTOFILL_YES)
}

/** Tag username/password fields so the system autofill service can offer save & fill. */
internal fun WebView.injectPosLoginAutofillHints() {
    evaluateJavascript(POS_LOGIN_AUTOFILL_JS, null)
}

internal fun shouldInjectPosLoginAutofill(pageUrl: String?, apiBaseUrl: String): Boolean {
    val url = pageUrl?.trim().orEmpty()
    if (url.isEmpty() || url == "about:blank") return false
    val base = apiBaseUrl.trimEnd('/')
    if (!url.startsWith(base)) return true
    return !url.contains("awaiting_till=") &&
        !url.contains("approval=pending") &&
        !url.contains("cashier_resume=")
}
