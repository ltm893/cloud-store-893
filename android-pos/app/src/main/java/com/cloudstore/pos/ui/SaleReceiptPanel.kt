package com.cloudstore.pos.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.cloudstore.pos.domain.checkout.paymentMethodLabel
import com.cloudstore.pos.domain.pricing.formatMoney
import com.cloudstore.pos.domain.receipt.ReceiptLine
import com.cloudstore.pos.domain.receipt.SaleReceipt
import com.cloudstore.pos.ui.theme.PosBorder
import com.cloudstore.pos.ui.theme.PosButtonDefaults
import com.cloudstore.pos.ui.theme.PosPanel

@Composable
fun SaleReceiptContent(
    receipt: SaleReceipt,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .fillMaxHeight(),
    ) {
        Text(
            text = "Receipt",
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            fontWeight = FontWeight.Bold,
        )
        Text(
            text = receipt.orderLabel(),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(top = 2.dp),
        )
        Text(
            text = receipt.formattedTimestamp(),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (receipt.queuedOffline) {
            Text(
                text = "Will sync when back online",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.tertiary,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
        receipt.customerName?.let { name ->
            Text(
                text = name,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
        }

        LazyColumn(
            modifier = Modifier
                .weight(1f)
                .padding(top = 6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            items(receipt.lines) { line ->
                ReceiptLineRow(line = line)
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp),
        ) {
            HorizontalDivider(color = PosBorder, thickness = 1.dp)
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(PosPanel)
                    .padding(horizontal = 4.dp, vertical = 6.dp),
            ) {
                ReceiptTotalsSection(receipt = receipt)
                if (receipt.payments.isNotEmpty()) {
                    ReceiptPaymentsSection(receipt = receipt)
                }
            }
        }
    }
}

@Composable
private fun ReceiptLineRow(line: ReceiptLine) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.Top,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "${line.quantity} × ${line.name}",
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                text = "ID ${line.productId}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text(
            text = formatMoney(line.lineTotal),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun ReceiptTotalsSection(receipt: SaleReceipt) {
    ReceiptTotalRow(label = "Items", value = receipt.itemCount.toString())
    if (receipt.customerLinked) {
        ReceiptTotalRow(label = "Subtotal", value = formatMoney(receipt.shelfSubtotal))
        ReceiptTotalRow(
            label = "Discount",
            value = if (receipt.showMemberDiscount) {
                "−${formatMoney(receipt.memberDiscount)}"
            } else {
                formatMoney(0.0)
            },
        )
        ReceiptTotalRow(label = "PreTax", value = formatMoney(receipt.subtotal))
    } else {
        ReceiptTotalRow(label = "Subtotal", value = formatMoney(receipt.subtotal))
    }
    ReceiptTotalRow(
        label = "Savings",
        value = if (receipt.savings > 0.005) "−${formatMoney(receipt.savings)}" else formatMoney(0.0),
    )
    ReceiptTotalRow(label = "Tax", value = formatMoney(receipt.tax))
    if (receipt.grandTotal - receipt.collectedTotal > 0.005) {
        ReceiptTotalRow(
            label = "Cash rounding",
            value = "−${formatMoney(receipt.grandTotal - receipt.collectedTotal)}",
        )
    }
    ReceiptTotalRow(
        label = if (receipt.grandTotal - receipt.collectedTotal > 0.005) "Collected" else "Total",
        value = formatMoney(receipt.collectedTotal),
        emphasize = true,
    )
    if (receipt.grandTotal - receipt.collectedTotal > 0.005) {
        ReceiptTotalRow(
            label = "Register total",
            value = formatMoney(receipt.grandTotal),
        )
    }
}

@Composable
private fun ReceiptPaymentsSection(receipt: SaleReceipt) {
    Text(
        text = "Payment",
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 6.dp, bottom = 2.dp),
    )
    receipt.payments.forEach { payment ->
        val tendered = payment.tenderedAmount ?: payment.amount
        Text(
            text = "${paymentMethodLabel(payment.method)} ${formatMoney(tendered)}",
            style = MaterialTheme.typography.bodySmall,
        )
        payment.changeGiven?.takeIf { it > 0.005 }?.let { change ->
            Text(
                text = "Change given: ${formatMoney(change)}",
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.tertiary,
            )
        }
    }
    if (receipt.changeTotal > 0.005 && receipt.payments.none { (it.changeGiven ?: 0.0) > 0.005 }) {
        Text(
            text = "Change given: ${formatMoney(receipt.changeTotal)}",
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.tertiary,
        )
    }
}

@Composable
private fun ReceiptTotalRow(
    label: String,
    value: String,
    emphasize: Boolean = false,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 1.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = label,
            style = if (emphasize) {
                MaterialTheme.typography.titleSmall
            } else {
                MaterialTheme.typography.bodySmall
            },
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = value,
            style = if (emphasize) {
                MaterialTheme.typography.titleSmall
            } else {
                MaterialTheme.typography.bodySmall
            },
            fontWeight = if (emphasize) FontWeight.Bold else FontWeight.Medium,
            color = if (emphasize) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurface
            },
        )
    }
}

@Composable
fun ReceiptActionPanel(
    onPrint: () -> Unit,
    modifier: Modifier = Modifier,
    printEnabled: Boolean = true,
) {
    Column(
        modifier = modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.Bottom),
    ) {
        Button(
            onClick = onPrint,
            enabled = printEnabled,
            colors = PosButtonDefaults.teal(),
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp),
        ) {
            Text("Print Receipt")
        }
    }
}
