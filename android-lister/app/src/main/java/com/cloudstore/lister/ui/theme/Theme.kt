package com.cloudstore.lister.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = ListerPrimary,
    onPrimary = Color.White,
    secondary = ListerAccent,
    onSecondary = Color.White,
    background = ListerBackground,
    onBackground = ListerText,
    surface = ListerHighlight,
    onSurface = ListerText,
    surfaceVariant = ListerPanel,
    onSurfaceVariant = ListerMuted,
    error = ListerDanger,
)

private val DarkColors = darkColorScheme(
    primary = ListerAccent,
    onPrimary = Color.White,
    secondary = ListerPrimary,
    background = Color(0xFF1A1210),
    surface = Color(0xFF1E3540),
)

@Composable
fun CloudStoreListerTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = LightColors,
        content = content,
    )
}
