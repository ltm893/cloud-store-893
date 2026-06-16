package com.cloudstore.pos.domain.network

import retrofit2.HttpException
import java.io.IOException

object NetworkErrorLogic {
    /** True only for transport failures — not HTTP 4xx/5xx (Retrofit wraps those as HttpException). */
    fun isOfflineLike(err: Throwable): Boolean = err is IOException && err !is HttpException

    fun isRetryableSyncError(err: Throwable): Boolean = isOfflineLike(err)

    fun httpErrorMessage(err: HttpException, fallback: String): String {
        val body = err.response()?.errorBody()?.use { it.string() }.orEmpty()
        val jsonError = Regex(""""error"\s*:\s*"([^"]+)"""").find(body)?.groupValues?.getOrNull(1)
        return jsonError?.takeIf { it.isNotBlank() } ?: "$fallback (${err.code()})"
    }
}
