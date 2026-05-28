package com.cloudstore.pos.ui.theme

import androidx.compose.material3.ButtonDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

object PosButtonDefaults {
    /** Rounded filled actions — admin accent-2 teal (#114b5f). */
    @Composable
    fun teal() = ButtonDefaults.buttonColors(
        containerColor = PosAccent,
        contentColor = Color.White,
        disabledContainerColor = PosHighlight,
        disabledContentColor = PosMuted,
    )

    @Composable
    fun numpadKey() = ButtonDefaults.buttonColors(
        containerColor = PosHighlight,
        contentColor = Color.Black,
    )

    @Composable
    fun numpadKeySecondary() = ButtonDefaults.buttonColors(
        containerColor = PosHighlight,
        contentColor = Color.Black,
    )
}
