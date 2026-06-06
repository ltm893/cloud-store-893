package com.cloudstore.pos.data

import android.util.Log

object PosIdentityLog {
    private const val TAG = "PosIdentity"

    fun d(message: String) {
        Log.d(TAG, message)
    }

    fun session(label: String, session: CashierSessionResponse) {
        Log.d(
            TAG,
            "$label ok=${session.ok} auth=${session.auth} sub=${session.sub} user=${session.user} " +
                "email=${session.email} name=${session.name} cashierEmail=${session.cashierEmail} " +
                "approvalEmail=${session.approval?.cashierEmail} approvalName=${session.approval?.cashierName}",
        )
    }

    fun resolved(label: String, resolved: String?, stored: String?, stateUser: String?) {
        Log.d(
            TAG,
            "$label resolved=${resolved ?: "null"} stored=${stored ?: "null"} state=${stateUser ?: "null"}",
        )
    }
}
