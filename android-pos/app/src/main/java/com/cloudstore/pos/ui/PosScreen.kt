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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.core.content.ContextCompat
import com.cloudstore.pos.BuildConfig
import com.cloudstore.pos.data.CartItem
import com.cloudstore.pos.data.CheckoutPayment
import com.cloudstore.pos.data.StoreCustomer
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope

private val PosNumpadWidth = 360.dp
private val PosNumpadHeight = 296.dp

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
    var cashPaymentOpen by remember { mutableStateOf(false) }
    var cashTenderedInput by remember { mutableStateOf("") }
    var statusPanelExpanded by remember { mutableStateOf(false) }
    var customerFindOpen by remember { mutableStateOf(false) }
    var adminOpen by remember { mutableStateOf(false) }
    var paymentDialogMessage by remember { mutableStateOf<String?>(null) }
    var pendingPaymentMethod by remember { mutableStateOf<String?>(null) }
    var processingCheckoutMethod by remember { mutableStateOf<String?>(null) }
    var processingDialogMessage by remember { mutableStateOf<String?>(null) }
    var paymentProcessingProgress by remember { mutableStateOf(0f) }
    var splitPaymentOpen by remember { mutableStateOf(false) }
    var splitPaymentAmountInput by remember { mutableStateOf("") }
    var splitPayments by remember { mutableStateOf(listOf<CheckoutPayment>()) }
    var pendingCheckoutPayments by remember { mutableStateOf<List<CheckoutPayment>?>(null) }

    LaunchedEffect(state.isAuthenticated) {
        if (!state.isAuthenticated) {
            payPanelVisible = false
            cashPaymentOpen = false
            cashTenderedInput = ""
            splitPaymentOpen = false
            splitPaymentAmountInput = ""
            splitPayments = emptyList()
            customerFindOpen = false
            adminOpen = false
            paymentDialogMessage = null
            pendingPaymentMethod = null
            processingCheckoutMethod = null
            processingDialogMessage = null
            paymentProcessingProgress = 0f
            pendingCheckoutPayments = null
        }
    }

    LaunchedEffect(state.cart.isEmpty(), state.isAuthenticated) {
        if (state.isAuthenticated && state.cart.isEmpty()) {
            payPanelVisible = false
            cashPaymentOpen = false
            splitPaymentOpen = false
            splitPaymentAmountInput = ""
            splitPayments = emptyList()
            pendingCheckoutPayments = null
        }
    }
    LaunchedEffect(state.status) {
        if (state.status.startsWith("Sale complete") || state.status.startsWith("Offline: checkout")) {
            payPanelVisible = false
            cashPaymentOpen = false
            cashTenderedInput = ""
            splitPaymentOpen = false
            splitPaymentAmountInput = ""
            splitPayments = emptyList()
            paymentDialogMessage = null
            pendingPaymentMethod = null
            processingCheckoutMethod = null
            processingDialogMessage = null
            paymentProcessingProgress = 0f
            pendingCheckoutPayments = null
        }
    }

    LaunchedEffect(processingCheckoutMethod, processingDialogMessage, pendingCheckoutPayments) {
        val method = processingCheckoutMethod ?: return@LaunchedEffect
        processingDialogMessage ?: return@LaunchedEffect
        val checkoutPayments = pendingCheckoutPayments
        paymentProcessingProgress = 0f
        val steps = 50
        repeat(steps) { index ->
            delay(100)
            paymentProcessingProgress = (index + 1) / steps.toFloat()
        }
        viewModel.setPaymentMethod(method)
        viewModel.checkout(payments = checkoutPayments)
        processingCheckoutMethod = null
        processingDialogMessage = null
        pendingPaymentMethod = null
        paymentProcessingProgress = 0f
        pendingCheckoutPayments = null
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

    if (adminOpen) {
        AdminWebScreen(
            apiBaseUrl = BuildConfig.API_BASE_URL,
            onClose = { adminOpen = false },
        )
        return
    }

    val drawerState = rememberDrawerState(initialValue = DrawerValue.Closed)
    val scope = rememberCoroutineScope()

    ModalNavigationDrawer(
        drawerState = drawerState,
        drawerContent = {
            ModalDrawerSheet {
                Text(
                    text = "Menu",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                )
                NavigationDrawerItem(
                    label = {
                        Text(if (statusPanelExpanded) "Hide status" else "Show status")
                    },
                    selected = statusPanelExpanded,
                    onClick = {
                        statusPanelExpanded = !statusPanelExpanded
                        scope.launch { drawerState.close() }
                    },
                )
                NavigationDrawerItem(
                    label = {
                        Text(if (customerFindOpen) "Show keypad" else "Find customer")
                    },
                    selected = customerFindOpen,
                    onClick = {
                        customerFindOpen = !customerFindOpen
                        scope.launch { drawerState.close() }
                    },
                )
                if (state.selectedCustomerId != null) {
                    NavigationDrawerItem(
                        label = { Text("Unlink customer") },
                        selected = false,
                        onClick = {
                            viewModel.setSelectedCustomerId(null)
                            customerFindOpen = false
                            scope.launch { drawerState.close() }
                        },
                    )
                }
                if (state.queuedCheckoutCount > 0) {
                    NavigationDrawerItem(
                        label = {
                            Text(
                                if (state.queueSyncing) "Syncing queue…"
                                else "Sync queued (${state.queuedCheckoutCount})",
                            )
                        },
                        selected = false,
                        onClick = {
                            viewModel.flushOfflineQueue()
                            scope.launch { drawerState.close() }
                        },
                    )
                    NavigationDrawerItem(
                        label = { Text("Discard queue (${state.queuedCheckoutCount})") },
                        selected = false,
                        onClick = {
                            viewModel.clearOfflineQueue()
                            scope.launch { drawerState.close() }
                        },
                    )
                }
                NavigationDrawerItem(
                    label = { Text("Admin") },
                    selected = adminOpen,
                    onClick = {
                        adminOpen = true
                        scope.launch { drawerState.close() }
                    },
                )
                NavigationDrawerItem(
                    label = { Text("Lock") },
                    selected = false,
                    onClick = {
                        viewModel.lock()
                        scope.launch { drawerState.close() }
                    },
                )
            }
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .navigationBarsPadding()
                .padding(horizontal = 14.dp, vertical = 8.dp),
        ) {
            val salesFeeRate = BuildConfig.POS_SALES_FEE_RATE.toDoubleOrNull() ?: 0.0
            val taxRate = BuildConfig.POS_TAX_RATE.toDoubleOrNull() ?: 0.0

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(
                    onClick = { scope.launch { drawerState.open() } },
                ) {
                    Text(
                        text = "\u2630",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                }
                Text(
                    text = "Cloud Store 893 POS",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = "v${BuildConfig.VERSION_NAME}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.width(48.dp),
                    textAlign = TextAlign.End,
                )
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
                    val barcodeFocus = remember { FocusRequester() }
                    val keyboard = LocalSoftwareKeyboardController.current
                    val focusManager = LocalFocusManager.current
                    OutlinedTextField(
                        value = state.barcodeInput,
                        onValueChange = viewModel::setBarcodeInput,
                        label = { Text("Scan or add ID") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Number,
                            imeAction = ImeAction.Done,
                        ),
                        keyboardActions = KeyboardActions(
                            onDone = {
                                keyboard?.hide()
                                focusManager.clearFocus()
                                viewModel.addByBarcode()
                            },
                        ),
                        textStyle = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier
                            .fillMaxWidth()
                            .focusRequester(barcodeFocus),
                    )

                    val scanInputReady = state.barcodeInput.isNotBlank()
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
                            enabled = scanInputReady,
                            modifier = Modifier
                                .weight(1f)
                                .height(42.dp),
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
                        ) {
                            Text("Scan", style = MaterialTheme.typography.labelLarge)
                        }
                        Button(
                            onClick = viewModel::addByBarcode,
                            enabled = scanInputReady,
                            modifier = Modifier
                                .weight(1f)
                                .height(42.dp),
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
                        ) {
                            Text("Add", style = MaterialTheme.typography.labelLarge)
                        }
                    }

                    HorizontalDivider(modifier = Modifier.padding(vertical = 6.dp))

                    Text(
                        text = "Current Sale",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    state.selectedCustomerId?.let { customerId ->
                        val customer = state.customers.find { it.id == customerId }
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 6.dp, bottom = 4.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                text = customerDisplayName(customer, customerId),
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.Medium,
                                modifier = Modifier.weight(1f),
                            )
                            TextButton(
                                onClick = { viewModel.setSelectedCustomerId(null) },
                                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 0.dp),
                            ) {
                                Text("Unlink")
                            }
                        }
                    }
                    LazyColumn(
                        modifier = Modifier
                            .weight(1f)
                            .padding(top = 4.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(state.cart) { item ->
                            CartLineRow(
                                item = item,
                                onRemove = { viewModel.removeCartItem(item.id) },
                            )
                        }
                    }
                }
            }

            // ── Status slot + fixed-size number pad (right) ───────────────────
            val showStatusSlot =
                statusPanelExpanded || state.queuedCheckoutCount > 0
            Column(
                modifier = Modifier
                    .width(PosNumpadWidth)
                    .fillMaxHeight(),
            ) {
                if (showStatusSlot) {
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 6.dp),
                    ) {
                        Column(
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        ) {
                            if (state.status != "Ready" && state.status.isNotBlank()) {
                                Text(
                                    text = state.status,
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                            }
                            OfflineQueueStatus(
                                queuedCount = state.queuedCheckoutCount,
                                syncing = state.queueSyncing,
                                onSyncQueued = viewModel::flushOfflineQueue,
                                onDiscardQueued = viewModel::clearOfflineQueue,
                                modifier = Modifier.padding(top = 4.dp),
                            )
                        }
                    }
                }
                if (!cashPaymentOpen) {
                    Spacer(modifier = Modifier.weight(1f))
                }
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(
                            if (cashPaymentOpen) {
                                Modifier.weight(1f)
                            } else {
                                Modifier.height(PosNumpadHeight)
                            },
                        ),
                ) {
                    if (customerFindOpen) {
                        CustomerFindPanel(
                            customers = state.customers,
                            linkedCustomerId = state.selectedCustomerId,
                            onLink = { id ->
                                viewModel.setSelectedCustomerId(id)
                                customerFindOpen = false
                            },
                            onUnlink = {
                                viewModel.setSelectedCustomerId(null)
                                customerFindOpen = false
                            },
                            onClose = { customerFindOpen = false },
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(12.dp),
                        )
                    } else if (cashPaymentOpen) {
                        val registerTotal = computeSaleGrandTotal(
                            cart = state.cart,
                            customerLinked = state.customerLinked(),
                            customerDiscount = state.customerDiscountActive(),
                            salesFeeRate = salesFeeRate,
                            taxRate = taxRate,
                        )
                        val amountDue = computeCashAmountDue(
                            cart = state.cart,
                            customerLinked = state.customerLinked(),
                            customerDiscount = state.customerDiscountActive(),
                            salesFeeRate = salesFeeRate,
                            taxRate = taxRate,
                        )
                        CashPaymentPanel(
                            registerTotal = registerTotal,
                            amountDue = amountDue,
                            tenderedInput = cashTenderedInput,
                            onTenderedChange = { cashTenderedInput = it },
                            onExactAmount = {
                                cashTenderedInput = formatCashEntry(amountDue)
                            },
                            onComplete = {
                                cashPaymentOpen = false
                                cashTenderedInput = ""
                                payPanelVisible = false
                                pendingCheckoutPayments = null
                                processingCheckoutMethod = "cash"
                                processingDialogMessage = "Printing Receipt"
                            },
                            onBack = {
                                cashPaymentOpen = false
                                cashTenderedInput = ""
                            },
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(12.dp),
                        )
                    } else if (splitPaymentOpen) {
                        val registerTotal = computeSaleGrandTotal(
                            cart = state.cart,
                            customerLinked = state.customerLinked(),
                            customerDiscount = state.customerDiscountActive(),
                            salesFeeRate = salesFeeRate,
                            taxRate = taxRate,
                        )
                        val paidTotal = roundMoney(splitPayments.sumOf { it.amount })
                        val remainingAmount = roundMoney((registerTotal - paidTotal).coerceAtLeast(0.0))
                        SplitPaymentPanel(
                            totalAmount = registerTotal,
                            payments = splitPayments,
                            amountInput = splitPaymentAmountInput,
                            onAmountChange = { splitPaymentAmountInput = it },
                            onFillRemaining = {
                                splitPaymentAmountInput = formatCashEntry(remainingAmount)
                            },
                            onAddPayment = { method ->
                                val enteredAmount = parseCashTendered(splitPaymentAmountInput)
                                if (enteredAmount != null &&
                                    enteredAmount > 0.0 &&
                                    enteredAmount <= remainingAmount + 0.005
                                ) {
                                    val appliedAmount = roundMoney(minOf(enteredAmount, remainingAmount))
                                    splitPayments = splitPayments + CheckoutPayment(
                                        method = method,
                                        amount = appliedAmount,
                                    )
                                    splitPaymentAmountInput = ""
                                }
                            },
                            onRemovePayment = { index ->
                                splitPayments = splitPayments.filterIndexed { paymentIndex, _ ->
                                    paymentIndex != index
                                }
                            },
                            onComplete = {
                                splitPaymentOpen = false
                                splitPaymentAmountInput = ""
                                payPanelVisible = false
                                pendingCheckoutPayments = splitPayments
                                splitPayments = emptyList()
                                processingCheckoutMethod = "split"
                                processingDialogMessage = "Processing Split Payment"
                            },
                            onBack = {
                                splitPaymentOpen = false
                                splitPaymentAmountInput = ""
                                splitPayments = emptyList()
                            },
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(12.dp),
                        )
                    } else if (payPanelVisible) {
                        val registerTotal = computeSaleGrandTotal(
                            cart = state.cart,
                            customerLinked = state.customerLinked(),
                            customerDiscount = state.customerDiscountActive(),
                            salesFeeRate = salesFeeRate,
                            taxRate = taxRate,
                        )
                        PaymentMethodPicker(
                            selected = state.paymentMethod,
                            amountDue = registerTotal,
                            cardProcessing = processingCheckoutMethod == "card",
                            onBack = { payPanelVisible = false },
                            onOptionPicked = { method ->
                                if (method == "cash") {
                                    viewModel.setPaymentMethod("cash")
                                    splitPaymentOpen = false
                                    splitPaymentAmountInput = ""
                                    splitPayments = emptyList()
                                    cashTenderedInput = ""
                                    cashPaymentOpen = true
                                } else if (method == "split") {
                                    viewModel.setPaymentMethod("split")
                                    splitPaymentAmountInput = ""
                                    splitPayments = emptyList()
                                    splitPaymentOpen = true
                                } else {
                                    viewModel.setPaymentMethod("card")
                                    splitPaymentOpen = false
                                    splitPaymentAmountInput = ""
                                    splitPayments = emptyList()
                                    pendingCheckoutPayments = null
                                    pendingPaymentMethod = method
                                    paymentDialogMessage = "Use Card Paid"
                                }
                            },
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(12.dp),
                        )
                    } else {
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
                        cart = state.cart,
                        linkedCustomer = state.selectedCustomer(),
                        customerLinked = state.customerLinked(),
                        customerDiscount = state.customerDiscountActive(),
                        salesFeeRate = salesFeeRate,
                        taxRate = taxRate,
                    )
                    if (!payPanelVisible && !cashPaymentOpen) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 8.dp),
                            horizontalArrangement = Arrangement.End,
                        ) {
                            Button(
                                onClick = {
                                    customerFindOpen = false
                                    cashPaymentOpen = false
                                    splitPaymentOpen = false
                                    splitPaymentAmountInput = ""
                                    splitPayments = emptyList()
                                    pendingCheckoutPayments = null
                                    viewModel.setPaymentMethod("card")
                                    payPanelVisible = true
                                },
                                enabled = state.cart.isNotEmpty(),
                                modifier = Modifier
                                    .fillMaxWidth(0.2f)
                                    .height(44.dp),
                                contentPadding = PaddingValues(vertical = 4.dp),
                            ) {
                                Text("Pay")
                            }
                        }
                    }
                }
            }
        }
        }
    }

    paymentDialogMessage?.let { message ->
        PaymentMessageDialog(
            message = message,
            onConfirm = {
                paymentDialogMessage = null
                pendingCheckoutPayments = null
                processingCheckoutMethod = pendingPaymentMethod
                processingDialogMessage = "Processing Card Payment"
            },
            onDismiss = {
                paymentDialogMessage = null
                pendingPaymentMethod = null
                pendingCheckoutPayments = null
            },
        )
    }

    processingDialogMessage?.let { message ->
        ProcessingStatusDialog(
            message = message,
            progress = paymentProcessingProgress,
        )
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
    syncing: Boolean,
    onSyncQueued: () -> Unit,
    onDiscardQueued: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
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
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                text = "Sync replays each saved cart. Discard clears entries that cannot be recovered.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp),
            )
            OutlinedButton(
                onClick = onSyncQueued,
                enabled = !syncing,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp),
            ) {
                Text(if (syncing) "Syncing…" else "Sync queued")
            }
            OutlinedButton(
                onClick = onDiscardQueued,
                enabled = !syncing,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 6.dp),
            ) {
                Text("Discard queue")
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

private fun formatCashEntry(amount: Double): String {
    val rounded = roundMoney(amount)
    return if (rounded == rounded.toLong().toDouble()) {
        rounded.toLong().toString()
    } else {
        "%.2f".format(rounded)
    }
}

private fun parseCashTendered(raw: String): Double? {
    val trimmed = raw.trim()
    if (trimmed.isEmpty() || trimmed == ".") return null
    return trimmed.toDoubleOrNull()
}

private fun appendCashDigit(current: String, digit: Char): String {
    if (digit == '.') {
        if (current.contains('.')) return current
        return if (current.isEmpty()) "0." else "$current."
    }
    if (current.contains('.')) {
        val frac = current.substringAfter('.')
        if (frac.length >= 2) return current
    } else if (current.length >= 7) {
        return current
    }
    return current + digit
}

@Composable
private fun CashPaymentPanel(
    registerTotal: Double,
    amountDue: Double,
    tenderedInput: String,
    onTenderedChange: (String) -> Unit,
    onExactAmount: () -> Unit,
    onComplete: () -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tendered = parseCashTendered(tenderedInput)
    val change = if (tendered != null) roundMoney(tendered - amountDue) else null
    val canComplete = tendered != null && tendered + 0.005 >= amountDue
    val nickelAdjustment = roundMoney(amountDue - registerTotal)
    val showNickelNote = kotlin.math.abs(nickelAdjustment) > 0.001
    val quickBills = cashQuickDenominations(amountDue)

    Column(
        modifier = modifier
            .fillMaxSize()
            .fillMaxHeight(),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = onBack, contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp)) {
                Text("Back")
            }
            Text(
                text = "Cash",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
            )
        }
        if (showNickelNote) {
            CashAmountRow(
                label = "Register total",
                value = formatMoney(registerTotal),
            )
        }
        CashAmountRow(
            label = if (showNickelNote) "Cash due (no pennies)" else "Amount due",
            value = formatMoney(amountDue),
            emphasize = true,
        )
        CashAmountRow(
            label = "Cash entered",
            value = if (tenderedInput.isBlank()) "—" else "\$$tenderedInput",
        )
        val changeLabel = when {
            change == null -> "Change"
            change < -0.005 -> "Still need"
            change < 0.005 -> "Change"
            else -> "Give change"
        }
        val changeValue = when {
            change == null -> "—"
            change < -0.005 -> formatMoney(-change)
            change < 0.005 -> formatMoney(0.0)
            else -> formatMoney(change)
        }
        val changeOk = change != null && change >= 0.005
        CashAmountRow(
            label = changeLabel,
            value = changeValue,
            emphasize = changeOk,
            valueColor = when {
                change == null -> null
                change < -0.005 -> MaterialTheme.colorScheme.error
                changeOk -> MaterialTheme.colorScheme.tertiary
                else -> MaterialTheme.colorScheme.onSurface
            },
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            OutlinedButton(
                onClick = onExactAmount,
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(vertical = 4.dp),
            ) {
                Text(formatMoney(amountDue), style = MaterialTheme.typography.labelMedium)
            }
            quickBills.forEach { bill ->
                OutlinedButton(
                    onClick = { onTenderedChange(formatCashEntry(bill.toDouble())) },
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(vertical = 4.dp),
                ) {
                    Text("\$$bill", style = MaterialTheme.typography.labelMedium)
                }
            }
        }
        NumberPad(
            onDigit = { d -> onTenderedChange(appendCashDigit(tenderedInput, d)) },
            onClear = { onTenderedChange("") },
            onBackspace = { onTenderedChange(tenderedInput.dropLast(1)) },
            onDecimal = { onTenderedChange(appendCashDigit(tenderedInput, '.')) },
            compact = true,
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .heightIn(min = 136.dp)
                .padding(top = 6.dp),
        )
        Button(
            onClick = onComplete,
            enabled = canComplete,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp),
            contentPadding = PaddingValues(vertical = 6.dp),
        ) {
            Text("Complete Sale")
        }
    }
}

