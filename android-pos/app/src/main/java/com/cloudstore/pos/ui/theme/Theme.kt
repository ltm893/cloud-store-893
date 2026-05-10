package com.cloudstore.pos.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColorScheme = darkColorScheme(
    primary          = PosPrimaryDark,
    onPrimary        = Color.White,
    secondary        = PosAccentDark,
    onSecondary      = Color.White,
    background       = PosBackgroundDark,
    onBackground     = Color.White,
    surface          = PosHighlightDark,
    onSurface        = Color.White,
    surfaceVariant   = PosLongPressDark,
    onSurfaceVariant = Color.White,
)

private val LightColorScheme = lightColorScheme(
    primary          = PosPrimary,
    onPrimary        = Color.White,
    secondary        = PosAccent,
    onSecondary      = Color.White,
    background       = PosBackground,
    onBackground     = Color(0xFF1C1B1F),
    surface          = PosHighlight,
    onSurface        = Color(0xFF1C1B1F),
    surfaceVariant   = PosLongPress,
    onSurfaceVariant = Color(0xFF1C1B1F),
)

@Composable
fun CloudStorePosTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

    MaterialTheme(
        colorScheme = colorScheme,
        typography  = PosTypography,
        content     = content,
    )
}
