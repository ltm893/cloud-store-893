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

    @GET("api/cashier/till/config")
    suspend fun tillConfig(): TillConfigResponse

    @POST("api/cashier/approval/till")
    suspend fun submitOpeningTill(@Body body: SubmitOpeningTillRequest): SubmitOpeningTillResponse

    @POST("api/cashier/approval/till/cancel")
    suspend fun cancelOpeningTill(): OkResponse

    @POST("api/cashier/logout")
    suspend fun logoutCashier(): OkResponse

    @POST("api/cashier/sign-off")
    suspend fun signOffCashier(@Body body: Map<String, String>): OkResponse

    @GET("api/cashier/shift/close/preview")
    suspend fun closeTillPreview(): CloseTillPreviewResponse

    @POST("api/cashier/shift/close/till")
    suspend fun submitCloseTill(@Body body: SubmitCloseTillRequest): SubmitCloseTillResponse

    @GET("api/cashier/shift/close/status")
    suspend fun closeTillStatus(@Query("closeToken") closeToken: String? = null): CloseTillStatusResponse

    @POST("api/cashier/shift/close/cancel")
    suspend fun cancelCloseTill(): OkResponse
}

class PosRepository(baseUrl: String) {
    private val api: PosApi
    private val normalizedBaseUrl: String
    val cookieJar = MemoryCookieJar()
    /** Echo of server awaiting-till token — cookie fallback for POST /approval/till. */
    private var storedAwaitingTillToken: String? = null

    init {
        normalizedBaseUrl = baseUrl.trim().let { url ->
            if (url.endsWith("/")) url else "$url/"
        }

        val logger = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BASIC
        }

        val okHttp = PocSelfSignedTls.applyToOkHttpIfDebug(
            OkHttpClient.Builder()
                .cookieJar(cookieJar)
                .addInterceptor(logger),
        ).build()

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

    suspend fun tillConfig() = api.tillConfig()

    fun applySessionAuth(session: CashierSessionResponse) {
        stashAwaitingTillToken(session.awaitingTillToken)
    }

    fun stashAwaitingTillToken(token: String?) {
        val trimmed = token?.trim().orEmpty()
        if (trimmed.isEmpty()) return
        storedAwaitingTillToken = trimmed
        pinAwaitingTillToken(trimmed)
    }

    fun awaitingTillTokenForSubmit(): String? = storedAwaitingTillToken?.trim()?.takeIf { it.isNotEmpty() }

    fun prepareForTillSubmit() {
        syncWebViewCookies()
        pinAwaitingTillFromWebView()
        awaitingTillTokenForSubmit()?.let { pinAwaitingTillToken(it) }
    }

    fun onTillSubmitSuccess(response: SubmitOpeningTillResponse) {
        if (response.pending || response.ok) {
            clearAwaitingTillAuth()
        }
        response.requestToken?.let { rememberPendingRequestToken(it) }
    }

    private fun pinAwaitingTillToken(token: String) {
        val httpUrl = normalizedBaseUrl.toHttpUrlOrNull() ?: return
        cookieJar.pinnedAwaitingTillToken = token
        cookieJar.saveFromResponse(httpUrl, listOf(buildCookie(httpUrl, "cashier_awaiting_till", token)))
    }

    fun clearAwaitingTillAuth() {
        storedAwaitingTillToken = null
        cookieJar.clearPinnedAwaitingTillToken()
    }

    suspend fun submitOpeningTill(body: SubmitOpeningTillRequest): SubmitOpeningTillResponse {
        val response = api.submitOpeningTill(body)
        onTillSubmitSuccess(response)
        return response
    }

    suspend fun cancelOpeningTill() = api.cancelOpeningTill()

    fun syncWebViewCookies() {
        WebViewCookieSync.sync(normalizedBaseUrl, cookieJar)
    }

    fun pinAwaitingTillFromWebView(): Boolean {
        val found = WebViewCookieSync.pinAwaitingTillFromWebView(normalizedBaseUrl, cookieJar)
        cookieJar.pinnedAwaitingTillToken?.let { storedAwaitingTillToken = it }
        return found
    }

    fun clearPinnedPendingRequest() {
        cookieJar.clearPinnedPendingToken()
    }

    fun clearPinnedAwaitingTill() {
        clearAwaitingTillAuth()
    }

    suspend fun clearStaleSignInCookies() {
        runCatching { cancelOpeningTill() }
        runCatching { cancelApproval() }
        clearAwaitingTillAuth()
        clearPinnedPendingRequest()
        clearCashierCookies()
        clearWebViewIdpSession()
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

    suspend fun unlockCashier(pin: String, registerId: String): CashierSessionResponse {
        val res = api.unlockCashier(
            mapOf(
                "pin" to pin,
                "registerId" to registerId,
                "clientKind" to "tablet",
            ),
        )
        if (!res.ok) throw IllegalStateException("Unlock failed")
        stashAwaitingTillToken(res.awaitingTillToken)
        val session = api.cashierSession()
        if (!session.ok && !session.awaitingTill) {
            throw IllegalStateException("Sign-in did not persist — rebuild APK with correct LAN_IP")
        }
        return session
    }

    suspend fun logoutCashier() {
        runCatching { api.logoutCashier() }
        clearCashierCookies()
    }

    suspend fun signOffCashier(registerId: String) {
        runCatching { api.signOffCashier(mapOf("registerId" to registerId)) }
        clearCashierCookies()
        clearWebViewIdpSession()
    }

    suspend fun closeTillPreview() = api.closeTillPreview()

    suspend fun submitCloseTill(body: SubmitCloseTillRequest) = api.submitCloseTill(body)

    suspend fun closeTillStatus(closeToken: String? = null) = api.closeTillStatus(closeToken)

    suspend fun cancelCloseTill() = api.cancelCloseTill()

    fun clearWebViewIdpSession() {
        clearIdpWebViewCookies()
    }
}
