package com.cloudstore.pos.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Divider
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat

@OptIn(ExperimentalLayoutApi::class)
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
            .padding(16.dp),
    ) {
        Text(
            text = "Cloud Store POS",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
        )
        Text(text = state.status, style = MaterialTheme.typography.bodyMedium)
        if (state.queuedCheckoutCount > 0) {
            Text(
                text = "Queued checkouts: ${state.queuedCheckoutCount}",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
            Button(onClick = viewModel::flushOfflineQueue, modifier = Modifier.padding(top = 4.dp)) {
                Text("Sync queued")
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .padding(top = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Card(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight(),
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("Products", style = MaterialTheme.typography.titleMedium)
                    OutlinedTextField(
                        value = state.barcodeInput,
                        onValueChange = viewModel::setBarcodeInput,
                        label = { Text("Scan / type barcode") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp),
                    )
                    Button(onClick = viewModel::addByBarcode, modifier = Modifier.padding(top = 8.dp)) {
                        Text("Add by barcode")
                    }
                    Button(
                        onClick = {
                            if (hasCameraPermission) {
                                scannerOpen = true
                            } else {
                                permissionLauncher.launch(Manifest.permission.CAMERA)
                            }
                        },
                        modifier = Modifier.padding(top = 8.dp),
                    ) {
                        Text("Scan with camera")
                    }
                    FlowRow(
                        modifier = Modifier.padding(top = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        state.products.forEach { product ->
                            Button(onClick = { viewModel.addProduct(product.id) }) {
                                Text("${product.name}  $${"%.2f".format(product.price)}")
                            }
                        }
                    }
                }
            }

            Card(
                modifier = Modifier
                    .width(360.dp)
                    .fillMaxHeight(),
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("Current Sale", style = MaterialTheme.typography.titleMedium)
                    LazyColumn(
                        modifier = Modifier
                            .weight(1f)
                            .padding(top = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(state.cart) { item ->
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text("${item.name} x${item.quantity}")
                                TextButton(onClick = { viewModel.removeCartItem(item.id) }) {
                                    Text("Remove")
                                }
                            }
                        }
                    }

                    Divider(modifier = Modifier.padding(vertical = 8.dp))
                    Text(
                        text = "Total: $${"%.2f".format(state.total)}",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )

                    PaymentMethodPicker(
                        selected = state.paymentMethod,
                        onSelected = viewModel::setPaymentMethod,
                    )

                    Button(
                        onClick = viewModel::checkout,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp),
                    ) {
                        Text("Complete Sale")
                    }
                }
            }
        }

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(12.dp)) {
                Text("Recent Sales", style = MaterialTheme.typography.titleMedium)
                state.recentSales.take(8).forEach { sale ->
                    Text("${sale.orderNumber}  $${"%.2f".format(sale.total)}  ${sale.paymentMethod}")
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
private fun CashierLogin(
    pinInput: String,
    status: String,
    onPinChange: (String) -> Unit,
    onUnlock: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text("Cashier Sign In", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(8.dp))
        OutlinedTextField(
            value = pinInput,
            onValueChange = onPinChange,
            label = { Text("PIN") },
            modifier = Modifier.fillMaxWidth(),
        )
        Button(onClick = onUnlock, modifier = Modifier.padding(top = 10.dp)) {
            Text("Unlock POS")
        }
        Text(text = status, modifier = Modifier.padding(top = 8.dp))
    }
}

@Composable
private fun PaymentMethodPicker(
    selected: String,
    onSelected: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val options = listOf("card", "cash", "mobile")

    Column(modifier = Modifier.padding(top = 8.dp)) {
        OutlinedTextField(
            value = selected,
            onValueChange = {},
            readOnly = true,
            label = { Text("Payment") },
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedButton(
            onClick = { expanded = true },
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp),
        ) {
            Text("Choose payment")
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
