package com.cloudstore.pos.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import com.cloudstore.pos.BuildConfig
import com.cloudstore.pos.data.CartItem
import com.cloudstore.pos.data.StoreCustomer
import com.cloudstore.pos.domain.checkout.cashBalanceDue
import com.cloudstore.pos.domain.checkout.exactBalanceDue
import com.cloudstore.pos.domain.checkout.formatCashEntry
import com.cloudstore.pos.domain.checkout.normalizeCashEntryInput
import com.cloudstore.pos.domain.pricing.computeCartTotals
import com.cloudstore.pos.domain.pricing.computeSaleGrandTotal
import com.cloudstore.pos.domain.pricing.computeTaxAmount
import com.cloudstore.pos.domain.pricing.formatMoney
import com.cloudstore.pos.domain.pricing.normalizeCartItems
import com.cloudstore.pos.domain.receipt.customerDisplayName
import com.cloudstore.pos.ui.theme.PosBackground
import com.cloudstore.pos.ui.theme.PosBorder
import com.cloudstore.pos.ui.theme.PosButtonDefaults
import com.cloudstore.pos.ui.theme.PosCardDefaults
import com.cloudstore.pos.ui.theme.PosPanel
import com.cloudstore.pos.ui.theme.PosPrimary
import com.cloudstore.pos.ui.theme.PosText
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope

