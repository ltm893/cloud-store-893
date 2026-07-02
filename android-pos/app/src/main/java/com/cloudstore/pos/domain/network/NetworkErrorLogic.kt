package com.cloudstore.pos.domain.network

import retrofit2.HttpException
import java.io.IOException

object NetworkErrorLogic {
    /** True only for transport failures — not HTTP 4xx/5xx (Retrofit wraps those as HttpException). */
    fun isOfflineLike(err: Throwable): Boolean = err is IOException && err !is HttpException

    fun isRetryableSyncError(err: Throwable): Boolean = isOfflineLike(err)

    fun httpErrorMessage(err: HttpException, fallback: String): String =
        formatApiError(err.response()?.errorBody()?.use { it.string() }.orEmpty(), fallback, err.code())

    fun formatApiError(body: String, fallback: String, statusCode: Int? = null): String {
        val jsonError = Regex(""""error"\s*:\s*"([^"]+)"""").find(body)?.groupValues?.getOrNull(1)
        val maxOrderable = Regex(""""maxOrderable"\s*:\s*(\d+)""")
            .find(body)?.groupValues?.getOrNull(1)?.toIntOrNull()
        val base = jsonError?.takeIf { it.isNotBlank() }
            ?: if (statusCode != null) "$fallback ($statusCode)" else fallback
        return if (maxOrderable != null && maxOrderable > 0) "$base (max $maxOrderable can be ordered)" else base
    }
}
