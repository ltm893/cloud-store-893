package com.cloudstore.lister.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.ViewList
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cloudstore.lister.BuildConfig
import com.cloudstore.lister.data.ListCsvShare
import com.cloudstore.lister.ui.auth.ListerOidcWebScreen
import com.cloudstore.lister.ui.lists.CsvImportScreen
import com.cloudstore.lister.ui.lists.ListOperationsScreen
import com.cloudstore.lister.ui.tabs.AllListsScreen
import com.cloudstore.lister.ui.tabs.InputRoute
import com.cloudstore.lister.ui.tabs.InputTab
import com.cloudstore.lister.ui.tabs.ListsTab
import com.cloudstore.lister.ui.tabs.ListsTabDialogs
import com.cloudstore.lister.ui.tabs.ResultsTab
import com.cloudstore.lister.ui.theme.ListerBackground
import com.cloudstore.lister.ui.theme.ListerPrimary

@Composable
fun ListerAppScreen(viewModel: ListerViewModel) {
    val state by viewModel.state.collectAsState()

    when (val gate = state.authGate) {
        AuthGate.Checking -> {
            Column(
                Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                CircularProgressIndicator(color = ListerPrimary)
                Text("Checking session…", modifier = Modifier.padding(top = 12.dp))
            }
        }
        AuthGate.SignIn -> SignInScreen(
            hostLabel = android.net.Uri.parse(BuildConfig.API_BASE_URL).host.orEmpty(),
            errorMessage = state.errorMessage,
            onSignIn = viewModel::openOidcSignIn,
        )
        AuthGate.OidcSignIn -> ListerOidcWebScreen(
            loginUrl = viewModel.oidcLoginUrl,
            apiBaseUrl = BuildConfig.API_BASE_URL,
            onComplete = viewModel::onOidcComplete,
            onCancel = viewModel::cancelOidcSignIn,
        )
        is AuthGate.SignedIn -> {
            if (state.showCsvImport) {
                CsvImportScreen(
                    lists = state.lists,
                    activeListId = state.activeListId,
                    onClose = viewModel::closeCsvImport,
                    onImport = viewModel::importCsv,
                )
            } else if (state.showListOperations) {
                ListOperationsScreen(
                    lists = state.lists,
                    batchProgress = state.batchQueryProgress,
                    onClose = viewModel::closeListOperations,
                    onUnion = viewModel::unionLists,
                    onSplit = viewModel::splitList,
                    onSort = viewModel::sortList,
                    onBatchQuery = viewModel::batchListQuery,
                    onCancelBatch = viewModel::cancelBatchQuery,
                    onDiff = viewModel::diffLists,
                    onSaveAsNewList = viewModel::saveItemsAsNewList,
                )
            } else {
                MainTabs(viewModel, gate.user)
            }
        }
    }
}

