package com.cloudstore.lister.domain

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ListerOidcRedirectLogicTest {
    private val base = "https://oci.cloudstore893.com"

    @Test
    fun detectsListerSignedInQuery() {
        assertTrue(
            ListerOidcRedirectLogic.isOidcComplete(
                "$base/?lister_signed_in=1",
                base,
            ),
        )
    }

    @Test
    fun rejectsOAuthCallbackPath() {
        assertFalse(
            ListerOidcRedirectLogic.isOidcComplete(
                "$base/oauth/callback?code=x",
                base,
            ),
        )
    }

    @Test
    fun rejectsBareRootWithoutQuery() {
        assertFalse(ListerOidcRedirectLogic.isOidcComplete("$base/", base))
    }

    @Test
    fun rejectsAboutBlank() {
        assertFalse(ListerOidcRedirectLogic.isOidcComplete("about:blank", base))
    }
}
