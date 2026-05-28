package com.cloudstore.pos.ui.theme

import androidx.compose.material3.CardDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp

/** Explicit card colors so M3 does not tint panels rose from [PosPrimary]. */
object PosCardDefaults {
    @Composable
    fun elevation() = CardDefaults.cardElevation(defaultElevation = 0.dp)

    /** Scan/Add, Current Sale, Sale total, status strip — light cyan at 50% opacity. */
    @Composable
    fun contentColors() = CardDefaults.cardColors(
        containerColor = PosHighlightPanel,
        contentColor = PosText,
    )

    /** Right column: barcode numpad / payment / find customer — cream pad area. */
    @Composable
    fun numpadPanelColors() = CardDefaults.cardColors(
        containerColor = PosBackground,
        contentColor = PosText,
    )

    @Composable
    fun nestedColors() = CardDefaults.cardColors(
        containerColor = PosPanel,
        contentColor = PosText,
    )
}