@Composable
fun PosScreen(viewModel: PosViewModel) {
    val state by viewModel.state.collectAsState()
    val checkout by viewModel.checkoutState.collectAsState()
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

    var customerFindOpen by remember { mutableStateOf(false) }
    var statusVisible by remember { mutableStateOf(false) }
    var adminOpen by remember { mutableStateOf(false) }
    var showCardOnFileConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(state.queuedCheckoutCount) {
        if (state.queuedCheckoutCount > 0) {
            statusVisible = true
        }
    }

    LaunchedEffect(state.isAuthenticated) {
        if (!state.isAuthenticated) {
            customerFindOpen = false
            adminOpen = false
            statusVisible = false
        }
    }

    LaunchedEffect(checkout.saleItemsLocked) {
        if (checkout.saleItemsLocked) {
            scannerOpen = false
            viewModel.cancelQuantityEdit()
        }
    }

    LaunchedEffect(state.quantityEditCartItemId, state.cart) {
        val editingId = state.quantityEditCartItemId ?: return@LaunchedEffect
        if (state.cart.none { it.id == editingId }) {
            viewModel.cancelQuantityEdit()
        }
    }

    LaunchedEffect(state.isAuthenticated) {
        if (state.isAuthenticated) {
            viewModel.syncCashierIdentity()
        }
    }

    when (val closeGate = state.authGate) {
        is CashierAuthGate.ClosingTill -> {
            val countedTotal = sumTillCounts(closeGate.denominations, closeGate.counts)
            val headerHint = buildString {
                append("Opening ${formatTillMoney(closeGate.openingCountedFloat)}")
                append(" · Cash sales ${formatTillMoney(closeGate.cashSalesTotal)}")
                append(" · Change ${formatTillMoney(closeGate.changeGivenTotal)}")
            }
            OpeningTillScreen(
                expectedOpeningFloat = closeGate.expectedCloseFloat,
                denominations = closeGate.denominations,
                counts = closeGate.counts,
                selectedDenominationId = closeGate.selectedDenominationId,
                countedTotal = countedTotal,
                status = state.status,
                submitting = closeGate.submitting,
                onSelectDenomination = viewModel::selectClosingDenomination,
                onDigit = viewModel::appendClosingTillDigit,
                onClearCount = viewModel::clearClosingTillCount,
                onBackspaceCount = viewModel::backspaceClosingTillCount,
                onPreviousDenomination = viewModel::selectPreviousClosingDenomination,
                onNextDenomination = viewModel::selectNextClosingDenomination,
                onSubmit = viewModel::submitClosingTill,
                onNoCashToday = {},
                onCancel = viewModel::cancelCloseTill,
                screenTitle = "Close till",
                referenceLabel = "Expected",
                defaultStatus = "Count closing till",
                submitButtonText = "Submit for approval",
                showSecondaryButton = false,
                headerHint = headerHint,
                requireExactMatch = false,
            )
            return
        }
        is CashierAuthGate.ClosingCreditOnly -> {
            ClosingCreditOnlyScreen(
                status = state.status,
                submitting = closeGate.submitting,
                onSubmit = viewModel::submitClosingCreditOnly,
                onCancel = viewModel::cancelCloseTill,
            )
            return
        }
        is CashierAuthGate.WaitingCloseApproval -> {
            CloseApprovalWaitingScreen(
                secondsRemaining = closeGate.secondsRemaining,
                cashMode = closeGate.cashMode,
                expectedCloseFloat = closeGate.expectedCloseFloat,
                countedCloseFloat = closeGate.countedCloseFloat,
                closeVariance = closeGate.closeVariance,
                onCancel = viewModel::cancelCloseTill,
            )
            return
        }
        else -> Unit
    }

    if (!state.isAuthenticated) {
        when (val gate = state.authGate) {
            CashierAuthGate.Checking -> {
                CashierAuthLoading(status = state.status)
            }
            CashierAuthGate.OidcSignIn -> {
                val loginUrl = state.idpLoginUrl
                if (loginUrl.isNullOrBlank()) {
                    LaunchedEffect(Unit) { viewModel.cancelOidcSignIn() }
                } else {
                    CashierOidcWebScreen(
                        loginUrl = loginUrl,
                        apiBaseUrl = BuildConfig.API_BASE_URL,
                        onComplete = viewModel::onOidcWebViewComplete,
                        onCancel = viewModel::cancelOidcSignIn,
                    )
                }
            }
            is CashierAuthGate.OpeningTill -> {
                val countedTotal = sumTillCounts(gate.denominations, gate.counts)
                OpeningTillScreen(
                    expectedOpeningFloat = gate.expectedOpeningFloat,
                    denominations = gate.denominations,
                    counts = gate.counts,
                    selectedDenominationId = gate.selectedDenominationId,
                    countedTotal = countedTotal,
                    status = state.status,
                    submitting = gate.submitting,
                    onSelectDenomination = viewModel::selectTillDenomination,
                    onDigit = viewModel::appendTillDigit,
                    onClearCount = viewModel::clearTillCount,
                    onBackspaceCount = viewModel::backspaceTillCount,
                    onPreviousDenomination = viewModel::selectPreviousTillDenomination,
                    onNextDenomination = viewModel::selectNextTillDenomination,
                    onSubmit = viewModel::submitOpeningTill,
                    onNoCashToday = viewModel::submitNoCashToday,
                    onCancel = viewModel::cancelOpeningTill,
                )
            }
            is CashierAuthGate.WaitingApproval -> {
                LaunchedEffect(gate.email) {
                    viewModel.noteCashierIdentity(gate.email)
                }
                ApprovalWaitingScreen(
                    secondsRemaining = gate.secondsRemaining,
                    cashMode = gate.cashMode,
                    expectedOpeningFloat = gate.expectedOpeningFloat,
                    openingCountedFloat = gate.openingCountedFloat,
                    openingVariance = gate.openingVariance,
                    onCancel = viewModel::cancelApprovalWait,
                )
            }
            is CashierAuthGate.PinSignIn -> {
                CashierLogin(
                    pinInput = state.pinInput,
                    pinAllowed = gate.pinAllowed,
                    idpLoginUrl = state.idpLoginUrl,
                    status = state.status,
                    onPinChange = viewModel::setPinInput,
                    onUnlock = viewModel::unlock,
                    onIdpSignIn = viewModel::openOidcSignIn,
                )
            }
            is CashierAuthGate.ClosingTill,
            is CashierAuthGate.ClosingCreditOnly,
            is CashierAuthGate.WaitingCloseApproval,
            CashierAuthGate.SignedIn -> Unit
        }
        if (!state.isAuthenticated) return
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
            ModalDrawerSheet(drawerContainerColor = PosBackground) {
                Text(
                    text = "Menu",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = PosPrimary,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                )
                Column(
                    modifier = Modifier.padding(bottom = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    DrawerMenuButton(
                        text = if (statusVisible) "Hide status" else "Show status",
                        onClick = {
                            statusVisible = !statusVisible
                            scope.launch { drawerState.close() }
                        },
                    )
                    DrawerMenuButton(
                        text = if (customerFindOpen) "Show keypad" else "Find customer",
                        onClick = {
                            if (!customerFindOpen) {
                                viewModel.cancelQuantityEdit()
                            }
                            customerFindOpen = !customerFindOpen
                            scope.launch { drawerState.close() }
                        },
                    )
                    if (state.queuedCheckoutCount > 0) {
                        DrawerMenuButton(
                            text = if (state.queueSyncing) {
                                "Syncing queue…"
                            } else {
                                "Sync queued (${state.queuedCheckoutCount})"
                            },
                            onClick = {
                                viewModel.flushOfflineQueue()
                                scope.launch { drawerState.close() }
                            },
                        )
                        DrawerMenuButton(
                            text = "Discard queue (${state.queuedCheckoutCount})",
                            onClick = {
                                viewModel.clearOfflineQueue()
                                scope.launch { drawerState.close() }
                            },
                        )
                    }
                    DrawerMenuButton(
                        text = "Admin",
                        onClick = {
                            adminOpen = true
                            scope.launch { drawerState.close() }
                        },
                    )
                    DrawerMenuButton(
                        text = "Sign out",
                        onClick = {
                            viewModel.signOutForBreak()
                            scope.launch { drawerState.close() }
                        },
                    )
                    DrawerMenuButton(
                        text = "Close till",
                        onClick = {
                            viewModel.beginCloseTill()
                            scope.launch { drawerState.close() }
                        },
                    )
                }
            }
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .navigationBarsPadding(),
        ) {
            val salesFeeRate = BuildConfig.POS_SALES_FEE_RATE.toDoubleOrNull() ?: 0.0
            val taxRate = BuildConfig.POS_TAX_RATE.toDoubleOrNull() ?: 0.0

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(PosPrimary)
                    .statusBarsPadding()
                    .padding(start = 14.dp, end = 14.dp, top = 5.dp, bottom = 12.dp),
            ) {
                IconButton(
                    onClick = { scope.launch { drawerState.open() } },
                    colors = IconButtonDefaults.iconButtonColors(
                        contentColor = PosBackground,
                    ),
                    modifier = Modifier.align(Alignment.CenterStart),
                ) {
                    Text(
                        text = "\u2630",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = PosBackground,
                    )
                }
                Text(
                    text = "Cloud Store 893 POS",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    color = PosBackground,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.align(Alignment.Center),
                )
                Row(
                    modifier = Modifier.align(Alignment.CenterEnd),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    state.loggedInUser?.let { user ->
                        Text(
                            text = "user: $user",
                            style = MaterialTheme.typography.labelSmall,
                            color = PosBackground.copy(alpha = 0.92f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier
                                .widthIn(max = 220.dp)
                                .padding(end = 8.dp),
                        )
                    }
                    Text(
                        text = "v${BuildConfig.VERSION_NAME}",
                        style = MaterialTheme.typography.labelSmall,
                        color = PosBackground,
                        textAlign = TextAlign.End,
                    )
                }
            }

            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(horizontal = 14.dp, vertical = 8.dp),
            ) {
        // ── Scan & items | Number pad ─────────────────────────────────────────
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .padding(top = 0.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val receipt = state.receipt
            val showReceipt = receipt != null
            // ── Scan & items (left) ─────────────────────────────────────────
            Card(
                modifier = Modifier
                    .weight(0.65f)
                    .fillMaxHeight(),
                colors = PosCardDefaults.contentColors(),
                elevation = PosCardDefaults.elevation(),
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxHeight()
                        .padding(horizontal = 10.dp, vertical = 8.dp),
                ) {
                    if (!showReceipt) {
                    val barcodeFocus = remember { FocusRequester() }
                    val keyboard = LocalSoftwareKeyboardController.current
                    val focusManager = LocalFocusManager.current
                    OutlinedTextField(
                        value = state.barcodeInput,
                        onValueChange = viewModel::setBarcodeInput,
                        label = { Text("Scan / Add Id", color = PosPrimary) },
                        singleLine = true,
                        readOnly = checkout.saleItemsLocked,
                        enabled = !checkout.saleItemsLocked,
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedLabelColor = PosPrimary,
                            unfocusedLabelColor = PosPrimary,
                            disabledLabelColor = PosPrimary.copy(alpha = 0.5f),
                            focusedBorderColor = PosPrimary,
                            unfocusedBorderColor = PosPrimary.copy(alpha = 0.6f),
                            disabledBorderColor = PosPrimary.copy(alpha = 0.3f),
                            cursorColor = PosPrimary,
                            focusedTextColor = PosText,
                            unfocusedTextColor = PosText,
                        ),
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Number,
                            imeAction = ImeAction.Done,
                        ),
                        keyboardActions = KeyboardActions(
                            onDone = {
                                if (checkout.saleItemsLocked) return@KeyboardActions
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

                    val addInputReady =
                        state.barcodeInput.isNotBlank() && !checkout.saleItemsLocked
                    val scanEnabled =
                        state.barcodeInput.isBlank() && !checkout.saleItemsLocked
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
                            enabled = scanEnabled,
                            colors = PosButtonDefaults.teal(),
                            modifier = Modifier
                                .weight(1f)
                                .height(42.dp),
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
                        ) {
                            Text("Scan", style = MaterialTheme.typography.labelLarge)
                        }
                        Button(
                            onClick = viewModel::addByBarcode,
                            enabled = addInputReady,
                            colors = PosButtonDefaults.teal(),
                            modifier = Modifier
                                .weight(1f)
                                .height(42.dp),
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
                        ) {
                            Text("Add", style = MaterialTheme.typography.labelLarge)
                        }
                    }
                    state.addItemError?.let { error ->
                        Text(
                            text = error,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.error,
                            modifier = Modifier.padding(top = 8.dp),
                        )
                    }

                    HorizontalDivider(modifier = Modifier.padding(vertical = 6.dp))
                    }

                    if (showReceipt && receipt != null) {
                        SaleReceiptContent(
                            receipt = receipt,
                            modifier = Modifier.weight(1f),
                        )
                    } else {
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
                                quantityEditActive = state.quantityEditCartItemId == item.id,
                                editEnabled = !checkout.saleItemsLocked,
                                onEditQuantity = {
                                    customerFindOpen = false
                                    viewModel.startQuantityEdit(item.id)
                                },
                                removeEnabled = !checkout.saleItemsLocked,
                                onRemove = { viewModel.removeCartItem(item.id) },
                            )
                        }
                    }
                    if (checkout.open && checkout.payments.isNotEmpty()) {
                        PaymentsReceivedSection(
                            payments = checkout.payments,
                            onRemovePayment = { index ->
                                viewModel.updateCheckout { checkoutState ->
                                    val payment = checkoutState.payments.getOrNull(index)
                                    if (payment != null && payment.method != "card") {
                                        checkoutState.copy(
                                            payments = checkoutState.payments.filterIndexed { paymentIndex, _ ->
                                                paymentIndex != index
                                            },
                                        )
                                    } else {
                                        checkoutState
                                    }
                                }
                            },
                            modifier = Modifier.padding(top = 8.dp),
                        )
                    }
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 4.dp),
                    ) {
                        HorizontalDivider(
                            color = PosBorder,
                            thickness = 1.dp,
                        )
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(PosPanel)
                                .padding(horizontal = 4.dp, vertical = 6.dp),
                        ) {
                            SaleTotalsPanel(
                                cart = state.cart,
                                linkedCustomer = state.selectedCustomer(),
                                customerLinked = state.customerLinked(),
                                customerDiscount = state.customerDiscountActive(),
                                salesFeeRate = salesFeeRate,
                                taxRate = taxRate,
                            )
                        }
                    }
                    }
                }
            }

            // ── Status slot + fixed-size number pad (right) ───────────────────
            val showStatusSlot = statusVisible
            if (showReceipt && receipt != null) {
                Column(
                    modifier = Modifier
                        .weight(0.35f)
                        .fillMaxHeight(),
                ) {
                    Spacer(modifier = Modifier.weight(1f))
                    ReceiptActionPanel(
                        onPrint = viewModel::printReceipt,
                        printEnabled = state.receiptPrintMessage == null,
                        modifier = Modifier.padding(top = 6.dp),
                    )
                }
            } else {
            Column(
                modifier = Modifier
                    .weight(0.35f)
                    .fillMaxHeight(),
            ) {
                if (showStatusSlot) {
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 6.dp),
                        colors = PosCardDefaults.contentColors(),
                        elevation = PosCardDefaults.elevation(),
                    ) {
                        RegisterStatusPanel(
                            apiBaseUrl = BuildConfig.API_BASE_URL,
                            tillId = state.tillId,
                            posSessionId = state.posSessionId,
                            status = state.status,
                            queuedCount = state.queuedCheckoutCount,
                            syncing = state.queueSyncing,
                            onSyncQueued = viewModel::flushOfflineQueue,
                            onDiscardQueued = viewModel::clearOfflineQueue,
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        )
                    }
                }
                if (!checkout.open && !customerFindOpen) {
                    Spacer(modifier = Modifier.weight(1f))
                }
                val quantityEditing = state.quantityEditCartItemId != null && !checkout.open
                if (quantityEditing) {
                    val editingItem = state.cart.find { it.id == state.quantityEditCartItemId }
                    CartQuantityEditHeader(
                        itemName = editingItem?.name ?: "",
                        quantityInput = state.quantityEditInput,
                        onCancel = viewModel::cancelQuantityEdit,
                        onApply = viewModel::applyQuantityEdit,
                    )
                }
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(
                            if (checkout.open || customerFindOpen) {
                                Modifier.weight(1f)
                            } else {
                                Modifier.height(PosNumpadCardHeight)
                            },
                        ),
                    colors = PosCardDefaults.numpadPanelColors(),
                    elevation = PosCardDefaults.elevation(),
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
                                .padding(PosNumpadInnerPadding),
                        )
                    } else if (checkout.open) {
                        val registerTotal = computeSaleGrandTotal(
                            cart = state.cart,
                            customerLinked = state.customerLinked(),
                            customerDiscount = state.customerDiscountActive(),
                            salesFeeRate = salesFeeRate,
                            taxRate = taxRate,
                        )
                        val remainingAmount = exactBalanceDue(registerTotal, checkout.payments)
                        val cashAmountDue = if (state.cashEnabled && !state.creditOnlyPayments()) {
                            cashBalanceDue(registerTotal, checkout.payments)
                        } else {
                            remainingAmount
                        }
                        val linkedCustomer = state.selectedCustomer()
                        val allowPaymentBack =
                            !checkout.payments.any { it.method == "card" } &&
                                checkout.processingCardPayment == null
                        CheckoutPaymentPanel(
                            saleTotal = registerTotal,
                            balanceDue = remainingAmount,
                            cashAmountDue = cashAmountDue,
                            payments = checkout.payments,
                            backEnabled = allowPaymentBack,
                            cashEnabled = state.cashEnabled,
                            creditOnlyPayments = state.creditOnlyPayments(),
                            showCardOnFileButton = linkedCustomer?.hasCardOnFile == true,
                            amountInput = checkout.amountInput,
                            onAmountChange = { amount ->
                                viewModel.updateCheckout {
                                    it.copy(amountInput = normalizeCashEntryInput(amount))
                                }
                            },
                            onFillRemaining = {
                                val fillAmount = if (state.cashEnabled && !state.creditOnlyPayments()) {
                                    cashAmountDue
                                } else {
                                    remainingAmount
                                }
                                viewModel.updateCheckout {
                                    it.copy(amountInput = normalizeCashEntryInput(formatCashEntry(fillAmount)))
                                }
                            },
                            onApplyPayment = viewModel::applyCheckoutPayment,
                            onPayCardOnFile = {
                                if (!linkedCustomer?.cardLast4.isNullOrBlank()) {
                                    showCardOnFileConfirm = true
                                }
                            },
                            onBack = {
                                if (allowPaymentBack) {
                                    viewModel.resetCheckout()
                                }
                            },
                            modifier = Modifier.fillMaxSize(),
                        )
                    } else {
                        NumberPad(
                            onDigit = if (quantityEditing) {
                                viewModel::appendQuantityEditDigit
                            } else {
                                { d -> viewModel.setBarcodeInput(state.barcodeInput + d) }
                            },
                            onClear = if (quantityEditing) {
                                { viewModel.setQuantityEditInput("") }
                            } else {
                                { viewModel.setBarcodeInput("") }
                            },
                            onBackspace = if (quantityEditing) {
                                viewModel::backspaceQuantityEditInput
                            } else {
                                { viewModel.setBarcodeInput(state.barcodeInput.dropLast(1)) }
                            },
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(PosNumpadInnerPadding),
                        )
                    }
                }
                if (!checkout.open && !customerFindOpen) {
                    val setQuantityEnabled =
                        quantityEditing && state.quantityEditInput.isNotBlank()
                    Button(
                        onClick = {
                            customerFindOpen = false
                            viewModel.openCheckout()
                        },
                        enabled = state.cart.isNotEmpty() && !setQuantityEnabled,
                        colors = PosButtonDefaults.teal(),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 6.dp)
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

    checkout.processingDialogMessage?.let { message ->
        ProcessingStatusDialog(
            message = message,
            progress = checkout.paymentProcessingProgress,
        )
    }

    state.receiptPrintMessage?.let { message ->
        ProcessingStatusDialog(
            message = message,
            progress = state.receiptPrintProgress,
        )
    }

    if (showCardOnFileConfirm) {
        val linkedCustomer = state.selectedCustomer()
        val last4 = linkedCustomer?.cardLast4
        AlertDialog(
            onDismissRequest = { showCardOnFileConfirm = false },
            title = { Text("Confirm CardOnFile") },
            text = {
                Text(
                    text = if (!last4.isNullOrBlank()) {
                        "Charge card ending in $last4?"
                    } else {
                        "No card on file for this customer."
                    },
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showCardOnFileConfirm = false
                        if (!last4.isNullOrBlank()) {
                            viewModel.applyCardOnFilePayment()
                        }
                    },
                    enabled = !last4.isNullOrBlank(),
                ) {
                    Text("Confirm")
                }
            },
            dismissButton = {
                TextButton(onClick = { showCardOnFileConfirm = false }) {
                    Text("Cancel")
                }
            },
        )
    }

    if (scannerOpen && !checkout.saleItemsLocked && state.receipt == null) {
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
private fun DrawerMenuButton(
    text: String,
    onClick: () -> Unit,
) {
    OutlinedButton(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 10.dp),
        border = BorderStroke(1.dp, PosPrimary),
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = Color.Transparent,
            contentColor = Color.Black,
        ),
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun RegisterStatusPanel(
    apiBaseUrl: String,
    tillId: Int?,
    posSessionId: Int?,
    status: String,
    queuedCount: Int,
    syncing: Boolean,
    onSyncQueued: () -> Unit,
    onDiscardQueued: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            text = "Status",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.primary,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "API URL",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 4.dp),
        )
        Text(
            text = apiBaseUrl,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 2.dp),
        )
        if (tillId != null || posSessionId != null) {
            val sessionLine = buildList {
                tillId?.let { add("Till #$it") }
                posSessionId?.let { add("POS session #$it") }
            }.joinToString(" · ")
            Text(
                text = sessionLine,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 2.dp, bottom = 6.dp),
            )
        } else {
            Spacer(modifier = Modifier.height(6.dp))
        }
        if (status.isNotBlank()) {
            Text(
                text = status,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp, bottom = 6.dp),
            )
        }
        OfflineQueueStatus(
            queuedCount = queuedCount,
            syncing = syncing,
            onSyncQueued = onSyncQueued,
            onDiscardQueued = onDiscardQueued,
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

    Column(
        modifier = modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Top,
    ) {
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

        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            label = { Text("Id or Name") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
            textStyle = MaterialTheme.typography.bodyLarge,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp),
        )

        linkedCustomerId?.let { id ->
            val linked = customers.find { it.id == id }
            Text(
                text = "Linked: ${customerDisplayName(linked, id)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp),
            )
            TextButton(
                onClick = onUnlink,
                modifier = Modifier.padding(top = 2.dp),
            ) {
                Text("Unlink customer")
            }
        }

        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(top = 6.dp),
            contentAlignment = Alignment.TopStart,
        ) {
            when {
                query.trim().isEmpty() -> {}
                matches.isEmpty() -> {
                    Text(
                        text = "No customers found.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(matches, key = { it.id }) { customer ->
                            OutlinedButton(
                                onClick = { onLink(customer.id) },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 2.dp),
                                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 10.dp),
                                border = BorderStroke(1.dp, PosPrimary),
                                colors = ButtonDefaults.outlinedButtonColors(
                                    containerColor = Color.Transparent,
                                    contentColor = PosText,
                                ),
                            ) {
                                Column(modifier = Modifier.fillMaxWidth()) {
                                    Text(
                                        text = customerDisplayName(customer, customer.id),
                                        style = MaterialTheme.typography.bodyMedium,
                                        fontWeight = FontWeight.Medium,
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
    }
}

@Composable
private fun CartLineRow(
    item: CartItem,
    quantityEditActive: Boolean = false,
    editEnabled: Boolean = true,
    onEditQuantity: () -> Unit = {},
    removeEnabled: Boolean = true,
    onRemove: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = item.name,
                    style = MaterialTheme.typography.bodyMedium,
                )
                Text(
                    text = "ID ${item.productId}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            TextButton(
                onClick = onEditQuantity,
                enabled = editEnabled,
            ) {
                Text(
                    text = if (quantityEditActive) "Quantity" else "Quantity · ${item.quantity}",
                    fontWeight = if (quantityEditActive) FontWeight.Bold else FontWeight.Normal,
                    color = if (quantityEditActive) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.primary.copy(alpha = 0.85f)
                    },
                )
            }
            TextButton(
                onClick = onRemove,
                enabled = removeEnabled,
            ) {
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
private fun CashierAuthLoading(status: String) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = if (status.isNotBlank()) status else "Starting…",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.primary,
        )
    }
}

