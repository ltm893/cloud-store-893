package com.cloudstore.pos.ui

import androidx.compose.foundation.layout.Column
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
import com.cloudstore.pos.ui.theme.PosCardDefaults
import kotlin.math.abs

@Composable
fun TillApprovalSummaryCard(
    cashMode: String?,
    expectedOpeningFloat: Double?,
    openingCountedFloat: Double?,
    openingVariance: Double?,
    modifier: Modifier = Modifier,
) {
    if (cashMode.isNullOrBlank()) return

    val isCreditOnly = cashMode == "credit_only"
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = PosCardDefaults.contentColors(),
        elevation = PosCardDefaults.elevation(),
    ) {
        Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
            Text(
                text = if (isCreditOnly) "Card only" else "Cash + card",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                text = if (isCreditOnly) {
                    "No cash drawer for this shift — card payments only."
                } else {
                    "Supervisor is approving cash drawer opening and card payments."
                },
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 6.dp),
            )
            if (!isCreditOnly && openingCountedFloat != null) {
                Text(
                    text = "Opening counted: ${formatMoney(openingCountedFloat)}",
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp),
                )
                if (expectedOpeningFloat != null) {
                    Text(
                        text = "Target float: ${formatMoney(expectedOpeningFloat)}",
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                if (openingVariance != null && abs(openingVariance) > 0.005) {
                    val sign = if (openingVariance >= 0) "+" else ""
                    Text(
                        text = "Variance: $sign${formatMoney(openingVariance)}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 4.dp),
                    )
                }
            }
        }
    }
}
