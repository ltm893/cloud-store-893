package com.cloudstore.pos.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.cloudstore.pos.data.TillDenomination
import com.cloudstore.pos.domain.pricing.formatMoney
import com.cloudstore.pos.domain.pricing.roundMoney
import com.cloudstore.pos.ui.theme.PosBackground
import com.cloudstore.pos.ui.theme.PosButtonDefaults
import com.cloudstore.pos.ui.theme.PosCardDefaults
import com.cloudstore.pos.ui.theme.PosPrimary
import kotlin.math.abs

private const val TillDenomPanelWeight = 0.63f
private const val TillGutterWeight = 0.02f
private const val TillNumpadPanelWeight = 0.35f

/** Fixed space above and below denom list / numpad within each panel. */
private val TillPanelEdgeSpacer = 12.dp

/** Denomination row sizing (20% taller than prior 5dp / 34dp / 3dp values). */
private val TillDenomRowVerticalPadding = 6.dp
private val TillDenomRowSpacing = 4.dp
private val TillDenomRowMinHeight = 41.dp

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun OpeningTillScreen(
    expectedOpeningFloat: Double?,
    denominations: List<TillDenomination>,
    counts: Map<String, String>,
    selectedDenominationId: String?,
    countedTotal: Double,
    status: String,
    submitting: Boolean,
    onSelectDenomination: (String) -> Unit,
    onDigit: (Char) -> Unit,
    onClearCount: () -> Unit,
    onBackspaceCount: () -> Unit,
    onPreviousDenomination: () -> Unit,
    onNextDenomination: () -> Unit,
    onSubmit: () -> Unit,
    onNoCashToday: () -> Unit,
    onCancel: () -> Unit,
    screenTitle: String = "Count opening till",
    referenceLabel: String = "Target",
    defaultStatus: String = "Count opening till",
    submitButtonText: String = "Submit Till Count",
    secondaryButtonText: String = "Credit Cards Only",
    showSecondaryButton: Boolean = true,
    headerHint: String = "Tap row → count · ↑↓ to move",
    requireExactMatch: Boolean = true,
) {
    val denomScroll = rememberScrollState()
    val selectedBringIntoView = remember { BringIntoViewRequester() }
    val selected = denominations.find { it.id == selectedDenominationId }
    val selectedCount = selected?.id?.let { counts[it].orEmpty() }.orEmpty()
    val targetReached = expectedOpeningFloat?.let { expected ->
        abs(countedTotal - expected) < 0.005
    } == true
    val variance = expectedOpeningFloat?.let { roundMoney(countedTotal - it) }
    val hasVariance = variance != null && abs(variance) > 0.005
    val hasCounts = denominations.any { denom ->
        (counts[denom.id]?.toIntOrNull() ?: 0) > 0
    }
    val canSubmit = targetReached || (!requireExactMatch && hasCounts)
    val summaryLine = buildString {
        if (expectedOpeningFloat != null) {
            append("$referenceLabel ${formatMoney(expectedOpeningFloat)}")
        }
        append(" · Total ${formatMoney(countedTotal)}")
        if (!requireExactMatch && hasVariance && variance != null) {
            val sign = if (variance >= 0) "+" else ""
            append(" · Variance $sign${formatMoney(variance)}")
        }
    }
    val actionStatus = when {
        submitting -> "Submitting till count…"
        status.isNotBlank() && status != "Ready" && status != defaultStatus -> status
        targetReached -> "Ready to submit"
        !requireExactMatch && hasCounts && hasVariance && variance != null -> {
            val sign = if (variance >= 0) "+" else ""
            "Variance $sign${formatMoney(variance)} — ready to submit"
        }
        !requireExactMatch && hasCounts -> "Ready to submit for approval"
        expectedOpeningFloat != null -> {
            val diff = roundMoney(expectedOpeningFloat - countedTotal)
            when {
                diff > 0.005 -> "Need ${formatMoney(diff)} more"
                diff < -0.005 -> "${formatMoney(-diff)} over target"
                else -> "Ready to submit"
            }
        }
        else -> "Enter counts for each denomination"
    }
    val selectionStatus = selected?.let { denom ->
        val count = selectedCount.toIntOrNull() ?: 0
        val lineTotal = denom.value * count
        buildString {
            append("Selected: ${denom.label}")
            append(" · ")
            append(if (selectedCount.isBlank()) "0" else selectedCount)
            append(" · ")
            append(formatMoney(lineTotal))
        }
    } ?: "Select a denomination"

    LaunchedEffect(selectedDenominationId) {
        if (selectedDenominationId != null) {
            selectedBringIntoView.bringIntoView()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(PosBackground)
            .navigationBarsPadding(),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(PosPrimary)
                .statusBarsPadding()
                .padding(start = 14.dp, end = 14.dp, top = 6.dp, bottom = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = screenTitle,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = PosBackground,
                textAlign = TextAlign.Center,
            )
            Text(
                text = summaryLine,
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
                color = PosBackground.copy(alpha = 0.92f),
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 2.dp),
            )
            Text(
                text = headerHint,
                style = MaterialTheme.typography.labelSmall,
                color = PosBackground.copy(alpha = 0.82f),
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 2.dp),
            )
        }

        Row(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(start = 8.dp, end = 8.dp, top = 6.dp)
                .padding(4.dp),
        ) {
            Column(
                modifier = Modifier
                    .weight(TillDenomPanelWeight)
                    .fillMaxHeight()
                    .padding(4.dp),
            ) {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .verticalScroll(denomScroll),
                    verticalArrangement = Arrangement.spacedBy(TillDenomRowSpacing),
                ) {
                    denominations.forEach { denom ->
                        val isSelected = denom.id == selectedDenominationId
                        TillDenominationRow(
                            denom = denom,
                            count = counts[denom.id]?.toIntOrNull() ?: 0,
                            isSelected = isSelected,
                            onSelect = { onSelectDenomination(denom.id) },
                            modifier = if (isSelected) {
                                Modifier.bringIntoViewRequester(selectedBringIntoView)
                            } else {
                                Modifier
                            },
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.weight(TillGutterWeight))

            Column(
                modifier = Modifier
                    .weight(TillNumpadPanelWeight)
                    .fillMaxHeight()
                    .padding(4.dp),
            ) {
                Spacer(modifier = Modifier.height(TillPanelEdgeSpacer))
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    contentAlignment = Alignment.Center,
                ) {
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(PosNumpadCardHeight),
                        colors = PosCardDefaults.numpadPanelColors(),
                        elevation = PosCardDefaults.elevation(),
                    ) {
                        NumberPad(
                            onDigit = onDigit,
                            onClear = onClearCount,
                            onBackspace = onBackspaceCount,
                            onUp = onPreviousDenomination,
                            onDown = onNextDenomination,
                            showClear = true,
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(PosNumpadInnerPadding),
                        )
                    }
                }
                Spacer(modifier = Modifier.height(TillPanelEdgeSpacer))
            }
        }

        TillStatusBar(
            selectionStatus = selectionStatus,
            actionStatus = actionStatus,
            modifier = Modifier.padding(start = 8.dp, end = 8.dp, top = 6.dp),
        )

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 8.dp, end = 8.dp, top = 6.dp, bottom = 8.dp)
                .padding(8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Button(
                onClick = onSubmit,
                enabled = !submitting && canSubmit,
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(vertical = 10.dp),
                colors = PosButtonDefaults.teal(),
            ) {
                Text(
                    if (submitting) "Submitting…" else submitButtonText,
                    style = MaterialTheme.typography.labelLarge,
                    textAlign = TextAlign.Center,
                )
            }
            if (showSecondaryButton) {
                Button(
                    onClick = onNoCashToday,
                    enabled = !submitting,
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(vertical = 10.dp),
                    colors = PosButtonDefaults.teal(),
                ) {
                    Text(
                        secondaryButtonText,
                        style = MaterialTheme.typography.labelLarge,
                        textAlign = TextAlign.Center,
                    )
                }
            }
            Button(
                onClick = onCancel,
                enabled = !submitting,
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(vertical = 10.dp),
                colors = PosButtonDefaults.primary(),
            ) {
                Text(
                    "Cancel",
                    style = MaterialTheme.typography.labelLarge,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

@Composable
private fun TillStatusBar(
    selectionStatus: String,
    actionStatus: String,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = PosCardDefaults.contentColors(),
        elevation = PosCardDefaults.elevation(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = selectionStatus,
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = actionStatus,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.End,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun TillDenominationRow(
    denom: TillDenomination,
    count: Int,
    isSelected: Boolean,
    onSelect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val lineTotal = denom.value * count
    Card(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect),
        colors = PosCardDefaults.contentColors(),
        elevation = PosCardDefaults.elevation(),
        border = if (isSelected) {
            BorderStroke(2.dp, PosPrimary)
        } else {
            null
        },
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = TillDenomRowMinHeight)
                .padding(horizontal = 8.dp, vertical = TillDenomRowVerticalPadding),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = denom.label,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = if (count > 0) "× $count" else "—",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
                color = if (isSelected) PosPrimary else MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.padding(horizontal = 4.dp),
            )
            Text(
                text = formatMoney(lineTotal),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.width(52.dp),
                textAlign = TextAlign.End,
            )
        }
    }
}

fun sumTillCounts(denominations: List<TillDenomination>, counts: Map<String, String>): Double {
    var total = 0.0
    for (denom in denominations) {
        val count = counts[denom.id]?.toIntOrNull() ?: 0
        if (count > 0) {
            total += denom.value * count
        }
    }
    return roundMoney(total)
}
