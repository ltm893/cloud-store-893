package com.cloudstore.pos.data

/**
 * In-memory POS backend for local UI/dev without Node or network.
 * PIN unlock accepts any PIN with 4+ digits (demo default: 8930).
 */
class StubPosRepository : PosBackend {
    private var signedIn = false
    private var nextCartLineId = 1
    private var nextSaleId = 1
    private var nextOrderSeq = 1

    private val catalog: List<Product> = listOf(
        Product(id = 1, barcode = "100000000001", name = "Ballet Leotard — Black", regularPrice = 28.00, quantityOnHand = 24),
        Product(id = 2, barcode = "100000000002", name = "Tutu Skirt — Pink", regularPrice = 42.00, salePrice = 34.99, onSale = true, quantityOnHand = 12),
        Product(id = 3, barcode = "100000000003", name = "Jazz Shoes — Tan", regularPrice = 36.50, quantityOnHand = 18),
        Product(id = 4, barcode = "100000000004", name = "Ballet Slippers — Pink", regularPrice = 24.99, quantityOnHand = 30),
        Product(id = 5, barcode = "100000000005", name = "Character Skirt — Black", regularPrice = 32.00, quantityOnHand = 15),
        Product(id = 6, barcode = "100000000006", name = "Dance Tights — Nude", regularPrice = 12.99, taxExempt = false, quantityOnHand = 60),
        Product(id = 7, barcode = "100000000007", name = "Competition Dress — Navy", regularPrice = 89.00, salePrice = 74.99, onSale = true, quantityOnHand = 6),
        Product(id = 8, barcode = "100000000008", name = "Hair Bun Net Pack", regularPrice = 6.50, quantityOnHand = 80),
        Product(id = 9, barcode = "100000000009", name = "Warm-up Booties", regularPrice = 22.00, quantityOnHand = 20),
        Product(id = 10, barcode = "100000000010", name = "Gift Card \$50", regularPrice = 50.0, taxExempt = true, quantityOnHand = 100),
    )

    private val customerList: List<StoreCustomer> = listOf(
        StoreCustomer(id = 1, name = "Ryan", is893 = false),
        StoreCustomer(id = 2, name = "Quinn", memberCode = "893-2041", is893 = true, hasCardOnFile = true, cardLast4 = "4242"),
        StoreCustomer(id = 3, name = "Zarya", email = "zarya@example.com", phone = "555-0142"),
        StoreCustomer(id = 4, name = "Jeremiah", is893 = false),
        StoreCustomer(id = 5, name = "Juni", memberCode = "893-2042", is893 = true),
    )

    private val cartLines = mutableListOf<CartItem>()
    private val sales = mutableListOf<Sale>()

    private fun signedOutSession() = CashierSessionResponse(
        ok = false,
        pinAllowed = true,
        supervisorApprovalRequired = false,
        idpEnabled = false,
        cashTillEnabled = false,
        cashEnabled = true,
        tillOpenForSales = true,
    )

    private fun signedInSession() = CashierSessionResponse(
        ok = true,
        auth = "pin",
        user = "Stub Cashier",
        pinAllowed = true,
        supervisorApprovalRequired = false,
        idpEnabled = false,
        cashTillEnabled = false,
        cashEnabled = true,
        tillOpenForSales = true,
    )

    private fun requireSignedIn() {
        if (!signedIn) throw IllegalStateException("Not signed in")
    }

    private fun unitPrice(product: Product): Double =
        if (product.onSale && product.salePrice != null) product.salePrice else product.regularPrice

    private fun buildCart(customerId: Int?): CartResponse {
        val linked = customerList.firstOrNull { it.id == customerId }?.is893 == true
        val discountRate = if (linked) 0.10 else 0.0
        var subtotalPre = 0.0
        var subtotalPay = 0.0
        val items = cartLines.map { line ->
            val public = line.unitPricePublic * line.quantity
            val payableUnit = line.unitPricePublic * (1.0 - discountRate)
            val payable = payableUnit * line.quantity
            subtotalPre += public
            subtotalPay += payable
            line.copy(
                unitPricePayable = payableUnit,
                lineSubtotalPublic = public,
                lineSubtotalPayable = payable,
            )
        }
        return CartResponse(
            items = items,
            subtotalPreMember = round2(subtotalPre),
            subtotalPayable = round2(subtotalPay),
            memberDiscountPreTax = round2(subtotalPre - subtotalPay),
            linked893 = linked,
        )
    }

