package com.cloudstore.pos.data

import android.annotation.SuppressLint
import android.net.http.SslError
import android.webkit.SslErrorHandler
import android.webkit.WebView
import android.webkit.WebViewClient
import com.cloudstore.pos.BuildConfig
import okhttp3.OkHttpClient
import java.security.SecureRandom
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

/**
 * POC / debug only: OCI LB may use a self-signed cert from generate-lb-tls.sh.
 * Debug APKs trust it; release builds require a public CA cert on the server.
 */
object PocSelfSignedTls {
    fun applyToOkHttpIfDebug(builder: OkHttpClient.Builder): OkHttpClient.Builder {
        if (!BuildConfig.DEBUG) return builder
        val trustAll = trustAllManager()
        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(null, arrayOf<TrustManager>(trustAll), SecureRandom())
        builder.sslSocketFactory(sslContext.socketFactory, trustAll)
        builder.hostnameVerifier { _, _ -> true }
        return builder
    }

    @SuppressLint("CustomX509TrustManager")
    private fun trustAllManager(): X509TrustManager =
        object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit

            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit

            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        }

    @SuppressLint("WebViewClientOnReceivedSslError")
    fun proceedSslErrorIfDebug(handler: SslErrorHandler?, error: SslError?): Boolean {
        if (!BuildConfig.DEBUG || handler == null) return false
        handler.proceed()
        return true
    }

    fun wrapWebViewClient(delegate: WebViewClient): WebViewClient =
        object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: android.webkit.WebResourceRequest?) =
                delegate.shouldOverrideUrlLoading(view, request)

            @Deprecated("Deprecated in Java")
            override fun shouldOverrideUrlLoading(view: WebView?, url: String?) =
                delegate.shouldOverrideUrlLoading(view, url)

            override fun onPageFinished(view: WebView?, url: String?) =
                delegate.onPageFinished(view, url)

            @SuppressLint("WebViewClientOnReceivedSslError")
            override fun onReceivedSslError(view: WebView?, handler: SslErrorHandler?, error: SslError?) {
                if (!proceedSslErrorIfDebug(handler, error)) {
                    super.onReceivedSslError(view, handler, error)
                }
            }
        }
}
