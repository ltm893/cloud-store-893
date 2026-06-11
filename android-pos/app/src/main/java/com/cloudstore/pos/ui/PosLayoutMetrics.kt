package com.cloudstore.pos.ui

import androidx.compose.ui.unit.dp

/** Right-column width for numpad / payment / customer-find card (75% of original 360dp). */
internal val PosNumpadColumnWidth = 270.dp

/** Fixed height of the cream numpad card on the sale screen (75% of original 296dp). */
internal val PosNumpadCardHeight = 222.dp

/** Inner padding around [NumberPad] inside the numpad card (75% of original 12dp). */
internal val PosNumpadInnerPadding = 9.dp

/** Gap between numpad keys (75% of original 8dp). */
internal val PosNumpadKeyGap = 6.dp

/** Up/down denomination keys beside till-count numpad. */
internal val PosNumpadNavKeyWidth = 40.dp

/** Till numpad card width including nav arrow column. */
internal val TillNumpadCardWidth = PosNumpadColumnWidth + PosNumpadNavKeyWidth + PosNumpadKeyGap
