package com.cloudstore.pos.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColorScheme = darkColorScheme(
    primary = PosPrimaryDark,
    onPrimary = Color.White,
    primaryContainer = PosLongPressDark,
    onPrimaryContainer = Color.White,
    secondary = PosAccentDark,
    onSecondary = Color.White,
    secondaryContainer = PosHighlightDark,
    onSecondaryContainer = Color.White,
    tertiary = PosAccentDark,
    onTertiary = Color.White,
    background = PosBackgroundDark,
    onBackground = PosTextDark,
    surface = PosPanelDark,
    onSurface = PosTextDark,
    surfaceDim = PosPanelDark,
    surfaceBright = PosPanelDark,
    surfaceContainerLowest = PosPanelDark,
    surfaceContainerLow = PosPanelDark,
    surfaceContainer = PosPanelDark,
    surfaceContainerHigh = PosPanelDark,
    surfaceContainerHighest = PosPanelDark,
    surfaceVariant = PosLongPressDark,
    onSurfaceVariant = PosMutedDark,
    outline = PosBorderDark,
    outlineVariant = PosBorderDark,
    error = PosDangerDark,
    onError = Color.White,
)

private val LightColorScheme = lightColorScheme(
    primary = PosPrimary,
    onPrimary = Color.White,
    primaryContainer = PosLongPress,
    onPrimaryContainer = PosPrimary,
    secondary = PosAccent,
    onSecondary = Color.White,
    secondaryContainer = PosHighlight,
    onSecondaryContainer = PosAccent,
    tertiary = PosAccent,
    onTertiary = Color.White,
    background = PosBackground,
    onBackground = PosText,
    // Cards (Scan/Add, Current Sale, Sale total, payment panel): light cyan like admin table headers.
    surface = PosHighlight,
    onSurface = PosText,
    surfaceDim = PosHighlight,
    surfaceBright = PosHighlight,
    surfaceContainerLowest = PosHighlight,
    surfaceContainerLow = PosHighlight,
    surfaceContainer = PosHighlight,
    surfaceContainerHigh = PosHighlight,
    surfaceContainerHighest = PosHighlight,
    surfaceVariant = PosLongPress,
    onSurfaceVariant = PosMuted,
    outline = PosBorder,
    outlineVariant = PosBorder,
    error = PosDanger,
    onError = Color.White,
)

@Composable
fun CloudStorePosTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

    MaterialTheme(
        colorScheme = colorScheme,
        typography = PosTypography,
        content = content,
    )
}
