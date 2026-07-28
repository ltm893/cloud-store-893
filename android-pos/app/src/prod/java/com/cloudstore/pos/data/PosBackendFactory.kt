package com.cloudstore.pos.data

import com.cloudstore.pos.BuildConfig

/** Prod flavor: real HTTP backend. */
object PosBackendFactory {
    fun create(): PosBackend = PosRepository(baseUrl = BuildConfig.API_BASE_URL)
}
