package com.cloudstore.lister.ui.tabs

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.cloudstore.lister.data.InventoryProduct
import com.cloudstore.lister.domain.InventoryDisplayLogic
import com.cloudstore.lister.ui.theme.ListerDanger
import com.cloudstore.lister.ui.theme.ListerHighlight
import com.cloudstore.lister.ui.theme.ListerMuted

@Composable
fun ProductCard(product: InventoryProduct) {
    val stockLabel = InventoryDisplayLogic.stockLabel(
        product.trackInventory,
        product.quantityOnHand,
        product.inStock,
        product.lowStock,
    )
    val stockEmphasis = product.lowStock || !product.inStock

    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(ListerHighlight)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        ListerFieldRow(label = "Name:", value = product.name, valueBold = true)
        ListerFieldDivider()
        ListerFieldRow(label = "Type:", value = product.productType?.takeIf { it.isNotBlank() } ?: "—")
        ListerFieldDivider()
        ListerFieldRow(
            label = "Manufacturer:",
            value = product.manufacturer?.takeIf { it.isNotBlank() } ?: "—",
        )
        ListerFieldDivider()
        ListerFieldRow(label = "Product ID:", value = product.id.toString())
        ListerFieldDivider()
        ListerFieldRow(
            label = "Barcode:",
            value = product.barcode?.takeIf { it.isNotBlank() } ?: "—",
            monospace = true,
        )
        ListerFieldDivider()
        ListerFieldRow(
            label = "Price:",
            value = InventoryDisplayLogic.priceDetail(
                product.regularPrice,
                product.onSale,
                product.salePrice,
            ),
        )
        ListerFieldDivider()
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Top,
        ) {
            Text("Stock:", style = MaterialTheme.typography.bodyMedium, color = ListerMuted)
            Spacer(Modifier.weight(1f))
            Text(
                text = stockLabel,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = if (stockEmphasis) ListerDanger else MaterialTheme.colorScheme.onBackground,
                textAlign = TextAlign.End,
            )
        }
        if (product.trackInventory && product.reorderPoint != null) {
            ListerFieldDivider()
            ListerFieldRow(label = "Reorder at:", value = product.reorderPoint.toString())
        }
    }
}

@Composable
internal fun ListerFieldRow(
    label: String,
    value: String,
    valueBold: Boolean = false,
    monospace: Boolean = false,
) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = ListerMuted)
        Spacer(Modifier.weight(1f))
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = if (valueBold) FontWeight.Bold else FontWeight.Normal,
            fontFamily = if (monospace) FontFamily.Monospace else FontFamily.Default,
            textAlign = TextAlign.End,
            modifier = Modifier.padding(start = 8.dp),
        )
    }
}

@Composable
internal fun ListerFieldDivider() {
    HorizontalDivider(
        modifier = Modifier.padding(vertical = 8.dp),
        color = Color.White.copy(alpha = 0.55f),
    )
}
