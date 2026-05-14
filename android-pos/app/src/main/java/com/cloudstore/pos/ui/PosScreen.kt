package com.cloudstore.pos.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Divider
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.cloudstore.pos.BuildConfig
import com.cloudstore.pos.data.CartItem
import com.cloudstore.pos.data.StoreCustomer
import kotlin.math.abs
import java.util.Locale

@Composable
fun PosScreen(viewModel: PosViewModel) {
    val state = viewModel.state.value
    val context = LocalContext.current
    var scannerOpen by remember { mutableStateOf(false) }
    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        )
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasCameraPermission = granted
        scannerOpen = granted
    }

    LaunchedEffect(state.isAuthenticated) {
        if (!state.isAuthenticated) scannerOpen = false
    }

    var payPanelVisible by remember { mutableStateOf(false) }
    var statusPanelExpanded by remember { mutableStateOf(false) }

    LaunchedEffect(state.isAuthenticated) {
        if (!state.isAuthenticated) payPanelVisible = false
    }
    LaunchedEffect(state.cart.isEmpty(), state.isAuthenticated) {
        if (state.isAuthenticated && state.cart.isEmpty()) payPanelVisible = false
    }
    LaunchedEffect(state.status) {
        if (state.status.startsWith("Sale complete")) payPanelVisible = false
    }

    if (!state.isAuthenticated) {
        CashierLogin(
            pinInput = state.pinInput,
            status = state.status,
            onPinChange = viewModel::setPinInput,
            onUnlock = viewModel::unlock,
        )
        return
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .navigationBarsPadding()
            .padding(horizontal = 14.dp, vertical = 8.dp),
    ) {
        val salesFeeRate = BuildConfig.POS_SALES_FEE_RATE.toDoubleOrNull() ?: 0.0
        val taxRate = BuildConfig.POS_TAX_RATE.toDoubleOrNull() ?: 0.0

        // ── Title (centered) + status (top-end) ───────────────────────────────
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 0.dp, bottom = 2.dp),
        ) {
            Text(
                text = "Cloud Store 893 POS",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
                textAlign = TextAlign.Center,
                modifier = Modifier.align(Alignment.Center),
            )
            Column(
                horizontalAlignment = Alignment.End,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .width(360.dp),
            ) {
                TextButton(
                    onClick = { statusPanelExpanded = !statusPanelExpanded },
                    contentPadding = PaddingValues(horizontal = 10.dp, vertical = 2.dp),
                ) {
                    Text(
                        text = if (statusPanelExpanded) "Hide status" else "Show status",
                        fontWeight = FontWeight.SemiBold,
                    )
                }
                if (statusPanelExpanded) {
                    if (state.status != "Ready" && state.status.isNotBlank()) {
                        Text(
                            text = state.status,
                            style = MaterialTheme.typography.bodyMedium,
                            textAlign = TextAlign.End,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 2.dp, bottom = 4.dp),
                        )
                    }
                    OfflineQueueStatus(
                        queuedCount = state.queuedCheckoutCount,
                        onSyncQueued = viewModel::flushOfflineQueue,
                        modifier = Modifier.padding(bottom = 4.dp),
                    )
                    TextButton(
                        onClick = viewModel::lock,
                        contentPadding = PaddingValues(horizontal = 10.dp, vertical = 2.dp),
                    ) {
                        Text("Lock", fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }

        // ── Scan & items | Number pad ─────────────────────────────────────────
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .padding(top = 0.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // ── Scan & items (left) ─────────────────────────────────────────
            Card(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight(),
            ) {
                Column(modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
                    OutlinedTextField(
                        value = state.barcodeInput,
                        onValueChange = viewModel::setBarcodeInput,
                        label = { Text("Scan or add ID") },
                        singleLine = true,
                        readOnly = true,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Number,
                            imeAction = ImeAction.Done,
                        ),
                        keyboardActions = KeyboardActions(
                            onDone = { viewModel.addByBarcode() },
                        ),
                        textStyle = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.fillMaxWidth(),
                    )

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 4.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Button(
                            onClick = {
                                if (hasCameraPermission) {
                                    scannerOpen = true
                                } else {
                                    permissionLauncher.launch(Manifest.permission.CAMERA)
                                }
                            },
                            modifier = Modifier
                                .weight(1f)
                                .height(42.dp),
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
                        ) {
                            Text("Scan", style = MaterialTheme.typography.labelLarge)
                        }
                        Button(
                            onClick = viewModel::addByBarcode,
                            modifier = Modifier
                                .weight(1f)
                                .height(42.dp),
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
                        ) {
                            Text("Add", style = MaterialTheme.typography.labelLarge)
                        }
                    }

                    Divider(modifier = Modifier.padding(vertical = 6.dp))

                    Text(
                        text = "Current Sale",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    CustomerLinkPicker(
                        customers = state.customers,
                        selectedCustomerId = state.selectedCustomerId,
                        onSelect = viewModel::setSelectedCustomerId,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 6.dp, bottom = 4.dp),
                    )
                    LazyColumn(
                        modifier = Modifier
                            .weight(1f)
                            .padding(top = 4.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(state.cart) { item ->
                            CartLineRow(
                                item = item,
                                linked893 = state.linked893Cart,
                                onRemove = { viewModel.removeCartItem(item.id) },
                            )
                        }
                    }
                }
            }

            // ── Number pad (right) ───────────────────────────────────────────
            Column(
                modifier = Modifier
                    .width(360.dp)
                    .fillMaxHeight(),
            ) {
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .fillMaxHeight(0.5f),
                ) {
                    NumberPad(
                        onDigit = { d ->
                            viewModel.setBarcodeInput(state.barcodeInput + d)
                        },
                        onClear = { viewModel.setBarcodeInput("") },
                        onBackspace = {
                            viewModel.setBarcodeInput(state.barcodeInput.dropLast(1))
                        },
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(12.dp),
                    )
                }
            }
        }

        // ── Totals + Pay (left) | payment flow under numpad (right) ────────────
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Card(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
            ) {
                Column(modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
                    SaleTotalsPanel(
                        itemCount = state.cart.sumOf { it.quantity },
                        itemSubtotalPublic = state.subtotalPreMember,
                        itemSubtotalPayable = state.subtotalPayable,
                        memberDiscountPreTax = state.memberDiscountPreTax,
                        linked893 = state.linked893Cart,
                        salesFeeRate = salesFeeRate,
                        taxRate = taxRate,
                    )
                    if (!payPanelVisible) {
                        Button(
                            onClick = { payPanelVisible = true },
                            enabled = state.cart.isNotEmpty(),
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 8.dp)
                                .height(44.dp),
                            contentPadding = PaddingValues(vertical = 4.dp),
                        ) {
                            Text("Pay")
                        }
                    }
                }
            }
            Column(
                modifier = Modifier.width(360.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                if (payPanelVisible) {
                    PaymentMethodPicker(
                        selected = state.paymentMethod,
                        onSelected = viewModel::setPaymentMethod,
                        compact = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Button(
                        onClick = viewModel::checkout,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(48.dp),
                        contentPadding = PaddingValues(vertical = 4.dp),
                    ) {
                        Text("Complete Sale")
                    }
                }
            }
        }
    }

    if (scannerOpen) {
        BarcodeScannerDialog(
            onBarcodeDetected = { code ->
                scannerOpen = false
                viewModel.addByBarcodeValue(code)
            },
            onDismiss = { scannerOpen = false },
        )
    }
}

