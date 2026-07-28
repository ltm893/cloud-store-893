package com.cloudstore.pos.data

/** Stub flavor: in-memory PIN backend (no network). */
object PosBackendFactory {
    fun create(): PosBackend = StubPosRepository()
}
