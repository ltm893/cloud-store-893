package com.cloudstore.pos.data

import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
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

    @DELETE("api/cart/{id}")
    suspend fun removeFromCart(
        @Path("id") cartItemId: Int,
        @Query("customerId") customerId: Int? = null,
    ): CartResponse

    @POST("api/checkout")
    suspend fun checkout(@Body body: CheckoutRequest): CheckoutResponse

    @GET("api/sales/recent")
    suspend fun getRecentSales(): List<Sale>

    @POST("api/cashier/unlock")
    suspend fun unlockCashier(@Body body: Map<String, String>): UnlockResponse
}

class PosRepository(baseUrl: String) {
    private val api: PosApi

    init {
        val logger = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BASIC
        }

        val okHttp = OkHttpClient.Builder()
            .addInterceptor(logger)
            .build()

        val moshi = Moshi.Builder()
            .add(KotlinJsonAdapterFactory())
            .build()

        val retrofit = Retrofit.Builder()
            .baseUrl(baseUrl)
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

    suspend fun checkout(paymentMethod: String, customerId: Int?) =
        api.checkout(CheckoutRequest(paymentMethod = paymentMethod, customerId = customerId))

    suspend fun recentSales() = api.getRecentSales()

    suspend fun unlockCashier(pin: String) {
        val res = api.unlockCashier(mapOf("pin" to pin))
        if (!res.ok) throw IllegalStateException("Unlock failed")
    }
}
