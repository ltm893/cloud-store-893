package com.cloudstore.lister.ui

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.cloudstore.lister.BuildConfig
import com.cloudstore.lister.data.InventoryListItem
import com.cloudstore.lister.data.InventoryNamedList
import com.cloudstore.lister.data.InventoryProduct
import com.cloudstore.lister.data.ListDiffResult
import com.cloudstore.lister.data.ListPersistence
import com.cloudstore.lister.data.ListerRegisterId
import com.cloudstore.lister.data.ListerRepository
import com.cloudstore.lister.data.WebViewCookieSync
import com.cloudstore.lister.data.clearIdpWebViewCookies
import com.cloudstore.lister.domain.ApiConfigLogic
import com.cloudstore.lister.domain.CsvImportLogic
import com.cloudstore.lister.domain.CsvFieldMapping
import com.cloudstore.lister.domain.ListExportLogic
import com.cloudstore.lister.domain.ParsedCsv
import com.cloudstore.lister.domain.ListQueryLogic
import com.cloudstore.lister.domain.ListSortField
import com.cloudstore.lister.domain.ListSortLogic
import com.cloudstore.lister.domain.ListStoreLogic
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlin.random.Random

enum class ListerTab { Input, Results, Lists }

sealed interface AuthGate {
    data object Checking : AuthGate
    data object SignIn : AuthGate
    data object OidcSignIn : AuthGate
    data class SignedIn(val user: String) : AuthGate
}

data class ListerUiState(
    val authGate: AuthGate = AuthGate.Checking,
    val selectedTab: ListerTab = ListerTab.Input,
    val inputText: String = "",
    val product: InventoryProduct? = null,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val lastQuery: String = "",
    val lists: List<InventoryNamedList> = emptyList(),
    val activeListId: String = "",
    val scannedCode: String = "",
    val showListOperations: Boolean = false,
    val showCsvImport: Boolean = false,
    val batchQueryProgress: String? = null,
)

