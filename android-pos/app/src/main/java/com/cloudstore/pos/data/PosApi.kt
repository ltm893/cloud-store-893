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

interface PosApi {
    @GET("api/products")
    suspend fun getProducts(): List<Product>

    @GET("api/cart")
    suspend fun getCart(): List<CartItem>

    @POST("api/cart")
    suspend fun addToCart(@Body body: Map<String, Int>)

    @POST("api/cart/barcode")
    suspend fun addByBarcode(@Body body: Map<String, String>)

    @DELETE("api/cart/{id}")
    suspend fun removeFromCart(@Path("id") cartItemId: Int)

    @POST("api/checkout")
    suspend fun checkout(@Body body: CheckoutRequest): CheckoutResponse

    @GET("api/sales/recent")
    suspend fun getRecentSales(): List<Sale>
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
    suspend fun cart() = api.getCart()
    suspend fun addProduct(productId: Int) = api.addToCart(mapOf("productId" to productId))
    suspend fun addProductByBarcode(barcode: String) = api.addByBarcode(mapOf("barcode" to barcode))
    suspend fun removeCartItem(cartItemId: Int) = api.removeFromCart(cartItemId)
    suspend fun checkout(paymentMethod: String) = api.checkout(CheckoutRequest(paymentMethod))
    suspend fun recentSales() = api.getRecentSales()
}