@Composable
private fun SignInScreen(hostLabel: String, errorMessage: String?, onSignIn: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(ListerBackground)
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("Cloud Store 893 Lister", style = MaterialTheme.typography.headlineMedium)
        Text(
            "Inventory Checker",
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(vertical = 16.dp),
        )
        Text(hostLabel, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        errorMessage?.let { msg ->
            Text(
                msg,
                color = MaterialTheme.colorScheme.error,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
        Button(
            onClick = onSignIn,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 24.dp),
        ) {
            Text("Sign In")
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MainTabs(viewModel: ListerViewModel, user: String) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var inputRoute by rememberSaveable { mutableStateOf(InputRoute.Hub) }
    var showAllLists by remember { mutableStateOf(false) }
    var listsMenuOpen by remember { mutableStateOf(false) }
    var showDeleteAll by remember { mutableStateOf(false) }
    val hostLabel = android.net.Uri.parse(BuildConfig.API_BASE_URL).host.orEmpty()
    val activeList = state.lists.firstOrNull { it.id == state.activeListId }
    val activeListName = activeList?.name ?: "Lists"
    val activeItemCount = activeList?.items?.size ?: 0
    val hasNonEmptyList = state.lists.any { it.items.isNotEmpty() }

    if (showAllLists) {
        AllListsScreen(
            lists = state.lists,
            activeListId = state.activeListId,
            onDismiss = { showAllLists = false },
            onSwitch = { viewModel.switchList(it); showAllLists = false },
            onCreate = viewModel::createList,
            onRename = viewModel::renameList,
            onDelete = viewModel::deleteList,
        )
        return
    }

    val topBarTitle = when (state.selectedTab) {
        ListerTab.Input -> when (inputRoute) {
            InputRoute.Hub -> "Search Input"
            InputRoute.Manual -> "Manual Entry"
            InputRoute.Scanner -> "Barcode Scanner"
        }
        ListerTab.Results -> "Results"
        ListerTab.Lists -> activeListName
    }

    Scaffold(
        containerColor = ListerBackground,
        topBar = {
            TopAppBar(
                title = { Text(topBarTitle) },
                navigationIcon = {
                    when {
                        state.selectedTab == ListerTab.Input && inputRoute != InputRoute.Hub -> {
                            IconButton(onClick = { inputRoute = InputRoute.Hub }) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                            }
                        }
                        state.selectedTab == ListerTab.Lists -> {
                            Box {
                                IconButton(onClick = { listsMenuOpen = true }) {
                                    Icon(Icons.Default.MoreVert, contentDescription = "List menu")
                                }
                                DropdownMenu(
                                    expanded = listsMenuOpen,
                                    onDismissRequest = { listsMenuOpen = false },
                                ) {
                                    DropdownMenuItem(
                                        text = { Text("List Operations") },
                                        enabled = hasNonEmptyList,
                                        onClick = {
                                            listsMenuOpen = false
                                            viewModel.openListOperations()
                                        },
                                    )
                                    DropdownMenuItem(
                                        text = { Text("Share as CSV") },
                                        enabled = activeItemCount > 0,
                                        onClick = {
                                            listsMenuOpen = false
                                            ListCsvShare.share(
                                                context = context,
                                                listName = activeListName,
                                                items = activeList?.items.orEmpty(),
                                            )
                                        },
                                    )
                                    HorizontalDivider()
                                    DropdownMenuItem(
                                        text = { Text("Delete All") },
                                        enabled = activeItemCount > 0,
                                        onClick = {
                                            listsMenuOpen = false
                                            showDeleteAll = true
                                        },
                                    )
                                }
                            }
                        }
                    }
                },
                actions = {
                    when (state.selectedTab) {
                        ListerTab.Lists -> {
                            IconButton(onClick = { showAllLists = true }) {
                                Icon(Icons.Default.ViewList, contentDescription = "All lists")
                            }
                        }
                        else -> {
                            TextButton(
                                onClick = { viewModel.signOut() },
                                colors = ButtonDefaults.textButtonColors(contentColor = Color.White),
                            ) {
                                Text(
                                    user,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.padding(end = 4.dp),
                                )
                            }
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = ListerPrimary,
                    titleContentColor = Color.White,
                    navigationIconContentColor = Color.White,
                    actionIconContentColor = Color.White,
                ),
            )
        },
        bottomBar = {
            NavigationBar(
                containerColor = ListerBackground,
                contentColor = ListerPrimary,
            ) {
                ListerTab.entries.forEach { tab ->
                    val selected = state.selectedTab == tab
                    NavigationBarItem(
                        selected = selected,
                        onClick = {
                            if (tab == ListerTab.Input) inputRoute = InputRoute.Hub
                            viewModel.selectTab(tab)
                        },
                        icon = {
                            val icon = when (tab) {
                                ListerTab.Input -> Icons.Default.Keyboard
                                ListerTab.Results -> Icons.Default.Search
                                ListerTab.Lists -> Icons.AutoMirrored.Filled.List
                            }
                            Icon(icon, contentDescription = tab.name)
                        },
                        label = { Text(tab.name) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = ListerPrimary,
                            selectedTextColor = ListerPrimary,
                            indicatorColor = ListerBackground,
                            unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                            unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        ),
                    )
                }
            }
        },
    ) { padding ->
        Box(
            Modifier
                .padding(padding)
                .fillMaxSize()
                .background(ListerBackground),
        ) {
            when (state.selectedTab) {
                ListerTab.Input -> InputTab(
                    hostLabel = hostLabel,
                    inputText = state.inputText,
                    route = inputRoute,
                    onRouteChange = { inputRoute = it },
                    onDigit = viewModel::appendDigit,
                    onBackspace = viewModel::backspace,
                    onClear = viewModel::clearInput,
                    onLookup = viewModel::lookupFromInput,
                    onBarcode = { code ->
                        inputRoute = InputRoute.Hub
                        viewModel.onBarcodeScanned(code)
                    },
                    onImportCsv = viewModel::openCsvImport,
                )
                ListerTab.Results -> ResultsTab(
                    isLoading = state.isLoading,
                    errorMessage = state.errorMessage,
                    product = state.product,
                    lists = state.lists,
                    activeListId = state.activeListId,
                    lastQuery = state.lastQuery,
                    onAddToList = viewModel::addProductToList,
                    onCreateList = viewModel::createList,
                )
                ListerTab.Lists -> ListsTab(
                    lists = state.lists,
                    activeListId = state.activeListId,
                    onIncrement = viewModel::incrementPull,
                    onDecrement = viewModel::decrementPull,
                    onDeleteItem = viewModel::deleteItem,
                    onCopyItem = viewModel::copyItem,
                    onMoveItem = viewModel::moveItem,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
    }

    ListsTabDialogs(
        activeListName = activeListName,
        itemCount = activeItemCount,
        showDeleteAll = showDeleteAll,
        onDismissDeleteAll = { showDeleteAll = false },
        onConfirmDeleteAll = {
            viewModel.clearActiveList()
            showDeleteAll = false
        },
    )
}
