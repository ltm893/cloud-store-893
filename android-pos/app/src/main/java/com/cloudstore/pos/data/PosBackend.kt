package com.cloudstore.pos.data

/**
 * Backend surface used by [com.cloudstore.pos.ui.PosViewModel].
 * Real HTTP: [PosRepository] (prod flavor). Offline PIN demo: [StubPosRepository] (stub flavor).
 */
interface PosBackend {
    suspend fun products(): List<Product>
    suspend fun customers(): List<StoreCustomer>
    suspend fun cart(customerId: Int?): CartResponse
    suspend fun addProduct(productId: Int, customerId: Int?): CartResponse
    suspend fun addProductByBarcode(barcode: String, customerId: Int?): CartResponse
    suspend fun removeCartItem(cartItemId: Int, customerId: Int?): CartResponse
    suspend fun updateCartItemQuantity(cartItemId: Int, quantity: Int, customerId: Int?): CartResponse
    suspend fun replaceCart(lines: List<QueuedCartLine>, customerId: Int?): CartResponse
    suspend fun checkout(
        paymentMethod: String,
        customerId: Int?,
        payments: List<CheckoutPayment>? = null,
        checkoutTotal: Double? = null,
    ): CheckoutResponse
    suspend fun recentSales(): List<Sale>

    suspend fun cashierSession(): CashierSessionResponse
    suspend fun pollApprovalStatus(): ApprovalStatusResponse
    suspend fun cancelApproval(): OkResponse
    suspend fun tillConfig(): TillConfigResponse

    fun applySessionAuth(session: CashierSessionResponse)
    fun stashAwaitingTillToken(token: String?)
    fun awaitingTillTokenForSubmit(): String?
    fun prepareForTillSubmit()
    fun onTillSubmitSuccess(response: SubmitOpeningTillResponse)
    fun clearAwaitingTillAuth()
    suspend fun submitOpeningTill(body: SubmitOpeningTillRequest): SubmitOpeningTillResponse
    suspend fun cancelOpeningTill(): OkResponse

    fun syncWebViewCookies()
    fun pinAwaitingTillFromWebView(): Boolean
    fun clearPinnedPendingRequest()
    fun clearPinnedAwaitingTill()
    suspend fun clearStaleSignInCookies()
    fun rememberPendingRequestToken(token: String?)
    fun hasPendingRequestCookie(): Boolean
    fun hasCashierSessionCookie(): Boolean
    fun clearCashierCookies()

    suspend fun unlockCashier(pin: String, registerId: String): CashierSessionResponse
    suspend fun logoutCashier()
    suspend fun signOffCashier(registerId: String)

    suspend fun closeTillPreview(): CloseTillPreviewResponse
    suspend fun submitCloseTill(body: SubmitCloseTillRequest): SubmitCloseTillResponse
    suspend fun closeTillStatus(closeToken: String? = null): CloseTillStatusResponse
    suspend fun cancelCloseTill(): OkResponse

    fun clearWebViewIdpSession()
}
