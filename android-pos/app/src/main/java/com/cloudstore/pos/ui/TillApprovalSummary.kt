package com.cloudstore.pos.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.cloudstore.pos.domain.pricing.formatMoney
import com.cloudstore.pos.ui.theme.PosCardDefaults
import kotlin.math.abs

private const val MONEY_EPSILON = 0.005

enum class TillSummaryContext {
    Opening,
    Closing,
}

fun approvalTimerText(secondsRemaining: Int?): String? {
    if (secondsRemaining == null || secondsRemaining < 0) return null
    val mins = secondsRemaining / 60
    val secs = secondsRemaining % 60
    return "Expires in %d:%02d".format(mins, secs)
}

fun buildTillApprovalSummaryLine(
    cashMode: String?,
    counted: Double?,
    expected: Double?,
    variance: Double?,
    context: TillSummaryContext = TillSummaryContext.Opening,
): String? {
    if (cashMode.isNullOrBlank()) return null

    val isCreditOnly = cashMode == "credit_only"
    val isClosing = context == TillSummaryContext.Closing

    if (isCreditOnly) {
        return if (isClosing) {
            "Card only · Supervisor must approve close"
        } else {
            "Card only · Card payments only"
        }
    }

    val parts = mutableListOf("Cash + card")

    if (isClosing) {
        counted?.let { parts.add("${formatMoney(it)} counted") }
        if (variance != null && abs(variance) > MONEY_EPSILON) {
            val sign = if (variance >= 0) "+" else ""
            parts.add("$sign${formatMoney(variance)}")
        }
    } else {
        counted?.let { parts.add("Opening ${formatMoney(it)}") }
        if (
            expected != null &&
                (counted == null || abs(expected - counted) > MONEY_EPSILON)
        ) {
            parts.add("(target ${formatMoney(expected)})")
        }
        if (variance != null && abs(variance) > MONEY_EPSILON) {
            val sign = if (variance >= 0) "+" else ""
            parts.add("$sign${formatMoney(variance)}")
        }
    }

    return parts.joinToString(" · ")
}

@Composable
fun TillApprovalSummaryCard(
    cashMode: String?,
    expectedOpeningFloat: Double?,
    openingCountedFloat: Double?,
    openingVariance: Double?,
    modifier: Modifier = Modifier,
    context: TillSummaryContext = TillSummaryContext.Opening,
) {
    val summary = buildTillApprovalSummaryLine(
        cashMode = cashMode,
        counted = openingCountedFloat,
        expected = expectedOpeningFloat,
        variance = openingVariance,
        context = context,
    ) ?: return

    Card(
        modifier = modifier.fillMaxWidth(),
        colors = PosCardDefaults.contentColors(),
        elevation = PosCardDefaults.elevation(),
    ) {
        Text(
            text = summary,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
        )
    }
}
