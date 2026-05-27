package com.cloudstore.pos.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

@Composable
internal fun NumberPad(
    onDigit: (Char) -> Unit,
    onClear: () -> Unit,
    onBackspace: () -> Unit,
    onDecimal: (() -> Unit)? = null,
    compact: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val keyGap = if (compact) 6.dp else 8.dp
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(keyGap),
    ) {
        listOf("123", "456", "789").forEach { rowDigits ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                horizontalArrangement = Arrangement.spacedBy(keyGap),
            ) {
                rowDigits.forEach { digit ->
                    PadKey(
                        text = digit.toString(),
                        onClick = { onDigit(digit) },
                        compact = compact,
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight(),
                    )
                }
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
            horizontalArrangement = Arrangement.spacedBy(keyGap),
        ) {
            PadKey(
                text = "C",
                onClick = onClear,
                compact = compact,
                modifier = Modifier.weight(1f).fillMaxHeight(),
                emphasis = KeyEmphasis.Secondary,
            )
            if (onDecimal != null) {
                PadKey(
                    text = ".",
                    onClick = onDecimal,
                    compact = compact,
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    emphasis = KeyEmphasis.Secondary,
                )
            }
            PadKey(
                text = "0",
                onClick = { onDigit('0') },
                compact = compact,
                modifier = Modifier.weight(1f).fillMaxHeight(),
            )
            PadKey(
                text = "\u232B",
                onClick = onBackspace,
                compact = compact,
                modifier = Modifier.weight(1f).fillMaxHeight(),
                emphasis = KeyEmphasis.Secondary,
            )
        }
    }
}

private enum class KeyEmphasis { Primary, Secondary }

@Composable
private fun PadKey(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    emphasis: KeyEmphasis = KeyEmphasis.Primary,
    compact: Boolean = false,
) {
    val colors = when (emphasis) {
        KeyEmphasis.Primary -> androidx.compose.material3.ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.secondaryContainer,
            contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
        )
        KeyEmphasis.Secondary -> androidx.compose.material3.ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
            contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
    Button(
        onClick = onClick,
        modifier = modifier,
        contentPadding = PaddingValues(0.dp),
        colors = colors,
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
            Text(
                text = text,
                style = if (compact) {
                    MaterialTheme.typography.titleLarge
                } else {
                    MaterialTheme.typography.headlineMedium
                },
                fontWeight = FontWeight.Bold,
            )
        }
    }
}
