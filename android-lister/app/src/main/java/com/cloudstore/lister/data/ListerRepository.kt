package com.cloudstore.lister.data

import com.cloudstore.lister.domain.ApiConfigLogic
import com.cloudstore.lister.domain.BarcodeNormalizeLogic
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.HttpException
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory

class ListerRepository(
    baseUrl: String,
    val cookieJar: ListerCookieJar = ListerCookieJar(),
) {
    private val normalizedBase = ApiConfigLogic.normalizeBaseUrl(baseUrl)
    private val api: ListerApi

    init {
        val logging = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BASIC
        }
        val client = PocSelfSignedTls.applyToOkHttpIfDebug(
            OkHttpClient.Builder()
                .cookieJar(cookieJar)
                .addInterceptor(logging),
        ).build()
        val moshi = Moshi.Builder().add(KotlinJsonAdapterFactory()).build()
        api = Retrofit.Builder()
            .baseUrl(normalizedBase)
            .client(client)
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()
            .create(ListerApi::class.java)
    }

    suspend fun lookup(query: String): InventoryProduct {
        val candidates = BarcodeNormalizeLogic.lookupCandidates(query).ifEmpty { listOf(query) }
        var lastError: Exception? = null
        for (candidate in candidates) {
            try {
                return api.inventoryLookup(candidate)
            } catch (e: HttpException) {
                lastError = e
                if (e.code() == 404) continue
                throw e
            }
        }
        throw lastError ?: IllegalStateException("Lookup failed")
    }

    suspend fun fetchSession(registerId: String): CashierSessionResponse =
        api.cashierSession(registerId)

    fun syncWebViewCookies() {
        WebViewCookieSync.sync(normalizedBase, cookieJar)
    }

    fun pinCashierSessionFromWebView(): Boolean =
        WebViewCookieSync.pinCashierSessionFromWebView(normalizedBase, cookieJar)

    fun hasCashierSessionCookie(): Boolean = cookieJar.hasCashierSession()

    suspend fun logout() {
        runCatching { api.logoutCashier() }
    }
}