@Composable
private fun CashAmountRow(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    emphasize: Boolean = false,
    valueColor: androidx.compose.ui.graphics.Color? = null,
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

@Composable
private fun NumberPad(
    onDigit: (Char) -> Unit,
    onClear: () -> Unit,
    onBackspace: () -> Unit,
    onDecimal: (() -> Unit)? = null,
    compact: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val keyGap = if (compact) 6.dp else 8.dp
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
                        compact = compact,
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
            PadKey(
                text = "C",
                onClick = onClear,
                compact = compact,
                modifier = Modifier.weight(1f).fillMaxHeight(),
                emphasis = KeyEmphasis.Secondary,
            )
            if (onDecimal != null) {
                PadKey(
                    text = ".",
                    onClick = onDecimal,
                    compact = compact,
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    emphasis = KeyEmphasis.Secondary,
                )
            }
            PadKey(
                text = "0",
                onClick = { onDigit('0') },
                compact = compact,
                modifier = Modifier.weight(1f).fillMaxHeight(),
            )
            PadKey(
                text = "\u232B",
                onClick = onBackspace,
                compact = compact,
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
    compact: Boolean = false,
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
                style = if (compact) {
                    MaterialTheme.typography.titleLarge
                } else {
                    MaterialTheme.typography.headlineMedium
                },
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

private fun customerDisplayName(customer: StoreCustomer?, customerId: Int): String {
    if (customer != null) {
        return customer.name
    }
    return "Customer #$customerId"
}

@Composable
private fun CustomerFindPanel(
    customers: List<StoreCustomer>,
    linkedCustomerId: Int?,
    onLink: (Int) -> Unit,
    onUnlink: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var query by remember { mutableStateOf("") }
    var selectedId by remember { mutableStateOf<Int?>(null) }

    val matches = remember(query, customers) {
        val q = query.trim()
        if (q.isEmpty()) {
            emptyList()
        } else {
            val asId = q.toIntOrNull()
            customers.filter { c ->
                if (asId != null) {
                    c.id == asId || c.id.toString().startsWith(q)
                } else {
                    c.name.contains(q, ignoreCase = true) ||
                        c.email?.contains(q, ignoreCase = true) == true ||
                        c.phone?.contains(q, ignoreCase = true) == true
                }
            }.take(12)
        }
    }

    LaunchedEffect(matches) {
        selectedId = when {
            matches.size == 1 -> matches.first().id
            selectedId != null && matches.none { it.id == selectedId } -> null
            else -> selectedId
        }
    }

    val selectedCustomer = selectedId?.let { id -> customers.find { it.id == id } }

    Column(modifier = modifier) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Find customer",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold,
            )
            TextButton(onClick = onClose) {
                Text("Keypad")
            }
        }

        linkedCustomerId?.let { id ->
            val linked = customers.find { it.id == id }
            Text(
                text = "Linked: ${customerDisplayName(linked, id)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
            TextButton(
                onClick = onUnlink,
                modifier = Modifier.padding(top = 2.dp),
            ) {
                Text("Unlink customer")
            }
        }

        OutlinedTextField(
            value = query,
            onValueChange = {
                query = it
                selectedId = null
            },
            label = { Text("ID or name") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
            textStyle = MaterialTheme.typography.bodyLarge,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp),
        )

        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(top = 6.dp),
        ) {
            when {
                query.trim().isEmpty() -> {
                    Text(
                        text = "Enter a customer ID or name to search.\n" +
                            "Link customers here; use Scan/Add for product IDs.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                matches.isEmpty() -> {
                    Text(
                        text = "No customers found.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                else -> {
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        items(matches, key = { it.id }) { customer ->
                            val picked = customer.id == selectedId
                            OutlinedButton(
                                onClick = { selectedId = customer.id },
                                modifier = Modifier.fillMaxWidth(),
                                contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp),
                                colors = if (picked) {
                                    androidx.compose.material3.ButtonDefaults.outlinedButtonColors(
                                        containerColor = MaterialTheme.colorScheme.secondaryContainer,
                                    )
                                } else {
                                    androidx.compose.material3.ButtonDefaults.outlinedButtonColors()
                                },
                            ) {
                                Column(modifier = Modifier.fillMaxWidth()) {
                                    Text(
                                        text = customerDisplayName(customer, customer.id),
                                        style = MaterialTheme.typography.bodyMedium,
                                        fontWeight = if (picked) FontWeight.SemiBold else FontWeight.Normal,
                                    )
                                    val detail = listOfNotNull(
                                        customer.email?.takeIf { it.isNotBlank() },
                                        customer.phone?.takeIf { it.isNotBlank() },
                                    ).joinToString(" · ")
                                    if (detail.isNotEmpty()) {
                                        Text(
                                            text = detail,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Button(
            onClick = { selectedCustomer?.let { onLink(it.id) } },
            enabled = selectedCustomer != null,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp),
        ) {
            Text(
                if (selectedCustomer != null) {
                    "Link ${customerDisplayName(selectedCustomer, selectedCustomer.id)}"
                } else {
                    "Link to customer"
                },
            )
        }
    }
}

@Composable
private fun CartLineRow(
    item: CartItem,
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
        if (item.onSale && item.salePrice != null) {
            val burgundy = MaterialTheme.colorScheme.primary
            val bodyColor = MaterialTheme.colorScheme.onSurface
            val strikeWidth = with(LocalDensity.current) { 1.5.dp.toPx() }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "Reg ${formatMoney(item.regularPrice)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = bodyColor,
                    modifier = Modifier.drawBehind {
                        val y = size.height / 2f
                        drawLine(
                            color = burgundy,
                            start = Offset(0f, y),
                            end = Offset(size.width, y),
                            strokeWidth = strikeWidth,
                        )
                    },
                )
                Text(
                    text = "Sale ${formatMoney(item.salePrice)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = burgundy,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        } else {
            Text(
                text = "Reg ${formatMoney(item.regularPrice)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun CashierLogin(
    pinInput: String,
    status: String,
    onPinChange: (String) -> Unit,
    onUnlock: () -> Unit,
) {
    val maskedPin = "•".repeat(pinInput.length)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 28.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "Cashier Sign In",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary,
        )
        Spacer(modifier = Modifier.height(16.dp))
        Card(
            modifier = Modifier
                .width(360.dp)
                .fillMaxHeight(0.85f),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                OutlinedTextField(
                    value = maskedPin,
                    onValueChange = {},
                    label = { Text("PIN") },
                    singleLine = true,
                    readOnly = true,
                    textStyle = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.fillMaxWidth(),
                )
                NumberPad(
                    onDigit = { d -> onPinChange(pinInput + d) },
                    onClear = { onPinChange("") },
                    onBackspace = { onPinChange(pinInput.dropLast(1)) },
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(top = 12.dp),
                )
                Button(
                    onClick = onUnlock,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp)
                        .height(52.dp),
                    contentPadding = PaddingValues(vertical = 4.dp),
                ) {
                    Text("Done", style = MaterialTheme.typography.titleMedium)
                }
            }
        }
        if (status != "Ready" && status.isNotBlank()) {
            Text(
                text = status,
                modifier = Modifier.padding(top = 12.dp),
                style = MaterialTheme.typography.bodyMedium,
                color = if (status.contains("Invalid") || status.contains("Cannot") || status.contains("error", ignoreCase = true)) {
                    MaterialTheme.colorScheme.error
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
            )
        }
    }
}

/**
 * Line totals for the cashier. Amounts are derived from [cart] lines so the bar stays in sync
 * with the list above. Tax rate comes from `BuildConfig` / pos.properties.
 */
@Composable
private fun SaleTotalsPanel(
    cart: List<CartItem>,
    linkedCustomer: StoreCustomer?,
    customerLinked: Boolean,
    customerDiscount: Boolean,
    salesFeeRate: Double,
    taxRate: Double,
) {
    val grandTotal = computeSaleGrandTotal(
        cart = cart,
        customerLinked = customerLinked,
        customerDiscount = customerDiscount,
        salesFeeRate = salesFeeRate,
        taxRate = taxRate,
    )
    val items = if (customerLinked) normalizeCartItems(cart, customerDiscount) else cart
    val totals = if (customerLinked) {
        computeCartTotalsForLinkedCustomer(items, customerDiscount)
    } else {
        computeCartTotals(items, customerDiscount = false)
    }
    val salesFee = totals.itemPreTax * salesFeeRate
    val taxable = totals.itemPreTax + salesFee
    val taxAmt = taxable * taxRate

    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = "Sale total",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.primary,
            fontWeight = FontWeight.Bold,
        )
        linkedCustomer?.let { customer ->
            Text(
                text = customerDisplayName(customer, customer.id),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 2.dp),
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
                value = totals.itemCount.toString(),
            )
            if (customerLinked) {
                TotalSaleStat(
                    modifier = Modifier.weight(1f),
                    label = "Subtotal",
                    value = formatMoney(totals.shelfSubtotal),
                )
                TotalSaleStat(
                    modifier = Modifier.weight(1f),
                    label = "Discount",
                    value = if (totals.showDiscount) {
                        "−${formatMoney(totals.memberDiscount)}"
                    } else {
                        formatMoney(0.0)
                    },
                    valueColor = if (totals.showDiscount) {
                        MaterialTheme.colorScheme.tertiary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
                TotalSaleStat(
                    modifier = Modifier.weight(1f),
                    label = "PreTax",
                    value = formatMoney(totals.itemPreTax),
                )
            } else {
                TotalSaleStat(
                    modifier = Modifier.weight(1f),
                    label = "Subtotal",
                    value = formatMoney(totals.itemPreTax),
                )
            }
            TotalSaleStat(
                modifier = Modifier.weight(1f),
                label = "Savings",
                value = if (totals.saleSavings > 0.005) {
                    "−${formatMoney(totals.saleSavings)}"
                } else {
                    formatMoney(0.0)
                },
                valueColor = MaterialTheme.colorScheme.primary,
            )
            TotalSaleStat(
                modifier = Modifier.weight(1f),
                label = "Tax",
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

private fun formatMoney(amount: Double): String = "\$${"%.2f".format(amount)}"

@Composable
private fun TotalSaleStat(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    emphasize: Boolean = false,
    valueColor: androidx.compose.ui.graphics.Color? = null,
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
            color = valueColor ?: if (emphasize) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurface
            },
            textAlign = TextAlign.Center,
            maxLines = 2,
        )
    }
}

@Composable
private fun PaymentMessageDialog(
    message: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    Dialog(onDismissRequest = onDismiss) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp),
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 18.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = "Payment Type",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary,
                )
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = message,
                    style = MaterialTheme.typography.bodyLarge,
                    textAlign = TextAlign.Center,
                )
                Spacer(modifier = Modifier.height(18.dp))
                Button(
                    onClick = onConfirm,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("OK")
                }
            }
        }
    }
}

@Composable
private fun ProcessingStatusDialog(
    message: String,
    progress: Float,
) {
    Dialog(onDismissRequest = {}) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp),
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 18.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = message,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary,
                    textAlign = TextAlign.Center,
                )
                Spacer(modifier = Modifier.height(14.dp))
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