@Composable
private fun OfflineQueueStatus(
    queuedCount: Int,
    onSyncQueued: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.End,
    ) {
        Text(
            text = "Offline queue",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.primary,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(4.dp))
        if (queuedCount > 0) {
            Text(
                text = "Queued checkouts: $queuedCount",
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.End,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedButton(
                onClick = onSyncQueued,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp),
            ) {
                Text("Sync queued")
            }
        } else {
            Text(
                text = "No queued checkouts",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.End,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun NumberPad(
    onDigit: (Char) -> Unit,
    onClear: () -> Unit,
    onBackspace: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        listOf("123", "456", "789").forEach { rowDigits ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
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
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            PadKey(
                text = "C",
                onClick = onClear,
                modifier = Modifier.weight(1f).fillMaxHeight(),
                emphasis = KeyEmphasis.Secondary,
            )
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
        KeyEmphasis.Primary -> androidx.compose.material3.ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.secondaryContainer,
            contentColor   = MaterialTheme.colorScheme.onSecondaryContainer,
        )
        KeyEmphasis.Secondary -> androidx.compose.material3.ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
            contentColor   = MaterialTheme.colorScheme.onSurfaceVariant,
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
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
private fun CustomerLinkPicker(
    customers: List<StoreCustomer>,
    selectedCustomerId: Int?,
    onSelect: (Int?) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    val label = selectedCustomerId?.let { id ->
        customers.find { it.id == id }?.let { c ->
            if (c.is893) "${c.name} (893)" else c.name
        } ?: "Customer #$id"
    } ?: "Walk-in (no customer)"

    Column(modifier = modifier) {
        Text(
            text = "Link customer",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedButton(
            onClick = { expanded = true },
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp),
            contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp),
        ) {
            Text(label, style = MaterialTheme.typography.bodyMedium, maxLines = 1)
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            DropdownMenuItem(
                text = { Text("Walk-in (no customer)") },
                onClick = {
                    onSelect(null)
                    expanded = false
                },
            )
            customers.forEach { c ->
                val text = if (c.is893) "${c.name} (893)" else c.name
                DropdownMenuItem(
                    text = { Text(text) },
                    onClick = {
                        onSelect(c.id)
                        expanded = false
                    },
                )
            }
        }
    }
}

@Composable
private fun CartLineRow(
    item: CartItem,
    linked893: Boolean,
    onRemove: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "${item.name} ×${item.quantity}",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = onRemove) {
                Text("Remove")
            }
        }
        val regLine = "Reg ${formatMoney(item.regularPrice)}" +
            if (item.onSale && item.salePrice != null) {
                " · Sale ${formatMoney(item.salePrice)}"
            } else {
                ""
            }
        Text(
            text = regLine,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        val payNote = if (linked893 && abs(item.lineSubtotalPayable - item.lineSubtotalPublic) > 0.005) {
            "Pre-tax line: ${formatMoney(item.lineSubtotalPublic)} → ${formatMoney(item.lineSubtotalPayable)} (893)"
        } else {
            "Pre-tax line: ${formatMoney(item.lineSubtotalPayable)}"
        }
        Text(
            text = payNote,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.primary,
        )
    }
}

@Composable
private fun CashierLogin(
    pinInput: String,
    status: String,
    onPinChange: (String) -> Unit,
    onUnlock: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 28.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "Cashier Sign In",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary,
        )
        Spacer(modifier = Modifier.height(12.dp))
        OutlinedTextField(
            value = pinInput,
            onValueChange = onPinChange,
            label = { Text("PIN") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.NumberPassword,
                imeAction = ImeAction.Done,
            ),
            keyboardActions = KeyboardActions(
                onDone = { onUnlock() },
            ),
            modifier = Modifier.fillMaxWidth(),
        )
        Button(onClick = onUnlock, modifier = Modifier.padding(top = 10.dp)) {
            Text("Unlock POS")
        }
        if (status != "Ready" && status.isNotBlank()) {
            Text(text = status, modifier = Modifier.padding(top = 8.dp))
        }
    }
}

