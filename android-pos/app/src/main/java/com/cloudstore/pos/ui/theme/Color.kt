package com.cloudstore.pos.ui.theme

import androidx.compose.ui.graphics.Color

// Palette aligned with public/admin/admin.css (--bg, --panel, --accent, --accent-2, etc.)

/** Page background — --bg #faf3df */
val PosBackground = Color(0xFFFAF3DF)

/** Cards, top bar, drawer — --panel #ffffff */
val PosPanel = Color(0xFFFFFFFF)

/** Primary brand — --accent #872434 */
val PosPrimary = Color(0xFF872434)

/** Secondary / links — --accent-2 #114b5f */
val PosAccent = Color(0xFF114B5F)

/** Body text — --text #1f2937 */
val PosText = Color(0xFF1F2937)

/** Muted labels — --muted #6b7280 */
val PosMuted = Color(0xFF6B7280)

/** Borders — --border #e5e7eb */
val PosBorder = Color(0xFFE5E7EB)

/** Errors — --danger #b42318 */
val PosDanger = Color(0xFFB42318)

/** Table headers, numpad keys — #a8d5d1 */
val PosHighlight = Color(0xFFA8D5D1)

/** Content cards (Scan/Add, Current Sale, Sale total) — #a8d5d1 at 25% on cream page */
val PosHighlightPanel = PosHighlight.copy(alpha = 0.25f)

/** Active / selected row — #f5e7e9 */
val PosLongPress = Color(0xFFF5E7E9)

// Dark theme (lifted variants for contrast on dark surfaces)
val PosBackgroundDark = Color(0xFF1A1210)
val PosPanelDark = Color(0xFF2A2420)
val PosPrimaryDark = Color(0xFFD4606F)
val PosAccentDark = Color(0xFF4A9EB5)
val PosTextDark = Color(0xFFF3F4F6)
val PosMutedDark = Color(0xFF9CA3AF)
val PosBorderDark = Color(0xFF4B5563)
val PosDangerDark = Color(0xFFF87171)
val PosHighlightDark = Color(0xFF1E3540)
val PosLongPressDark = Color(0xFF3A1F22)
