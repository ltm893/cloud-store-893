package com.cloudstore.lister.data

import android.annotation.SuppressLint
import android.net.http.SslError
import android.webkit.SslErrorHandler
import android.webkit.WebView
import android.webkit.WebViewClient
import com.cloudstore.lister.BuildConfig
import okhttp3.OkHttpClient
import java.security.SecureRandom
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

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
                if (BuildConfig.DEBUG && handler != null) handler.proceed()
                else super.onReceivedSslError(view, handler, error)
            }
        }
}
