package com.cloudstore.lister.data

import android.content.Context
import android.provider.Settings

object ListerRegisterId {
    fun get(context: Context): String {
        val androidId = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ANDROID_ID,
        )?.trim().orEmpty()
        return if (androidId.isNotEmpty()) "lister-$androidId" else "lister-unknown"
    }
}
