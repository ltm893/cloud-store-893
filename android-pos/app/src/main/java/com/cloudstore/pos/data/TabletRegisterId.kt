package com.cloudstore.pos.data

import android.content.Context
import android.provider.Settings

/** Stable per-device register id sent to the server for one-cashier-per-tablet policy. */
object TabletRegisterId {
    fun get(context: Context): String {
        val androidId = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ANDROID_ID,
        )?.trim().orEmpty()
        return if (androidId.isNotEmpty()) "tablet-$androidId" else "tablet-unknown"
    }
}
