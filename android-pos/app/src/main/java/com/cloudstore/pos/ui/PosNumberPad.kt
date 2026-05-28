package com.cloudstore.pos.ui

import androidx.compose.foundation.background
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
import com.cloudstore.pos.ui.theme.PosBackground
import com.cloudstore.pos.ui.theme.PosButtonDefaults

@Composable
internal fun NumberPad(
    onDigit: (Char) -> Unit,
    onClear: () -> Unit,
    onBackspace: () -> Unit,
    onDecimal: (() -> Unit)? = null,
    showClear: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val keyGap = PosNumpadKeyGap
    Column(
        modifier = modifier.background(PosBackground),
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
            if (showClear) {
                PadKey(
                    text = "C",
                    onClick = onClear,
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    emphasis = KeyEmphasis.Secondary,
                )
            }
            if (onDecimal != null) {
                PadKey(
                    text = ".",
                    onClick = onDecimal,
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    emphasis = KeyEmphasis.Secondary,
                )
            }
            PadKey(
                text = "0",
                onClick = { onDigit('0') },
                modifier = Modifier.weight(1f).fillMaxHeight(),
            )
            PadKey(
                text = "\u232B",
                onClick = onBackspace,
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
) {
    val colors = when (emphasis) {
        KeyEmphasis.Primary -> PosButtonDefaults.numpadKey()
        KeyEmphasis.Secondary -> PosButtonDefaults.numpadKeySecondary()
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
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}