/**
 * Line totals for the cashier. [salesFeeRate] and [taxRate] come from `BuildConfig`.
 * Fee and tax apply to [itemSubtotalPayable] (893-adjusted pre-tax item total when linked).
 * The server persists pre-tax line totals only; tax/fee remain client-side until the backend adds them.
 */
@Composable
private fun SaleTotalsPanel(
    itemCount: Int,
    itemSubtotalPublic: Double,
    itemSubtotalPayable: Double,
    memberDiscountPreTax: Double,
    linked893: Boolean,
    salesFeeRate: Double,
    taxRate: Double,
) {
    val salesFee = itemSubtotalPayable * salesFeeRate
    val taxable = itemSubtotalPayable + salesFee
    val taxAmt = taxable * taxRate
    val grandTotal = taxable + taxAmt

    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = "Sale total",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.primary,
            fontWeight = FontWeight.Bold,
        )
        if (linked893 && memberDiscountPreTax > 0.005) {
            Text(
                text = "893 member — pre-tax discount ${formatMoney(memberDiscountPreTax)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.tertiary,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.Top,
        ) {
            TotalSaleStat(
                modifier = Modifier.weight(1f),
                label = "Items",
                value = itemCount.toString(),
            )
            TotalSaleStat(
                modifier = Modifier.weight(1f),
                label = "Shelf\nsubtotal",
                value = formatMoney(itemSubtotalPublic),
            )
            TotalSaleStat(
                modifier = Modifier.weight(1f),
                label = "Item\npre-tax",
                value = formatMoney(itemSubtotalPayable),
            )
            TotalSaleStat(
                modifier = Modifier.weight(1f),
                label = salesFeeLabel(salesFeeRate),
                value = formatMoney(salesFee),
            )
            TotalSaleStat(
                modifier = Modifier.weight(1f),
                label = taxLabel(taxRate),
                value = formatMoney(taxAmt),
            )
            TotalSaleStat(
                modifier = Modifier.weight(1f),
                label = "Total",
                value = formatMoney(grandTotal),
                emphasize = true,
            )
        }
    }
}

