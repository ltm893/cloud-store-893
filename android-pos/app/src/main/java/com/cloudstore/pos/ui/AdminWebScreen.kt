package com.cloudstore.pos.ui

import android.annotation.SuppressLint
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
fun AdminWebScreen(
    apiBaseUrl: String,
    onClose: () -> Unit,
) {
    val base = remember(apiBaseUrl) { apiBaseUrl.trimEnd('/') }
    val adminStartUrl = remember(base) { "$base/admin/" }

    BackHandler(onBack = onClose)

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
            TextButton(onClick = onClose) {
                Text("← Register")
            }
            Text(
                text = "Admin",
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
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.loadWithOverviewMode = true
                    settings.useWideViewPort = true
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                    val client = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(
                            view: WebView?,
                            request: WebResourceRequest?,
                        ): Boolean {
                            val url = request?.url?.toString() ?: return false
                            if (shouldLeaveAdmin(url, base)) {
                                onClose()
                                return true
                            }
                            return false
                        }

                        @Deprecated("Deprecated in Java")
                        override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                            val target = url ?: return false
                            if (shouldLeaveAdmin(target, base)) {
                                onClose()
                                return true
                            }
                            return false
                        }
                    }
                    webViewClient = PocSelfSignedTls.wrapWebViewClient(client)
                    loadUrl(adminStartUrl)
                }
            },
            onRelease = { webView -> webView.destroy() },
        )
    }
}

/** Web POS root — return to native register instead of loading browser POS HTML. */
private fun shouldLeaveAdmin(url: String, base: String): Boolean {
    val normalized = url.trimEnd('/')
    return normalized == base || normalized == "$base/"
}
