package com.cloudstore.lister.data

import com.squareup.moshi.JsonClass
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Query

interface ListerApi {
    @GET("api/inventory/lookup")
    suspend fun inventoryLookup(@Query("q") query: String): InventoryProduct

    @GET("api/cashier/session")
    suspend fun cashierSession(@Query("register_id") registerId: String): CashierSessionResponse

    @POST("api/cashier/logout")
    suspend fun logoutCashier(@Body body: EmptyBody = EmptyBody()): OkResponse
}

@JsonClass(generateAdapter = true)
class EmptyBody
