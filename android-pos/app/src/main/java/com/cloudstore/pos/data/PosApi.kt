package com.cloudstore.pos.data

import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import okhttp3.Cookie
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query

interface PosApi {
    @GET("api/products")
    suspend fun getProducts(): List<Product>

    @GET("api/customers")
    suspend fun getCustomers(): List<StoreCustomer>

    @GET("api/cart")
    suspend fun getCart(@Query("customerId") customerId: Int?): CartResponse

    @POST("api/cart")
    suspend fun addToCart(
        @Body body: Map<String, Int>,
        @Query("customerId") customerId: Int? = null,
    ): CartResponse

    @POST("api/cart/barcode")
    suspend fun addByBarcode(
        @Body body: Map<String, String>,
        @Query("customerId") customerId: Int? = null,
    ): CartResponse

    @PUT("api/cart/{id}")
    suspend fun updateCartQuantity(
        @Path("id") cartItemId: Int,
        @Body body: Map<String, Int>,
        @Query("customerId") customerId: Int? = null,
    ): CartResponse

    @DELETE("api/cart/{id}")
    suspend fun removeFromCart(
        @Path("id") cartItemId: Int,
        @Query("customerId") customerId: Int? = null,
    ): CartResponse

    @POST("api/cart/replace")
    suspend fun replaceCart(@Body body: CartReplaceRequest): CartResponse

    @POST("api/checkout")
    suspend fun checkout(@Body body: CheckoutRequest): CheckoutResponse

    @GET("api/sales/recent")
    suspend fun getRecentSales(): List<Sale>

    @POST("api/cashier/unlock")
    suspend fun unlockCashier(@Body body: Map<String, String>): OkResponse

    @GET("api/cashier/session")
    suspend fun cashierSession(): CashierSessionResponse

    @GET("api/cashier/approval/status")
    suspend fun approvalStatus(): ApprovalStatusResponse

    @POST("api/cashier/approval/cancel")
    suspend fun cancelApproval(): OkResponse

    @POST("api/cashier/logout")
    suspend fun logoutCashier(): OkResponse
}

class PosRepository(baseUrl: String) {
    private val api: PosApi
    private val normalizedBaseUrl: String
    val cookieJar = MemoryCookieJar()

    init {
        normalizedBaseUrl = baseUrl.trim().let { url ->
            if (url.endsWith("/")) url else "$url/"
        }

        val logger = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BASIC
        }

        val okHttp = OkHttpClient.Builder()
            .cookieJar(cookieJar)
            .addInterceptor(logger)
            .build()

        val moshi = Moshi.Builder()
            .add(KotlinJsonAdapterFactory())
            .build()

        val retrofit = Retrofit.Builder()
            .baseUrl(normalizedBaseUrl)
            .client(okHttp)
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()

        api = retrofit.create(PosApi::class.java)
    }

    suspend fun products() = api.getProducts()
    suspend fun customers() = api.getCustomers()
    suspend fun cart(customerId: Int?) = api.getCart(customerId)
    suspend fun addProduct(productId: Int, customerId: Int?) =
        api.addToCart(mapOf("productId" to productId), customerId)

    suspend fun addProductByBarcode(barcode: String, customerId: Int?) =
        api.addByBarcode(mapOf("barcode" to barcode), customerId)

    suspend fun removeCartItem(cartItemId: Int, customerId: Int?) =
        api.removeFromCart(cartItemId, customerId)

    suspend fun updateCartItemQuantity(cartItemId: Int, quantity: Int, customerId: Int?) =
        api.updateCartQuantity(cartItemId, mapOf("quantity" to quantity), customerId)

    suspend fun replaceCart(lines: List<QueuedCartLine>, customerId: Int?) =
        api.replaceCart(
            CartReplaceRequest(
                items = lines.map { CartLineQuantity(it.productId, it.quantity) },
                customerId = customerId,
            ),
        )

    suspend fun checkout(
        paymentMethod: String,
        customerId: Int?,
        payments: List<CheckoutPayment>? = null,
        checkoutTotal: Double? = null,
    ) = api.checkout(
        CheckoutRequest(
            paymentMethod = paymentMethod,
            customerId = customerId,
            payments = payments,
            checkoutTotal = checkoutTotal,
        ),
    )

    suspend fun recentSales() = api.getRecentSales()

    suspend fun cashierSession() = api.cashierSession()

    suspend fun pollApprovalStatus() = api.approvalStatus()

    suspend fun cancelApproval() = api.cancelApproval()

    fun syncWebViewCookies() {
        WebViewCookieSync.sync(normalizedBaseUrl, cookieJar)
    }

    /** WebView→Retrofit bridge: inject pending token when CookieManager sync is unreliable. */
    fun rememberPendingRequestToken(token: String?) {
        val trimmed = token?.trim().orEmpty()
        if (trimmed.isEmpty()) return
        cookieJar.pinnedPendingToken = trimmed
        val httpUrl = normalizedBaseUrl.toHttpUrlOrNull() ?: return
        cookieJar.saveFromResponse(httpUrl, listOf(buildCookie(httpUrl, "cashier_pending", trimmed)))
    }

    fun hasPendingRequestCookie(): Boolean {
        if (!cookieJar.pinnedPendingToken.isNullOrBlank()) return true
        val httpUrl = normalizedBaseUrl.toHttpUrlOrNull() ?: return false
        return cookieJar.loadForRequest(httpUrl).any { it.name == "cashier_pending" }
    }

    fun hasCashierSessionCookie(): Boolean {
        if (!cookieJar.manualSessionId.isNullOrBlank()) return true
        val httpUrl = normalizedBaseUrl.toHttpUrlOrNull() ?: return false
        return cookieJar.loadForRequest(httpUrl).any { it.name == "cashier_session" }
    }

    private fun buildCookie(httpUrl: okhttp3.HttpUrl, name: String, value: String): Cookie =
        Cookie.Builder()
            .name(name)
            .value(value)
            .domain(httpUrl.host)
            .path("/")
            .httpOnly()
            .build()

    fun clearCashierCookies() {
        normalizedBaseUrl.toHttpUrlOrNull()?.host?.let { cookieJar.clearHost(it) }
    }

    suspend fun unlockCashier(pin: String) {
        val res = api.unlockCashier(mapOf("pin" to pin))
        if (!res.ok) throw IllegalStateException("Unlock failed")
        val session = api.cashierSession()
        if (!session.ok) {
            throw IllegalStateException("Sign-in did not persist — rebuild APK with correct LAN_IP")
        }
    }

    suspend fun logoutCashier() {
        runCatching { api.logoutCashier() }
        clearCashierCookies()
    }
}
