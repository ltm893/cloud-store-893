package com.cloudstore.pos.ui

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.cloudstore.pos.BuildConfig

/** Right-column width for numpad / payment / customer-find card (75% of original 360dp). */
internal val PosNumpadColumnWidth = 270.dp

/**
 * Cream numpad card height on the sale screen.
 * Stub is shorter so Cash / Charge Card stay visible on small Fire tablets.
 */
internal val PosNumpadCardHeight: Dp
    get() = if (BuildConfig.STUB_BACKEND) 148.dp else 222.dp

/** Inner padding around [NumberPad] inside the numpad card (75% of original 12dp). */
internal val PosNumpadInnerPadding = 9.dp

/** Gap between numpad keys (75% of original 8dp). */
internal val PosNumpadKeyGap = 6.dp

/** Up/down denomination keys beside till-count numpad. */
internal val PosNumpadNavKeyWidth = 40.dp

/** Till numpad card width including nav arrow column. */
internal val TillNumpadCardWidth = PosNumpadColumnWidth + PosNumpadNavKeyWidth + PosNumpadKeyGap