    private fun round2(value: Double): Double = kotlin.math.round(value * 100.0) / 100.0

    private fun addOrBump(product: Product, customerId: Int?): CartResponse {
        requireSignedIn()
        val existing = cartLines.indexOfFirst { it.productId == product.id }
        if (existing >= 0) {
            val line = cartLines[existing]
            val qty = line.quantity + 1
            val unit = line.unitPricePublic
            cartLines[existing] = line.copy(
                quantity = qty,
                lineSubtotalPublic = unit * qty,
                lineSubtotalPayable = unit * qty,
            )
        } else {
            val unit = unitPrice(product)
            cartLines += CartItem(
                id = nextCartLineId++,
                productId = product.id,
                name = product.name,
                regularPrice = product.regularPrice,
                salePrice = product.salePrice,
                onSale = product.onSale,
                taxExempt = product.taxExempt,
                quantity = 1,
                unitPricePublic = unit,
                unitPricePayable = unit,
                lineSubtotalPublic = unit,
                lineSubtotalPayable = unit,
            )
        }
        return buildCart(customerId)
    }

    override suspend fun products(): List<Product> {
        requireSignedIn()
        return catalog
    }

    override suspend fun customers(): List<StoreCustomer> {
        requireSignedIn()
        return customerList
    }

    override suspend fun cart(customerId: Int?): CartResponse {
        requireSignedIn()
        return buildCart(customerId)
    }

    override suspend fun addProduct(productId: Int, customerId: Int?): CartResponse {
        val product = catalog.firstOrNull { it.id == productId }
            ?: throw IllegalStateException("Product not found: $productId")
        return addOrBump(product, customerId)
    }

    override suspend fun addProductByBarcode(barcode: String, customerId: Int?): CartResponse {
        val trimmed = barcode.trim()
        val product = catalog.firstOrNull { it.barcode == trimmed || it.id.toString() == trimmed }
            ?: throw IllegalStateException("Barcode not found: $trimmed")
        return addOrBump(product, customerId)
    }

    override suspend fun removeCartItem(cartItemId: Int, customerId: Int?): CartResponse {
        requireSignedIn()
        cartLines.removeAll { it.id == cartItemId }
        return buildCart(customerId)
    }

    override suspend fun updateCartItemQuantity(cartItemId: Int, quantity: Int, customerId: Int?): CartResponse {
        requireSignedIn()
        val index = cartLines.indexOfFirst { it.id == cartItemId }
        if (index < 0) throw IllegalStateException("Cart line not found")
        if (quantity <= 0) {
            cartLines.removeAt(index)
        } else {
            val line = cartLines[index]
            val unit = line.unitPricePublic
            cartLines[index] = line.copy(
                quantity = quantity,
                lineSubtotalPublic = unit * quantity,
                lineSubtotalPayable = unit * quantity,
            )
        }
        return buildCart(customerId)
    }

    override suspend fun replaceCart(lines: List<QueuedCartLine>, customerId: Int?): CartResponse {
        requireSignedIn()
        cartLines.clear()
        lines.forEach { queued ->
            val product = catalog.firstOrNull { it.id == queued.productId } ?: return@forEach
            val unit = unitPrice(product)
            val qty = queued.quantity.coerceAtLeast(1)
            cartLines += CartItem(
                id = nextCartLineId++,
                productId = product.id,
                name = product.name,
                regularPrice = product.regularPrice,
                salePrice = product.salePrice,
                onSale = product.onSale,
                taxExempt = product.taxExempt,
                quantity = qty,
                unitPricePublic = unit,
                unitPricePayable = unit,
                lineSubtotalPublic = unit * qty,
                lineSubtotalPayable = unit * qty,
            )
        }
        return buildCart(customerId)
    }