private fun formatMoney(amount: Double): String = "$${"%.2f".format(amount)}"

@Composable
private fun TotalSaleStat(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    emphasize: Boolean = false,
) {
    Column(
        modifier = modifier.padding(horizontal = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            maxLines = 3,
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = value,
            style = if (emphasize) {
                MaterialTheme.typography.titleMedium
            } else {
                MaterialTheme.typography.bodyMedium
            },
            fontWeight = if (emphasize) FontWeight.Bold else FontWeight.Medium,
            color = if (emphasize) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurface
            },
            textAlign = TextAlign.Center,
            maxLines = 2,
        )
    }
}

private fun salesFeeLabel(rate: Double): String =
    if (rate > 0.0) "Sales\n(${formatPercent(rate)})" else "Sales"

private fun taxLabel(rate: Double): String =
    if (rate > 0.0) "Tax\n(${formatPercent(rate)})" else "Tax"

private fun formatPercent(rate: Double): String =
    String.format(Locale.US, "%.2f%%", rate * 100)

@Composable
private fun PaymentMethodPicker(
    selected: String,
    onSelected: (String) -> Unit,
    modifier: Modifier = Modifier,
    compact: Boolean = false,
) {
    var expanded by remember { mutableStateOf(false) }
    val options = listOf("card", "cash", "mobile")

    Column(modifier = modifier) {
        if (!compact) {
            OutlinedTextField(
                value = selected,
                onValueChange = {},
                readOnly = true,
                label = { Text("Payment") },
                modifier = Modifier.fillMaxWidth(),
            )
        }
        OutlinedButton(
            onClick = { expanded = true },
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = if (compact) 0.dp else 6.dp),
            contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp),
        ) {
            Text(
                if (compact) {
                    "Payment: $selected"
                } else {
                    "Choose payment"
                },
            )
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option) },
                    onClick = {
                        onSelected(option)
                        expanded = false
                    },
                )
            }
        }
    }
}
