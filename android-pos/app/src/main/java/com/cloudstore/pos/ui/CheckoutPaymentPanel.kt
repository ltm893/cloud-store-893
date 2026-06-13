package com.cloudstore.pos.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.cloudstore.pos.data.CheckoutPayment
import com.cloudstore.pos.ui.theme.PosButtonDefaults
import com.cloudstore.pos.ui.theme.PosCardDefaults
import com.cloudstore.pos.ui.theme.PosPrimary
import com.cloudstore.pos.ui.theme.PosText

@Composable
fun PaymentsReceivedSection(
    payments: List<CheckoutPayment>,
    onRemovePayment: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val paymentsScroll = rememberScrollState()
    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            text = "Payments received",
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
        )
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 120.dp)
                .padding(top = 4.dp)
                .verticalScroll(paymentsScroll),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            payments.forEachIndexed { index, payment ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = PosCardDefaults.nestedColors(),
                    elevation = PosCardDefaults.elevation(),
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = "${index + 1}. ${paymentMethodLabel(payment.method)} · ${formatMoney(payment.amount)}",
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold,
                            )
                            payment.changeGiven?.takeIf { it > 0.005 }?.let { change ->
                                Text(
                                    text = "Change ${formatMoney(change)}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                        if (payment.method != "card") {
                            TextButton(
                                onClick = { onRemovePayment(index) },
                                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 0.dp),
                            ) {
                                Text("Remove")
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun CheckoutPaymentPanel(
    saleTotal: Double,
    balanceDue: Double,
    payments: List<CheckoutPayment>,
    backEnabled: Boolean,
    cashEnabled: Boolean = true,
    creditOnlyPayments: Boolean = false,
    showCardOnFileButton: Boolean,
    amountInput: String,
    onAmountChange: (String) -> Unit,
    onFillRemaining: () -> Unit,
    onApplyPayment: (String) -> Unit,
    onPayCardOnFile: () -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val changeTotal = checkoutChangeTotal(payments)
    val nextAmount = parseCashTendered(amountInput)
    val canPayCash = cashEnabled && balanceDue > 0.005 && nextAmount != null && nextAmount > 0.0
    val canPayCard = balanceDue > 0.005 && nextAmount != null && nextAmount > 0.0 &&
        nextAmount <= balanceDue + 0.005
    val quickBills = cashQuickDenominations(balanceDue, cashEnabled = !creditOnlyPayments)
    val maxCardEntry = if (creditOnlyPayments && balanceDue > 0.005) balanceDue else null

    Column(
        modifier = modifier.fillMaxSize(),
    ) {
        Column(modifier = Modifier.padding(PosNumpadInnerPadding)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(
                onClick = onBack,
                enabled = backEnabled,
                contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp),
            ) {
                Text("Back")
            }
            Text(
                text = "Payment",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
            )
        }
        CashAmountRow(
            label = "Sale total",
            value = formatMoney(saleTotal),
        )
        CashAmountRow(
            label = "Balance due",
            value = formatMoney(balanceDue),
            emphasize = true,
            valueColor = if (balanceDue > 0.005) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.tertiary
            },
        )
        if (changeTotal > 0.005) {
            CashAmountRow(
                label = "Change from payments",
                value = formatMoney(changeTotal),
                valueColor = MaterialTheme.colorScheme.tertiary,
            )
        }
        CashAmountRow(
            label = "Amount entered",
            value = if (amountInput.isBlank()) "—" else "\$$amountInput",
            modifier = Modifier.padding(top = 2.dp),
        )
        nextAmount?.let { tendered ->
            val changeDelta = roundMoney(tendered - balanceDue)
            val changeLabel = when {
                changeDelta < -0.005 -> "Still need"
                changeDelta < 0.005 -> "Change"
                else -> "Give change"
            }
            val changeValue = when {
                changeDelta < -0.005 -> formatMoney(-changeDelta)
                changeDelta < 0.005 -> formatMoney(0.0)
                else -> formatMoney(changeDelta)
            }
            val changeOk = changeDelta >= 0.005
            CashAmountRow(
                label = changeLabel,
                value = changeValue,
                emphasize = changeOk,
                valueColor = when {
                    changeDelta < -0.005 -> MaterialTheme.colorScheme.error
                    changeOk -> MaterialTheme.colorScheme.tertiary
                    else -> null
                },
            )
        }
        }
        Spacer(modifier = Modifier.weight(1f))
        Column(
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(
                        start = PosNumpadInnerPadding,
                        end = PosNumpadInnerPadding,
                        top = 4.dp,
                    ),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                OutlinedButton(
                    onClick = onFillRemaining,
                    enabled = balanceDue > 0.005,
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(vertical = 4.dp),
                    border = BorderStroke(1.dp, PosPrimary),
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = PosText,
                    ),
                ) {
                    Text(formatMoney(balanceDue), style = MaterialTheme.typography.labelMedium)
                }
                quickBills.forEach { bill ->
                    OutlinedButton(
                        onClick = { onAmountChange(formatCashEntry(bill.toDouble())) },
                        modifier = Modifier.weight(1f),
                        contentPadding = PaddingValues(vertical = 4.dp),
                        border = BorderStroke(1.dp, PosPrimary),
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = PosText,
                        ),
                    ) {
                        Text("\$$bill", style = MaterialTheme.typography.labelMedium)
                    }
                }
            }
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(PosNumpadCardHeight),
            ) {
                NumberPad(
                    onDigit = { d ->
                        onAmountChange(appendCashDigitLimited(amountInput, d, maxCardEntry))
                    },
                    onClear = { onAmountChange("") },
                    onBackspace = { onAmountChange(amountInput.dropLast(1)) },
                    onDecimal = {
                        onAmountChange(appendCashDigitLimited(amountInput, '.', maxCardEntry))
                    },
                    showClear = false,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(PosNumpadInnerPadding),
                )
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(
                        start = PosNumpadInnerPadding,
                        end = PosNumpadInnerPadding,
                        top = 4.dp,
                    ),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                if (cashEnabled) {
                    Button(
                        onClick = { onApplyPayment("cash") },
                        enabled = canPayCash,
                        colors = PosButtonDefaults.teal(),
                        modifier = Modifier.weight(1f),
                        contentPadding = PaddingValues(vertical = 6.dp),
                    ) {
                        Text("Cash", style = MaterialTheme.typography.labelMedium)
                    }
                }
                Button(
                    onClick = { onApplyPayment("card") },
                    enabled = canPayCard,
                    colors = PosButtonDefaults.teal(),
                    modifier = Modifier.weight(if (cashEnabled) 1f else 2f),
                    contentPadding = PaddingValues(vertical = 6.dp),
                ) {
                    Text("Charge Card", style = MaterialTheme.typography.labelMedium)
                }
                if (showCardOnFileButton) {
                    Button(
                        onClick = onPayCardOnFile,
                        enabled = canPayCard,
                        colors = PosButtonDefaults.teal(),
                        modifier = Modifier.weight(1f),
                        contentPadding = PaddingValues(vertical = 6.dp),
                    ) {
                        Text("CardOnFile", style = MaterialTheme.typography.labelMedium)
                    }
                }
            }
        }
    }
}

@Composable
internal fun CashAmountRow(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    emphasize: Boolean = false,
    valueColor: Color? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = value,
            style = if (emphasize) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyLarge,
            fontWeight = if (emphasize) FontWeight.Bold else FontWeight.Medium,
            color = valueColor ?: MaterialTheme.colorScheme.onSurface,
        )
    }
}
