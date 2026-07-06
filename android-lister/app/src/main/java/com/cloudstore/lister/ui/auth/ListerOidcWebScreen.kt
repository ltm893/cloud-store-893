package com.cloudstore.lister.ui.auth

import android.annotation.SuppressLint
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.cloudstore.lister.data.PocSelfSignedTls
import com.cloudstore.lister.domain.ListerOidcRedirectLogic

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun ListerOidcWebScreen(
    loginUrl: String,
    apiBaseUrl: String,
    onComplete: (String) -> Unit,
    onCancel: () -> Unit,
) {
    val base = remember(apiBaseUrl) { apiBaseUrl.trimEnd('/') }
    BackHandler(onBack = onCancel)

    Column(
        Modifier
            .fillMaxSize()
            .navigationBarsPadding(),
    ) {
        TextButton(onClick = onCancel, modifier = Modifier.padding(8.dp)) {
            Text("Cancel")
        }
        Text(
            text = "Sign in",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 16.dp),
        )
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { context ->
                WebView(context).apply {
                    configureForListerAutofill()
                    settings.configureForListerWebView()
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                    var finished = false
                    fun finishOidc(url: String) {
                        if (finished || !ListerOidcRedirectLogic.isOidcComplete(url, base)) return
                        finished = true
                        stopLoading()
                        loadUrl("about:blank")
                        onComplete(url)
                    }
                    val client = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(
                            view: WebView?,
                            request: WebResourceRequest?,
                        ): Boolean {
                            val url = request?.url?.toString() ?: return false
                            if (ListerOidcRedirectLogic.isOidcComplete(url, base)) {
                                finishOidc(url)
                                return true
                            }
                            return false
                        }

                        @Deprecated("Deprecated in Java")
                        override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                            val target = url ?: return false
                            if (ListerOidcRedirectLogic.isOidcComplete(target, base)) {
                                finishOidc(target)
                                return true
                            }
                            return false
                        }

                        override fun onPageFinished(view: WebView?, url: String?) {
                            if (url == null || finished || url == "about:blank") return
                            if (ListerOidcRedirectLogic.isOidcComplete(url, base)) {
                                finishOidc(url)
                            }
                        }
                    }
                    webViewClient = PocSelfSignedTls.wrapWebViewClient(client)
                    loadUrl(loginUrl)
                }
            },
            update = { webView -> webView.configureForListerAutofill() },
            onRelease = { webView -> webView.destroy() },
        )
    }
}