@Composable
private fun ApprovalWaitingScreen(
    secondsRemaining: Int?,
    cashMode: String?,
    expectedOpeningFloat: Double?,
    openingCountedFloat: Double?,
    openingVariance: Double?,
    onCancel: () -> Unit,
) {
    val timerText = approvalTimerText(secondsRemaining)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 28.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "Till open — waiting for supervisor",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary,
            textAlign = TextAlign.Center,
        )
        if (timerText != null) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = timerText,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        TillApprovalSummaryCard(
            cashMode = cashMode,
            expectedOpeningFloat = expectedOpeningFloat,
            openingCountedFloat = openingCountedFloat,
            openingVariance = openingVariance,
            modifier = Modifier.padding(top = 16.dp),
        )
        Spacer(modifier = Modifier.height(20.dp))
        OutlinedButton(
            onClick = onCancel,
            modifier = Modifier
                .width(PosNumpadColumnWidth)
                .height(52.dp),
        ) {
            Text("Cancel")
        }
    }
}

private fun formatTillMoney(value: Double?): String =
    if (value == null) "—" else formatMoney(value)

@Composable
private fun ClosingCreditOnlyScreen(
    status: String,
    submitting: Boolean,
    onSubmit: () -> Unit,
    onCancel: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 28.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "Close till",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = "Credit cards only shift. A supervisor must approve before this till closes and the next cashier can sign in.",
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
        )
        if (status.isNotBlank() && status != "Ready") {
            Spacer(modifier = Modifier.height(12.dp))
            Text(text = status, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
        }
        Spacer(modifier = Modifier.height(20.dp))
        Button(
            onClick = onSubmit,
            enabled = !submitting,
            colors = PosButtonDefaults.teal(),
            modifier = Modifier
                .width(PosNumpadColumnWidth)
                .height(52.dp),
        ) {
            Text(if (submitting) "Submitting…" else "Submit for approval")
        }
        OutlinedButton(
            onClick = onCancel,
            enabled = !submitting,
            modifier = Modifier
                .width(PosNumpadColumnWidth)
                .height(52.dp)
                .padding(top = 8.dp),
        ) {
            Text("Cancel")
        }
    }
}