    override suspend fun checkout(
        paymentMethod: String,
        customerId: Int?,
        payments: List<CheckoutPayment>?,
        checkoutTotal: Double?,
    ): CheckoutResponse {
        requireSignedIn()
        val cart = buildCart(customerId)
        if (cart.items.isEmpty()) throw IllegalStateException("Cart is empty")
        val total = checkoutTotal ?: cart.subtotalPayable
        val orderNumber = "STUB-%04d".format(nextOrderSeq++)
        sales.add(
            0,
            Sale(
                id = nextSaleId++,
                orderNumber = orderNumber,
                total = round2(total),
                paymentMethod = paymentMethod,
                linked893 = cart.linked893,
                memberDiscountPreTax = cart.memberDiscountPreTax,
                subtotalPreMember = cart.subtotalPreMember,
            ),
        )
        cartLines.clear()
        return CheckoutResponse(
            ok = true,
            orderNumber = orderNumber,
            total = round2(total),
            paymentMethod = paymentMethod,
            subtotalPreMember = cart.subtotalPreMember,
            memberDiscountPreTax = cart.memberDiscountPreTax,
            linked893 = cart.linked893,
            customerId = customerId,
            payments = payments,
        )
    }

    override suspend fun recentSales(): List<Sale> {
        requireSignedIn()
        return sales.toList()
    }

    override suspend fun cashierSession(): CashierSessionResponse =
        if (signedIn) signedInSession() else signedOutSession()

    override suspend fun pollApprovalStatus(): ApprovalStatusResponse =
        ApprovalStatusResponse(status = "none", ok = false)

    override suspend fun cancelApproval(): OkResponse = OkResponse(ok = true)

    override suspend fun tillConfig(): TillConfigResponse =
        TillConfigResponse(cashTillEnabled = false)

    override fun applySessionAuth(session: CashierSessionResponse) = Unit
    override fun stashAwaitingTillToken(token: String?) = Unit
    override fun awaitingTillTokenForSubmit(): String? = null
    override fun prepareForTillSubmit() = Unit
    override fun onTillSubmitSuccess(response: SubmitOpeningTillResponse) = Unit
    override fun clearAwaitingTillAuth() = Unit

    override suspend fun submitOpeningTill(body: SubmitOpeningTillRequest): SubmitOpeningTillResponse =
        SubmitOpeningTillResponse(ok = true, cashEnabled = true)

    override suspend fun cancelOpeningTill(): OkResponse = OkResponse(ok = true)

    override fun syncWebViewCookies() = Unit
    override fun pinAwaitingTillFromWebView(): Boolean = false
    override fun clearPinnedPendingRequest() = Unit
    override fun clearPinnedAwaitingTill() = Unit
    override suspend fun clearStaleSignInCookies() {
        signedIn = false
        cartLines.clear()
    }

    override fun rememberPendingRequestToken(token: String?) = Unit
    override fun hasPendingRequestCookie(): Boolean = false
    override fun hasCashierSessionCookie(): Boolean = signedIn
    override fun clearCashierCookies() {
        signedIn = false
    }

    override suspend fun unlockCashier(pin: String, registerId: String): CashierSessionResponse {
        val trimmed = pin.trim()
        if (trimmed.length < 4) throw IllegalStateException("Unlock failed")
        signedIn = true
        return signedInSession()
    }

    override suspend fun logoutCashier() {
        signedIn = false
        cartLines.clear()
    }

    override suspend fun signOffCashier(registerId: String) {
        logoutCashier()
    }

    override suspend fun closeTillPreview(): CloseTillPreviewResponse =
        CloseTillPreviewResponse(ok = false, creditOnly = true, error = "Stub mode — no till")

    override suspend fun submitCloseTill(body: SubmitCloseTillRequest): SubmitCloseTillResponse =
        SubmitCloseTillResponse(ok = false, error = "Stub mode — no till")

    override suspend fun closeTillStatus(closeToken: String?): CloseTillStatusResponse =
        CloseTillStatusResponse(status = "none", ok = false)

    override suspend fun cancelCloseTill(): OkResponse = OkResponse(ok = true)

    override fun clearWebViewIdpSession() = Unit
}
