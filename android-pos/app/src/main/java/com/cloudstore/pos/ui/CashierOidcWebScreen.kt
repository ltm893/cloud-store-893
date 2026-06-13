package com.cloudstore.pos.ui

import android.annotation.SuppressLint
import android.net.Uri
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.cloudstore.pos.data.PocSelfSignedTls

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun CashierOidcWebScreen(
    loginUrl: String,
    apiBaseUrl: String,
    onComplete: (completionUrl: String) -> Unit,
    onCancel: () -> Unit,
) {
    val base = remember(apiBaseUrl) { apiBaseUrl.trimEnd('/') }

    BackHandler(onBack = onCancel)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .navigationBarsPadding(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = onCancel) {
                Text("Cancel")
            }
            Text(
                text = "Store sign-in",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(start = 4.dp),
            )
        }

        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { context ->
                WebView(context).apply {
                    settings.configureForPosWebView()
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                    var finished = false
                    fun finishOidc(url: String) {
                        if (finished || !isCashierOidcComplete(url, base)) return
                        finished = true
                        stopLoading()
                        // Never render the server's web POS HTML in this WebView.
                        loadUrl("about:blank")
                        onComplete(url)
                    }
                    val client = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(
                            view: WebView?,
                            request: WebResourceRequest?,
                        ): Boolean {
                            val url = request?.url?.toString() ?: return false
                            if (isCashierOidcComplete(url, base)) {
                                finishOidc(url)
                                return true
                            }
                            return false
                        }

                        @Deprecated("Deprecated in Java")
                        override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                            val target = url ?: return false
                            if (isCashierOidcComplete(target, base)) {
                                finishOidc(target)
                                return true
                            }
                            return false
                        }

                        override fun onPageFinished(view: WebView?, url: String?) {
                            if (url == null || finished) return
                            if (isCashierOidcComplete(url, base)) {
                                finishOidc(url)
                                return
                            }
                            view?.evaluateJavascript(
                                "(document.body && document.body.innerText) || ''",
                            ) { raw ->
                                if (finished) return@evaluateJavascript
                                val text = raw?.trim()?.trim('"') ?: return@evaluateJavascript
                                if (text.contains("pending login approval", ignoreCase = true)) {
                                    finished = true
                                    onComplete(url)
                                }
                            }
                        }
                    }
                    webViewClient = PocSelfSignedTls.wrapWebViewClient(client)
                    loadUrl(loginUrl)
                }
            },
            onRelease = { webView -> webView.destroy() },
        )
    }
}

/** OIDC finished when the app redirects to till count or supervisor approval. */
private fun isCashierOidcComplete(url: String, base: String): Boolean {
    if (!url.startsWith(base)) return false
    val uri = Uri.parse(url)
    if (uri.getQueryParameter("awaiting_till") != null) return true
    if (uri.getQueryParameter("approval") == "pending") return true
    if (uri.getQueryParameter("cashier_resume") != null) return true
    return false
}

fun isAwaitingTillRedirect(completionUrl: String): Boolean {
    val value = Uri.parse(completionUrl).getQueryParameter("awaiting_till") ?: return false
    return value == "1" || value.equals("true", ignoreCase = true)
}

fun isCashierResumeRedirect(completionUrl: String): Boolean {
    val value = Uri.parse(completionUrl).getQueryParameter("cashier_resume") ?: return false
    return value == "1" || value.equals("true", ignoreCase = true)
}

fun parsePendingRequestToken(completionUrl: String): String? {
    val token = Uri.parse(completionUrl).getQueryParameter("request_token")?.trim()
    return token?.takeIf { it.isNotEmpty() }
}