private fun paymentMethodLabel(method: String): String = when (method) {
    "card" -> "Card"
    "cash" -> "Cash"
    "split" -> "Split"
    else -> method
}

@Composable
private fun SplitPaymentPanel(
    totalAmount: Double,
    payments: List<CheckoutPayment>,
    amountInput: String,
    onAmountChange: (String) -> Unit,
    onFillRemaining: () -> Unit,
    onAddPayment: (String) -> Unit,
    onRemovePayment: (Int) -> Unit,
    onComplete: () -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val paidTotal = roundMoney(payments.sumOf { it.amount })
    val remaining = roundMoney((totalAmount - paidTotal).coerceAtLeast(0.0))
    val nextAmount = parseCashTendered(amountInput)
    val canAdd = nextAmount != null && nextAmount > 0.0 && nextAmount <= remaining + 0.005
    val canComplete = payments.isNotEmpty() && remaining <= 0.005

    Column(
        modifier = modifier.fillMaxSize(),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = onBack, contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp)) {
                Text("Back")
            }
            Text(
                text = "Split Payment",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
            )
        }
        CashAmountRow(
            label = "Amount due",
            value = formatMoney(totalAmount),
            emphasize = true,
        )
        CashAmountRow(
            label = "Collected",
            value = formatMoney(paidTotal),
        )
        CashAmountRow(
            label = "Remaining",
            value = formatMoney(remaining),
            emphasize = remaining > 0.005,
            valueColor = if (remaining > 0.005) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.tertiary
            },
        )
        Text(
            text = "Enter exact applied amounts for each tender. Split cash does not track tendered or change.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 4.dp),
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            OutlinedButton(
                onClick = onFillRemaining,
                enabled = remaining > 0.005,
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(vertical = 4.dp),
            ) {
                Text("Remaining", style = MaterialTheme.typography.labelMedium)
            }
            OutlinedButton(
                onClick = { onAmountChange("") },
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(vertical = 4.dp),
            ) {
                Text("Clear", style = MaterialTheme.typography.labelMedium)
            }
        }
        CashAmountRow(
            label = "Next amount",
            value = nextAmount?.let(::formatMoney) ?: "—",
            modifier = Modifier.padding(top = 2.dp),
        )
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .padding(top = 6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (payments.isEmpty()) {
                Text(
                    text = "Add card and/or cash entries until the remaining balance reaches \$0.00.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                payments.forEachIndexed { index, payment ->
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 10.dp, vertical = 8.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(
                                modifier = Modifier.weight(1f),
                            ) {
                                Text(
                                    text = "${index + 1}. ${paymentMethodLabel(payment.method)}",
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                Text(
                                    text = formatMoney(payment.amount),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
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
        NumberPad(
            onDigit = { d -> onAmountChange(appendCashDigit(amountInput, d)) },
            onClear = { onAmountChange("") },
            onBackspace = { onAmountChange(amountInput.dropLast(1)) },
            onDecimal = { onAmountChange(appendCashDigit(amountInput, '.')) },
            compact = true,
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .heightIn(min = 136.dp)
                .padding(top = 6.dp),
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            OutlinedButton(
                onClick = { onAddPayment("card") },
                enabled = canAdd,
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(vertical = 6.dp),
            ) {
                Text("Add Card")
            }
            OutlinedButton(
                onClick = { onAddPayment("cash") },
                enabled = canAdd,
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(vertical = 6.dp),
            ) {
                Text("Add Cash")
            }
        }
        Button(
            onClick = onComplete,
            enabled = canComplete,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp),
            contentPadding = PaddingValues(vertical = 6.dp),
        ) {
            Text("Complete Sale")
        }
    }
}

/**
 * Two direct action buttons so the cashier can pick card, cash, or split without opening a select box.
 */
@Composable
private fun PaymentMethodPicker(
    selected: String,
    amountDue: Double,
    cardProcessing: Boolean,
    onBack: () -> Unit,
    onOptionPicked: (method: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val options = listOf(
        "card" to "Card",
        "cash" to "Cash",
        "split" to "Split",
    )
    val title = when (selected) {
        "card" -> "Card"
        "split" -> "Split Payment"
        else -> "Payment Type"
    }
    Column(
        modifier = modifier.fillMaxSize(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 6.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(
                onClick = onBack,
                contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp),
            ) {
                Text("Back")
            }
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
            )
        }
        Spacer(modifier = Modifier.weight(1f))
        if (selected == "card") {
            Column(
                modifier = Modifier.fillMaxWidth(),
            ) {
                CashAmountRow(
                    label = "Amount due",
                    value = formatMoney(amountDue),
                    emphasize = true,
                )
                CashAmountRow(
                    label = "Card amount",
                    value = formatMoney(amountDue),
                )
                CashAmountRow(
                    label = "Status",
                    value = if (cardProcessing) "Processing Card Payment" else "Ready to charge",
                    valueColor = if (cardProcessing) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
            }
        } else if (selected == "split") {
            Column(
                modifier = Modifier.fillMaxWidth(),
            ) {
                CashAmountRow(
                    label = "Amount due",
                    value = formatMoney(amountDue),
                    emphasize = true,
                )
                Text(
                    text = "Split combines exact card and cash entries until the balance reaches zero.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Spacer(modifier = Modifier.weight(1f))
        Row(
            modifier = Modifier
                .fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            options.forEach { (value, label) ->
                val isSelected = value == selected
                if (isSelected) {
                    Button(
                        onClick = { onOptionPicked(value) },
                        modifier = Modifier
                            .weight(1f)
                            .height(52.dp),
                    ) {
                        Text(label)
                    }
                } else {
                    OutlinedButton(
                        onClick = { onOptionPicked(value) },
                        modifier = Modifier
                            .weight(1f)
                            .height(52.dp),
                    ) {
                        Text(label)
                    }
                }
            }
        }
    }
}
