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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardReturn
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.cloudstore.pos.ui.theme.PosBackground
import com.cloudstore.pos.ui.theme.PosButtonDefaults

@Composable
internal fun NumberPad(
    onDigit: (Char) -> Unit,
    onClear: () -> Unit,
    onBackspace: () -> Unit,
    onDecimal: (() -> Unit)? = null,
    onEnter: (() -> Unit)? = null,
    onUp: (() -> Unit)? = null,
    onDown: (() -> Unit)? = null,
    showClear: Boolean = true,
    enterKeyIcon: Boolean = false,
    keyCornerRadius: Dp = 20.dp,
    modifier: Modifier = Modifier,
) {
    val showNavKeys = onUp != null && onDown != null
    if (showNavKeys) {
        Row(
            modifier = modifier
                .fillMaxSize()
                .background(PosBackground),
            horizontalArrangement = Arrangement.spacedBy(PosNumpadKeyGap),
        ) {
            NumberPadKeys(
                onDigit = onDigit,
                onClear = onClear,
                onBackspace = onBackspace,
                onDecimal = onDecimal,
                onEnter = onEnter,
                showClear = showClear,
                enterKeyIcon = enterKeyIcon,
                keyCornerRadius = keyCornerRadius,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .background(PosBackground),
            )
            NumberPadNavKeys(
                onUp = onUp,
                onDown = onDown,
                keyCornerRadius = keyCornerRadius,
            )
        }
    } else {
        NumberPadKeys(
            onDigit = onDigit,
            onClear = onClear,
            onBackspace = onBackspace,
            onDecimal = onDecimal,
            onEnter = onEnter,
            showClear = showClear,
            enterKeyIcon = enterKeyIcon,
            keyCornerRadius = keyCornerRadius,
            modifier = modifier.background(PosBackground),
        )
    }
}

@Composable
private fun NumberPadKeys(
    onDigit: (Char) -> Unit,
    onClear: () -> Unit,
    onBackspace: () -> Unit,
    onDecimal: (() -> Unit)?,
    onEnter: (() -> Unit)?,
    showClear: Boolean,
    enterKeyIcon: Boolean,
    keyCornerRadius: Dp,
    modifier: Modifier = Modifier,
) {
    val keyGap = PosNumpadKeyGap
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
                        cornerRadius = keyCornerRadius,
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
                    cornerRadius = keyCornerRadius,
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    emphasis = KeyEmphasis.Secondary,
                )
            }
            if (onDecimal != null) {
                PadKey(
                    text = ".",
                    onClick = onDecimal,
                    cornerRadius = keyCornerRadius,
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    emphasis = KeyEmphasis.Secondary,
                )
            }
            PadKey(
                text = "0",
                onClick = { onDigit('0') },
                cornerRadius = keyCornerRadius,
                modifier = Modifier.weight(1f).fillMaxHeight(),
            )
            PadKey(
                text = "\u232B",
                onClick = onBackspace,
                cornerRadius = keyCornerRadius,
                modifier = Modifier.weight(1f).fillMaxHeight(),
                emphasis = KeyEmphasis.Secondary,
            )
            if (onEnter != null) {
                PadKey(
                    onClick = onEnter,
                    cornerRadius = keyCornerRadius,
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    emphasis = KeyEmphasis.Enter,
                    compactLabel = !enterKeyIcon,
                    text = if (enterKeyIcon) null else "Enter",
                    content = if (enterKeyIcon) {
                        {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.KeyboardReturn,
                                contentDescription = "Enter",
                                modifier = Modifier.fillMaxSize(0.55f),
                            )
                        }
                    } else {
                        null
                    },
                )
            }
        }
    }
}

@Composable
private fun NumberPadNavKeys(
    onUp: () -> Unit,
    onDown: () -> Unit,
    keyCornerRadius: Dp,
) {
    Column(
        modifier = Modifier
            .width(PosNumpadNavKeyWidth)
            .fillMaxHeight(),
        verticalArrangement = Arrangement.spacedBy(PosNumpadKeyGap),
    ) {
        PadKey(
            onClick = onUp,
            cornerRadius = keyCornerRadius,
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
            emphasis = KeyEmphasis.Secondary,
            content = {
                Icon(
                    imageVector = Icons.Filled.KeyboardArrowUp,
                    contentDescription = "Previous denomination",
                    modifier = Modifier.fillMaxSize(0.55f),
                )
            },
        )
        PadKey(
            onClick = onDown,
            cornerRadius = keyCornerRadius,
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
            emphasis = KeyEmphasis.Secondary,
            content = {
                Icon(
                    imageVector = Icons.Filled.KeyboardArrowDown,
                    contentDescription = "Next denomination",
                    modifier = Modifier.fillMaxSize(0.55f),
                )
            },
        )
    }
}

private enum class KeyEmphasis { Primary, Secondary, Enter }

@Composable
private fun PadKey(
    onClick: () -> Unit,
    cornerRadius: Dp,
    modifier: Modifier = Modifier,
    emphasis: KeyEmphasis = KeyEmphasis.Primary,
    text: String? = null,
    compactLabel: Boolean = false,
    content: (@Composable () -> Unit)? = null,
) {
    val colors = when (emphasis) {
        KeyEmphasis.Primary -> PosButtonDefaults.numpadKey()
        KeyEmphasis.Secondary -> PosButtonDefaults.numpadKeySecondary()
        KeyEmphasis.Enter -> PosButtonDefaults.teal()
    }
    Button(
        onClick = onClick,
        modifier = modifier,
        contentPadding = PaddingValues(0.dp),
        shape = RoundedCornerShape(cornerRadius),
        colors = colors,
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
            when {
                content != null -> content()
                text != null -> {
                    Text(
                        text = text,
                        style = if (compactLabel) {
                            MaterialTheme.typography.titleSmall
                        } else {
                            MaterialTheme.typography.titleLarge
                        },
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
    }
}
