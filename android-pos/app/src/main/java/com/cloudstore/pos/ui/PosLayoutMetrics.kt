package com.cloudstore.pos.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.cloudstore.pos.BuildConfig

/** Max width for a standard number pad (no till nav column). */
internal val PosNumpadColumnWidth = 270.dp

/**
 * Fixed height for every number-pad host (cream card or checkout pad slot).
 * Stub is shorter so Cash / Charge Card stay visible on small Fire tablets.
 */
internal val PosNumpadCardHeight: Dp
    get() = if (BuildConfig.STUB_BACKEND) 148.dp else 222.dp

/** Inner padding around [NumberPad] inside its host. */
internal val PosNumpadInnerPadding = 9.dp

/** Gap between numpad keys. */
internal val PosNumpadKeyGap = 6.dp

/** Up/down denomination keys beside till-count numpad. */
internal val PosNumpadNavKeyWidth = 40.dp

/** Max width for till numpad including nav arrow column. */
internal val TillNumpadCardWidth = PosNumpadColumnWidth + PosNumpadNavKeyWidth + PosNumpadKeyGap

/**
 * Standard host size for a number pad: fixed height, width capped at the shared max
 * so keys stay consistent across login, sale, checkout, and till.
 */
internal fun Modifier.numberPadHostSize(withNavColumn: Boolean = false): Modifier {
    val maxWidth = if (withNavColumn) TillNumpadCardWidth else PosNumpadColumnWidth
    return this
        .widthIn(max = maxWidth)
        .fillMaxWidth()
        .height(PosNumpadCardHeight)
}