class ListerViewModel(
    private val appContext: Context,
    private val repository: ListerRepository,
    private val persistence: ListPersistence,
    private val registerId: String,
    private val baseUrl: String = BuildConfig.API_BASE_URL,
) : ViewModel() {

    private val _state = MutableStateFlow(ListerUiState())
    val state: StateFlow<ListerUiState> = _state.asStateFlow()

    private var batchJob: Job? = null

    val oidcLoginUrl: String
        get() = ApiConfigLogic.oidcLoginUrl(baseUrl, registerId)

    init {
        loadLists()
        probeSession()
    }

    private suspend fun applySessionProbe() {
        runCatching { repository.fetchSession(registerId) }
            .onSuccess { session ->
                val user = session.displayUser
                when {
                    session.ok -> activateSignedIn(user ?: "Signed in")
                    session.idpEnabled -> {
                        val detail = when {
                            repository.hasCashierSessionCookie() ->
                                "Signed in at Oracle but session was not accepted — try again"
                            else -> "Sign in required"
                        }
                        _state.update {
                            it.copy(authGate = AuthGate.SignIn, errorMessage = detail)
                        }
                    }
                    else -> activateSignedIn("Lister")
                }
            }
            .onFailure { err ->
                _state.update {
                    it.copy(authGate = AuthGate.SignIn, errorMessage = err.message ?: "Session check failed")
                }
            }
    }

    fun probeSession() {
        viewModelScope.launch {
            _state.update { it.copy(authGate = AuthGate.Checking) }
            applySessionProbe()
        }
    }

    fun openOidcSignIn() {
        _state.update { it.copy(authGate = AuthGate.OidcSignIn, errorMessage = null) }
    }

    fun cancelOidcSignIn() {
        _state.update { it.copy(authGate = AuthGate.SignIn) }
    }

    fun onOidcComplete(completionUrl: String) {
        _state.update { it.copy(authGate = AuthGate.Checking, errorMessage = null) }
        viewModelScope.launch {
            WebViewCookieSync.syncWithRetry(baseUrl, repository.cookieJar)
            repository.pinCashierSessionFromWebView()
            applySessionProbe()
        }
    }

    fun signOut() {
        viewModelScope.launch {
            repository.logout()
            clearIdpWebViewCookies()
            repository.cookieJar.clearHost(android.net.Uri.parse(baseUrl).host.orEmpty())
            _state.update {
                it.copy(authGate = AuthGate.SignIn, product = null, errorMessage = null)
            }
        }
    }

    fun selectTab(tab: ListerTab) {
        _state.update { it.copy(selectedTab = tab) }
    }

    fun appendDigit(digit: Char) {
        _state.update { it.copy(inputText = it.inputText + digit) }
    }

    fun backspace() {
        _state.update { it.copy(inputText = it.inputText.dropLast(1)) }
    }

    fun clearInput() {
        _state.update { it.copy(inputText = "") }
    }

    fun submitLookup(query: String) {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) {
            _state.update { it.copy(errorMessage = "Enter product ID or barcode") }
            return
        }
        viewModelScope.launch {
            _state.update {
                it.copy(isLoading = true, errorMessage = null, product = null, lastQuery = trimmed, inputText = "")
            }
            runCatching { repository.lookup(trimmed) }
                .onSuccess { product ->
                    _state.update { it.copy(isLoading = false, product = product, selectedTab = ListerTab.Results) }
                }
                .onFailure { err ->
                    _state.update {
                        it.copy(isLoading = false, errorMessage = err.message ?: "Lookup failed")
                    }
                }
        }
    }

    fun lookupFromInput() = submitLookup(_state.value.inputText)

    fun onBarcodeScanned(code: String) {
        _state.update { it.copy(scannedCode = code) }
        submitLookup(code)
    }

    fun addProductToActiveList(product: InventoryProduct) {
        val item = InventoryListItem.fromProduct(product)
        updateLists { lists ->
            ListStoreLogic.addItem(item, _state.value.activeListId, lists)
        }
        _state.update { it.copy(selectedTab = ListerTab.Lists) }
    }

    fun addProductToList(product: InventoryProduct, listId: String) {
        val item = InventoryListItem.fromProduct(product)
        updateLists { ListStoreLogic.addItem(item, listId, it) }
        _state.update { it.copy(activeListId = listId, selectedTab = ListerTab.Lists) }
    }

    fun switchList(id: String) {
        if (_state.value.lists.any { it.id == id }) {
            _state.update { it.copy(activeListId = id) }
            persistence.saveActiveListId(id)
        }
    }

    fun createList(name: String): String? {
        val (updated, newId) = ListStoreLogic.createList(name, _state.value.lists)
        _state.update { it.copy(lists = updated, activeListId = newId) }
        saveLists(updated, newId)
        return newId
    }

    fun saveItemsAsNewList(name: String, items: List<InventoryListItem>): String? {
        if (items.isEmpty()) return null
        val (updated, newId) = ListStoreLogic.createListWithItems(name, items, _state.value.lists)
        _state.update {
            it.copy(
                lists = updated,
                activeListId = newId,
                showListOperations = false,
                selectedTab = ListerTab.Lists,
            )
        }
        saveLists(updated, newId)
        return newId
    }

    fun renameList(id: String, name: String) {
        val updated = ListStoreLogic.renameList(id, name, _state.value.lists) ?: return
        _state.update { it.copy(lists = updated) }
        saveLists(updated)
    }

    fun deleteList(id: String) {
        val updated = ListStoreLogic.deleteList(id, _state.value.lists)
        val active = if (updated.any { it.id == _state.value.activeListId }) {
            _state.value.activeListId
        } else {
            updated.firstOrNull()?.id.orEmpty()
        }
        _state.update { it.copy(lists = updated, activeListId = active) }
        saveLists(updated, active)
    }

    fun incrementPull(itemId: String) = mutateActiveItems { ListStoreLogic.incrementPullCount(itemId, it) }
    fun decrementPull(itemId: String) = mutateActiveItems { ListStoreLogic.decrementPullCount(itemId, it) }
    fun deleteItem(itemId: String) = mutateActiveItems { it.filter { row -> row.id != itemId } }
    fun clearActiveList() = mutateActiveItems { emptyList() }

    fun copyItem(item: InventoryListItem, toListId: String): Boolean {
        val current = _state.value
        val updated = ListStoreLogic.copyItem(current.lists, current.activeListId, item, toListId) ?: return false
        _state.update { it.copy(lists = updated) }
        saveLists(updated)
        return true
    }

    fun moveItem(item: InventoryListItem, toListId: String): Boolean {
        val current = _state.value
        val updated = ListStoreLogic.moveItem(current.lists, current.activeListId, item, toListId) ?: return false
        _state.update { it.copy(lists = updated, activeListId = toListId) }
        saveLists(updated, toListId)
        return true
    }

    fun openListOperations() {
        _state.update { it.copy(showListOperations = true) }
    }

    fun closeListOperations() {
        _state.update { it.copy(showListOperations = false) }
    }

    fun openCsvImport() {
        _state.update { it.copy(showCsvImport = true) }
    }

    fun closeCsvImport() {
        _state.update { it.copy(showCsvImport = false) }
    }

    fun importCsv(parsed: ParsedCsv, mapping: CsvFieldMapping, targetListId: String?, newListName: String) {
        viewModelScope.launch {
            runCatching {
                val items = CsvImportLogic.buildItems(parsed, mapping)
                val (lists, listId) = if (targetListId != null) {
                    _state.value.lists to targetListId
                } else {
                    ListStoreLogic.createList(newListName, _state.value.lists)
                }
                val updated = CsvImportLogic.applyImport(items, listId, lists)
                _state.update {
                    it.copy(
                        lists = updated,
                        activeListId = listId,
                        showCsvImport = false,
                        selectedTab = ListerTab.Lists,
                        errorMessage = null,
                    )
                }
                saveLists(updated, listId)
            }.onFailure { err ->
                _state.update { it.copy(errorMessage = err.message) }
            }
        }
    }

    fun unionLists(ids: List<String>, name: String) {
        val result = ListStoreLogic.unionLists(ids, name, _state.value.lists) ?: return
        _state.update { it.copy(lists = result.first, activeListId = result.second) }
        saveLists(result.first, result.second)
    }

    fun diffLists(aId: String, bId: String): ListDiffResult? =
        ListStoreLogic.diffLists(aId, bId, _state.value.lists)

    fun splitList(id: String, mode: ListStoreLogic.SplitMode, count: Int, prefix: String) {
        val result = ListStoreLogic.splitList(id, mode, count, prefix, _state.value.lists) ?: return
        _state.update { it.copy(lists = result.first, activeListId = result.second) }
        saveLists(result.first, result.second)
    }

    fun sortList(id: String, field: ListSortField, ascending: Boolean) {
        val updated = ListSortLogic.sortList(id, field, ascending, _state.value.lists) ?: return
        _state.update { it.copy(lists = updated, activeListId = id) }
        saveLists(updated, id)
    }

    fun exportCsv(): String {
        val items = activeItems()
        return ListExportLogic.buildCsv(items)
    }

    fun batchListQuery(sourceListId: String, resultName: String) {
        batchJob?.cancel()
        val source = _state.value.lists.firstOrNull { it.id == sourceListId } ?: return
        if (source.items.isEmpty()) return
        batchJob = viewModelScope.launch {
            val finalName = ListStoreLogic.uniqueListName(
                ListQueryLogic.resultListName(source.name, resultName),
                _state.value.lists,
            )
            val (created, targetId) = ListStoreLogic.createList(finalName, _state.value.lists)
            _state.update { it.copy(lists = created, activeListId = targetId) }
            saveLists(created, targetId)

            val results = mutableListOf<InventoryListItem>()
            source.items.forEachIndexed { index, item ->
                if (index > 0) delay(Random.nextLong(300, 800))
                _state.update { it.copy(batchQueryProgress = "${index + 1}/${source.items.size}") }
                val refreshed = runCatching { repository.lookup(item.productId.toString()) }
                    .fold(
                        onSuccess = { item.refreshed(it) },
                        onFailure = { err -> item.withLookupFailure(err.message ?: "Lookup failed") },
                    )
                results.add(refreshed)
                val lists = ListQueryLogic.setItems(results.toList(), targetId, _state.value.lists)
                _state.update { it.copy(lists = lists) }
                saveLists(lists, targetId)
            }
            _state.update {
                it.copy(
                    batchQueryProgress = null,
                    selectedTab = ListerTab.Lists,
                    showListOperations = false,
                )
            }
        }
    }

    fun cancelBatchQuery() {
        batchJob?.cancel()
        _state.update { it.copy(batchQueryProgress = null) }
    }

    private fun activateSignedIn(user: String) {
        _state.update { it.copy(authGate = AuthGate.SignedIn(user), errorMessage = null) }
    }

    private fun loadLists() {
        val saved = persistence.loadLists()
        val lists = ListStoreLogic.bootstrapLists(saved)
        val active = ListStoreLogic.resolveActiveListId(persistence.loadActiveListId(), lists)
        _state.update { it.copy(lists = lists, activeListId = active) }
        saveLists(lists, active)
    }

    private fun updateLists(transform: (List<InventoryNamedList>) -> List<InventoryNamedList>) {
        val updated = transform(_state.value.lists)
        _state.update { it.copy(lists = updated) }
        saveLists(updated)
    }

    private fun mutateActiveItems(transform: (List<InventoryListItem>) -> List<InventoryListItem>) {
        val activeId = _state.value.activeListId
        val index = _state.value.lists.indexOfFirst { it.id == activeId }
        if (index < 0) return
        val updated = _state.value.lists.toMutableList()
        updated[index] = updated[index].copy(items = transform(updated[index].items))
        _state.update { it.copy(lists = updated) }
        saveLists(updated)
    }

    private fun activeItems(): List<InventoryListItem> =
        _state.value.lists.firstOrNull { it.id == _state.value.activeListId }?.items.orEmpty()

    private fun saveLists(lists: List<InventoryNamedList>, activeId: String = _state.value.activeListId) {
        persistence.saveLists(lists)
        persistence.saveActiveListId(activeId)
    }

    class Factory(private val context: Context) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            val appContext = context.applicationContext
            return ListerViewModel(
                appContext,
                ListerRepository(BuildConfig.API_BASE_URL),
                ListPersistence(appContext),
                ListerRegisterId.get(appContext),
            ) as T
        }
    }
}