@Composable
private fun CloseApprovalWaitingScreen(
    secondsRemaining: Int?,
    cashMode: String?,
    expectedCloseFloat: Double?,
    countedCloseFloat: Double?,
    closeVariance: Double?,
    onCancel: () -> Unit,
) {
    val timerText = approvalTimerText(secondsRemaining)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 28.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "Till close — waiting for supervisor",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary,
            textAlign = TextAlign.Center,
        )
        if (timerText != null) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = timerText,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        TillApprovalSummaryCard(
            cashMode = cashMode,
            expectedOpeningFloat = expectedCloseFloat,
            openingCountedFloat = countedCloseFloat,
            openingVariance = closeVariance,
            modifier = Modifier.padding(top = 16.dp),
            context = TillSummaryContext.Closing,
        )
        Spacer(modifier = Modifier.height(20.dp))
        OutlinedButton(
            onClick = onCancel,
            modifier = Modifier
                .width(PosNumpadColumnWidth)
                .height(52.dp),
        ) {
            Text("Cancel")
        }
    }
}

@Composable
private fun CashierLogin(
    pinInput: String,
    pinAllowed: Boolean,
    idpLoginUrl: String?,
    status: String,
    onPinChange: (String) -> Unit,
    onUnlock: () -> Unit,
    onIdpSignIn: () -> Unit,
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
            modifier = Modifier.width(PosNumpadColumnWidth),
            colors = PosCardDefaults.numpadPanelColors(),
            elevation = PosCardDefaults.elevation(),
        ) {
            Column(
                modifier = Modifier.padding(PosNumpadInnerPadding),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                if (pinAllowed) {
                    OutlinedTextField(
                        value = maskedPin,
                        onValueChange = {},
                        label = { Text("PIN") },
                        singleLine = true,
                        readOnly = true,
                        textStyle = MaterialTheme.typography.headlineSmall,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(PosNumpadCardHeight)
                            .padding(top = PosNumpadInnerPadding),
                    ) {
                        NumberPad(
                            onDigit = { d -> onPinChange(pinInput + d) },
                            onClear = { onPinChange("") },
                            onBackspace = { onPinChange(pinInput.dropLast(1)) },
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(PosNumpadInnerPadding),
                        )
                    }
                    Button(
                        onClick = onUnlock,
                        colors = PosButtonDefaults.teal(),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp)
                            .height(52.dp),
                        contentPadding = PaddingValues(vertical = 4.dp),
                    ) {
                        Text("Done", style = MaterialTheme.typography.titleMedium)
                    }
                }
                if (!idpLoginUrl.isNullOrBlank()) {
                    Button(
                        onClick = onIdpSignIn,
                        colors = PosButtonDefaults.teal(),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = if (pinAllowed) 8.dp else 0.dp)
                            .height(52.dp),
                        contentPadding = PaddingValues(vertical = 4.dp),
                    ) {
                        Text("Sign in", style = MaterialTheme.typography.titleMedium)
                    }
                }
            }
        }
        if (status != "Ready" && status.isNotBlank()) {
            Text(
                text = status,
                modifier = Modifier.padding(top = 12.dp),
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
                color = if (status.contains("Invalid") || status.contains("Cannot") || status.contains("error", ignoreCase = true) || status.contains("denied", ignoreCase = true)) {
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
    val totals = computeCartTotals(items, customerLinked && customerDiscount)
    val taxAmt = computeTaxAmount(cart, customerLinked, customerDiscount, salesFeeRate, taxRate)

    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = "Sale Total",
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            fontWeight = FontWeight.Bold,
        )
        linkedCustomer?.let { customer ->
            Text(
                text = customerDisplayName(customer, customer.id),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 1.dp),
            )
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
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

@Composable
private fun TotalSaleStat(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    emphasize: Boolean = false,
    valueColor: androidx.compose.ui.graphics.Color? = null,
) {
    Column(
        modifier = modifier.padding(horizontal = 1.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            maxLines = 2,
            lineHeight = MaterialTheme.typography.labelSmall.lineHeight * 0.9f,
        )
        Text(
            text = value,
            style = if (emphasize) {
                MaterialTheme.typography.titleSmall
            } else {
                MaterialTheme.typography.bodySmall
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
private fun ProcessingStatusDialog(
    message: String,
    progress: Float,
) {
    Dialog(
        onDismissRequest = {},
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            Card(
                modifier = Modifier.fillMaxWidth(0.4f),
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
}
