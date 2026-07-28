package com.cloudstore.lister.ui.lists

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.List
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cloudstore.lister.data.InventoryListItem
import com.cloudstore.lister.data.InventoryNamedList
import com.cloudstore.lister.data.ListDiffResult
import com.cloudstore.lister.domain.ListSortField
import com.cloudstore.lister.domain.ListSortLogic
import com.cloudstore.lister.domain.ListStoreLogic
import com.cloudstore.lister.ui.theme.ListerAccent
import com.cloudstore.lister.ui.theme.ListerBackground
import com.cloudstore.lister.ui.theme.ListerHighlight
import com.cloudstore.lister.ui.theme.ListerMuted
import com.cloudstore.lister.ui.theme.ListerPanel
import com.cloudstore.lister.ui.theme.ListerPrimary
import kotlin.math.ceil
import kotlin.math.min

private enum class OperationMode(val label: String) {
    Union("Union"),
    Diff("Diff"),
    Split("Split"),
    Sort("Sort"),
    Query("Query"),
}

private val SegmentedTrack = Color(0xFFE5E1D8)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ListOperationsScreen(
    lists: List<InventoryNamedList>,
    batchProgress: String?,
    onClose: () -> Unit,
    onUnion: (List<String>, String) -> Unit,
    onSplit: (String, ListStoreLogic.SplitMode, Int, String) -> Unit,
    onSort: (String, ListSortField, Boolean) -> Unit,
    onBatchQuery: (String, String) -> Unit,
    onCancelBatch: () -> Unit,
    onDiff: (String, String) -> ListDiffResult?,
    onSaveAsNewList: (String, List<InventoryListItem>) -> Unit,
) {
    var mode by remember { mutableStateOf(OperationMode.Union) }

    Scaffold(
        containerColor = ListerBackground,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "List Operations",
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    TextButton(
                        onClick = onClose,
                        modifier = Modifier.padding(start = 4.dp),
                    ) {
                        Text(
                            "Done",
                            color = Color.White,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = ListerPrimary,
                    titleContentColor = Color.White,
                    navigationIconContentColor = Color.White,
                ),
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            OperationModePicker(
                selected = mode,
                onSelect = { mode = it },
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            )
            when (mode) {
                OperationMode.Union -> UnionOperationView(
                    lists = lists,
                    onCreate = onUnion,
                    onDone = onClose,
                )
                OperationMode.Diff -> DiffOperationView(
                    lists = lists,
                    onDiff = onDiff,
                    onSaveAsNewList = onSaveAsNewList,
                )
                OperationMode.Split -> SplitOperationView(
                    lists = lists,
                    onSplit = onSplit,
                    onDone = onClose,
                )
                OperationMode.Sort -> SortOperationView(
                    lists = lists,
                    onSort = onSort,
                    onDone = onClose,
                )
                OperationMode.Query -> QueryOperationView(
                    lists = lists,
                    batchProgress = batchProgress,
                    onBatchQuery = onBatchQuery,
                    onCancelBatch = onCancelBatch,
                )
            }
        }
    }
}

@Composable
private fun SplitByPicker(
    byNumberOfLists: Boolean,
    onSelect: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(SegmentedTrack)
            .padding(4.dp),
    ) {
        listOf(true to "Number of Lists", false to "Items per List").forEach { (value, label) ->
            val isSelected = byNumberOfLists == value
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(20.dp))
                    .background(if (isSelected) ListerPanel else Color.Transparent)
                    .clickable { onSelect(value) }
                    .padding(vertical = 8.dp, horizontal = 4.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = label,
                    fontSize = 11.sp,
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (isSelected) ListerPrimary else ListerMuted,
                    maxLines = 2,
                    lineHeight = 13.sp,
                )
            }
        }
    }
}

@Composable
private fun OperationModePicker(
    selected: OperationMode,
    onSelect: (OperationMode) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(SegmentedTrack)
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        OperationMode.entries.forEach { option ->
            val isSelected = option == selected
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(20.dp))
                    .background(if (isSelected) ListerPanel else Color.Transparent)
                    .clickable { onSelect(option) }
                    .padding(vertical = 8.dp, horizontal = 2.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = option.label,
                    fontSize = 12.sp,
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (isSelected) ListerPrimary else ListerMuted,
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun UnionOperationView(
    lists: List<InventoryNamedList>,
    onCreate: (List<String>, String) -> Unit,
    onDone: () -> Unit,
) {
    var selectedIds by remember { mutableStateOf(setOf<String>()) }
    var customName by remember { mutableStateOf("") }

    val generatedName = lists
        .filter { selectedIds.contains(it.id) }
        .joinToString("-") { it.name }
    val canCreate = selectedIds.size >= 2
    val totalItems = lists
        .filter { selectedIds.contains(it.id) }
        .flatMap { it.items }
        .map { it.productId }
        .toSet()
        .size

    Column(Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 8.dp),
        ) {
            item {
                OperationSectionHeader("Select lists to combine (pick 2 or more)")
            }
            items(lists, key = { it.id }) { list ->
                val isSelected = selectedIds.contains(list.id)
                ListSelectionRow(
                    name = list.name,
                    itemCount = list.items.size,
                    isSelected = isSelected,
                    onClick = {
                        selectedIds = if (isSelected) {
                            selectedIds - list.id
                        } else {
                            selectedIds + list.id
                        }
                        customName = generatedName
                    },
                )
            }
            if (canCreate) {
                item {
                    OperationSectionHeader("Result List", modifier = Modifier.padding(top = 8.dp))
                    OutlinedTextField(
                        value = customName,
                        onValueChange = { customName = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp),
                        singleLine = true,
                        label = { Text("List name") },
                    )
                    InfoCaption(
                        "$totalItems unique item${if (totalItems == 1) "" else "s"} (pull counts summed)",
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
            }
        }
        if (canCreate) {
            AccentActionButton(
                label = "Create Union List",
                onClick = {
                    val finalName = customName.trim().ifEmpty { generatedName }
                    onCreate(selectedIds.toList(), finalName)
                    onDone()
                },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DiffOperationView(
    lists: List<InventoryNamedList>,
    onDiff: (String, String) -> ListDiffResult?,
    onSaveAsNewList: (String, List<InventoryListItem>) -> Unit,
) {
    var listAId by remember { mutableStateOf<String?>(null) }
    var listBId by remember { mutableStateOf<String?>(null) }
    var result by remember { mutableStateOf<ListDiffResult?>(null) }
    val canRun = listAId != null && listBId != null && listAId != listBId

    Column(Modifier.fillMaxSize()) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
        ) {
            OperationSectionHeader("Pick 2 lists to Compare")
            ListDropdownPicker(
                label = "List A",
                lists = lists,
                selectedId = listAId,
                onSelect = { listAId = it; result = null },
            )
            Spacer(Modifier.height(8.dp))
            ListDropdownPicker(
                label = "List B",
                lists = lists,
                selectedId = listBId,
                onSelect = { listBId = it; result = null },
            )
        }
        AccentActionButton(
            label = "Run Diff",
            enabled = canRun,
            onClick = {
                result = onDiff(listAId!!, listBId!!)
            },
            modifier = Modifier.padding(top = 8.dp),
        )
        result?.let { diff ->
            LazyColumn(
                modifier = Modifier
                    .weight(1f)
                    .padding(top = 8.dp),
            ) {
                item {
                    DiffSection(
                        title = "Common (${diff.common.size})",
                        items = diff.common,
                        defaultListName = "Common",
                        onSaveAsNewList = onSaveAsNewList,
                    )
                }
                item {
                    DiffSection(
                        title = "Only in ${diff.listAName} (${diff.onlyInA.size})",
                        items = diff.onlyInA,
                        defaultListName = "Only in ${diff.listAName}",
                        onSaveAsNewList = onSaveAsNewList,
                    )
                }
                item {
                    DiffSection(
                        title = "Only in ${diff.listBName} (${diff.onlyInB.size})",
                        items = diff.onlyInB,
                        defaultListName = "Only in ${diff.listBName}",
                        onSaveAsNewList = onSaveAsNewList,
                    )
                }
            }
        } ?: Spacer(Modifier.weight(1f))
    }
}

@Composable
private fun SplitOperationView(
    lists: List<InventoryNamedList>,
    onSplit: (String, ListStoreLogic.SplitMode, Int, String) -> Unit,
    onDone: () -> Unit,
) {
    var selectedListId by remember { mutableStateOf<String?>(null) }
    var splitByNumberOfLists by remember { mutableStateOf(true) }
    var splitValue by remember { mutableIntStateOf(3) }
    var prefix by remember { mutableStateOf("") }

    val selectedList = lists.firstOrNull { it.id == selectedListId }
    val effectivePrefix = prefix.trim().ifEmpty { selectedList?.name ?: "List" }
    val previewChunks = remember(selectedList, splitByNumberOfLists, splitValue) {
        computeSplitPreview(selectedList, splitByNumberOfLists, splitValue)
    }
    val canRun = selectedList != null && selectedList.items.isNotEmpty() && splitValue >= 1

    Column(Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 8.dp),
        ) {
            item {
                OperationSectionHeader("Select list to split")
            }
            items(lists, key = { it.id }) { list ->
                val isSelected = list.id == selectedListId
                ListSelectionRow(
                    name = list.name,
                    itemCount = list.items.size,
                    isSelected = isSelected,
                    onClick = {
                        selectedListId = list.id
                        prefix = list.name
                    },
                )
            }
            if (selectedList != null) {
                item {
                    OperationSectionHeader("Split Options", modifier = Modifier.padding(top = 8.dp))
                    SplitByPicker(
                        byNumberOfLists = splitByNumberOfLists,
                        onSelect = { splitByNumberOfLists = it },
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            if (splitByNumberOfLists) "Lists" else "Items / list",
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        StepperControl(
                            value = splitValue,
                            onValueChange = { splitValue = it.coerceIn(1, 999) },
                        )
                    }
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("Prefix", style = MaterialTheme.typography.bodyMedium)
                        Spacer(Modifier.width(12.dp))
                        TextField(
                            value = prefix,
                            onValueChange = { prefix = it },
                            modifier = Modifier.weight(1f),
                            singleLine = true,
                            colors = TextFieldDefaults.colors(
                                focusedContainerColor = Color.Transparent,
                                unfocusedContainerColor = Color.Transparent,
                                focusedTextColor = ListerAccent,
                                unfocusedTextColor = ListerAccent,
                            ),
                            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                        )
                    }
                    InfoCaption(
                        "Lists will be named $effectivePrefix-1, -2, …",
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
                if (previewChunks.isNotEmpty()) {
                    item {
                        OperationSectionHeader(
                            "Preview — ${previewChunks.size} list${if (previewChunks.size == 1) "" else "s"}",
                            modifier = Modifier.padding(top = 8.dp),
                        )
                    }
                    items(previewChunks.size) { idx ->
                        val size = previewChunks[idx]
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .background(
                                    if (idx % 2 == 0) {
                                        ListerHighlight.copy(alpha = 0.4f)
                                    } else {
                                        ListerBackground.copy(alpha = 0.5f)
                                    },
                                )
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            androidx.compose.material3.Icon(
                                Icons.Outlined.List,
                                contentDescription = null,
                                tint = ListerAccent,
                                modifier = Modifier.size(16.dp),
                            )
                            Spacer(Modifier.width(8.dp))
                            Text("$effectivePrefix-${idx + 1}", style = MaterialTheme.typography.bodyMedium)
                            Spacer(Modifier.weight(1f))
                            Text(
                                "$size item${if (size == 1) "" else "s"}",
                                style = MaterialTheme.typography.bodySmall,
                                color = ListerMuted,
                            )
                        }
                    }
                }
            }
        }
        if (canRun) {
            AccentActionButton(
                label = "Split List",
                onClick = {
                    val mode = if (splitByNumberOfLists) {
                        ListStoreLogic.SplitMode.ByNumberOfLists
                    } else {
                        ListStoreLogic.SplitMode.ByItemsPerList
                    }
                    onSplit(selectedListId!!, mode, splitValue, prefix)
                    onDone()
                },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SortOperationView(
    lists: List<InventoryNamedList>,
    onSort: (String, ListSortField, Boolean) -> Unit,
    onDone: () -> Unit,
) {
    var selectedListId by remember { mutableStateOf<String?>(null) }
    var sortField by remember { mutableStateOf(ListSortField.Name) }
    var ascending by remember { mutableStateOf(true) }

    val selectedList = lists.firstOrNull { it.id == selectedListId }
    val previewItems = remember(selectedList, sortField, ascending) {
        selectedList?.items?.let { ListSortLogic.sorted(it, sortField, ascending) }.orEmpty()
    }
    val canRun = selectedList != null && selectedList.items.isNotEmpty()

    Column(Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 8.dp),
        ) {
            item {
                OperationSectionHeader("Select list to sort")
            }
            items(lists, key = { it.id }) { list ->
                val isSelected = list.id == selectedListId
                ListSelectionRow(
                    name = list.name,
                    itemCount = list.items.size,
                    isSelected = isSelected,
                    onClick = { selectedListId = list.id },
                )
            }
            if (selectedList != null) {
                item {
                    OperationSectionHeader("Sort Options", modifier = Modifier.padding(top = 8.dp))
                    var fieldExpanded by remember { mutableStateOf(false) }
                    ExposedDropdownMenuBox(
                        expanded = fieldExpanded,
                        onExpandedChange = { fieldExpanded = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 4.dp),
                    ) {
                        OutlinedTextField(
                            value = sortField.label,
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("Sort by") },
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = fieldExpanded) },
                            modifier = Modifier
                                .menuAnchor()
                                .fillMaxWidth(),
                        )
                        ExposedDropdownMenu(
                            expanded = fieldExpanded,
                            onDismissRequest = { fieldExpanded = false },
                        ) {
                            ListSortField.entries.forEach { field ->
                                DropdownMenuItem(
                                    text = { Text(field.label) },
                                    onClick = {
                                        sortField = field
                                        fieldExpanded = false
                                    },
                                )
                            }
                        }
                    }
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                    ) {
                        listOf(true to "Ascending", false to "Descending").forEach { (value, label) ->
                            val selected = ascending == value
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .padding(horizontal = 2.dp)
                                    .clip(RoundedCornerShape(20.dp))
                                    .background(if (selected) ListerPanel else SegmentedTrack)
                                    .clickable { ascending = value }
                                    .padding(vertical = 10.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    label,
                                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                                    color = if (selected) ListerPrimary else ListerMuted,
                                )
                            }
                        }
                    }
                }
                if (previewItems.isNotEmpty()) {
                    item {
                        OperationSectionHeader("Preview", modifier = Modifier.padding(top = 8.dp))
                    }
                    items(previewItems.take(5).size) { index ->
                        val item = previewItems[index]
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .background(
                                    if (index % 2 == 0) {
                                        ListerHighlight.copy(alpha = 0.4f)
                                    } else {
                                        ListerBackground.copy(alpha = 0.5f)
                                    },
                                )
                                .padding(horizontal = 16.dp, vertical = 10.dp),
                        ) {
                            Text(
                                "${index + 1}.",
                                style = MaterialTheme.typography.bodySmall,
                                color = ListerMuted,
                                modifier = Modifier.width(24.dp),
                            )
                            Column {
                                Text(
                                    item.name.ifEmpty { item.productId.toString() },
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                                Text(
                                    sortPreviewDetail(item, sortField),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = ListerMuted,
                                )
                            }
                        }
                    }
                    if (previewItems.size > 5) {
                        item {
                            Text(
                                "+ ${previewItems.size - 5} more",
                                style = MaterialTheme.typography.bodySmall,
                                color = ListerMuted,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                            )
                        }
                    }
                }
            }
        }
        if (canRun) {
            AccentActionButton(
                label = "Sort List",
                onClick = {
                    onSort(selectedListId!!, sortField, ascending)
                    onDone()
                },
            )
        }
    }
}

@Composable
private fun QueryOperationView(
    lists: List<InventoryNamedList>,
    batchProgress: String?,
    onBatchQuery: (String, String) -> Unit,
    onCancelBatch: () -> Unit,
) {
    var selectedListId by remember { mutableStateOf<String?>(null) }
    var customName by remember { mutableStateOf("") }

    val selectedList = lists.firstOrNull { it.id == selectedListId }
    val canRun = selectedList != null && selectedList.items.isNotEmpty()
    val isRunning = batchProgress != null
    val progressParts = batchProgress?.split("/")?.mapNotNull { it.trim().toIntOrNull() }
    val progressCurrent = progressParts?.getOrNull(0) ?: 0
    val progressTotal = progressParts?.getOrNull(1) ?: 1

    Column(Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 8.dp),
        ) {
            item {
                Row(
                    Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    androidx.compose.material3.Icon(
                        Icons.Default.Bolt,
                        contentDescription = null,
                        tint = ListerAccent,
                        modifier = Modifier.size(16.dp),
                    )
                    Text(
                        "Re-queries each item by product ID via the Cloud Store API. Pull counts are preserved; " +
                            "name, price, and stock are refreshed.",
                        style = MaterialTheme.typography.bodySmall,
                        color = ListerMuted,
                    )
                }
                OperationSectionHeader("Select list to re-query")
            }
            items(lists, key = { it.id }) { list ->
                val isSelected = list.id == selectedListId
                ListSelectionRow(
                    name = list.name,
                    itemCount = list.items.size,
                    isSelected = isSelected,
                    onClick = {
                        selectedListId = list.id
                        customName = "${list.name}-BQ"
                    },
                )
            }
            if (selectedList != null) {
                item {
                    OperationSectionHeader("Result List", modifier = Modifier.padding(top = 8.dp))
                    OutlinedTextField(
                        value = customName,
                        onValueChange = { customName = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp),
                        singleLine = true,
                        label = { Text("List name") },
                    )
                    InfoCaption(
                        "Creates a new list with fresh stock and price data",
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
            }
        }
        when {
            isRunning -> {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .background(ListerBackground)
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    LinearProgressIndicator(
                        progress = { progressCurrent.toFloat() / progressTotal.coerceAtLeast(1) },
                        modifier = Modifier.fillMaxWidth(),
                        color = ListerAccent,
                    )
                    Text(
                        "Querying $progressCurrent of $progressTotal…",
                        style = MaterialTheme.typography.bodyMedium,
                        color = ListerMuted,
                    )
                    AccentActionButton(
                        label = "Stop",
                        containerColor = Color(0xFFDC2626),
                        leadingIcon = Icons.Default.Stop,
                        onClick = onCancelBatch,
                    )
                }
            }
            canRun -> {
                AccentActionButton(
                    label = "Run List Query",
                    leadingIcon = Icons.Default.Refresh,
                    onClick = { onBatchQuery(selectedListId!!, customName) },
                )
            }
        }
    }
}

@Composable
private fun ListSelectionRow(
    name: String,
    itemCount: Int,
    isSelected: Boolean,
    onClick: () -> Unit,
) {
    val rowBackground = if (isSelected) ListerHighlight else ListerBackground.copy(alpha = 0.5f)
    Column(
        Modifier
            .fillMaxWidth()
            .background(rowBackground)
            .clickable(onClick = onClick),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                Modifier
                    .width(4.dp)
                    .height(36.dp)
                    .clip(RoundedCornerShape(3.dp))
                    .background(if (isSelected) ListerAccent else ListerHighlight),
            )
            androidx.compose.material3.Icon(
                imageVector = if (isSelected) Icons.Default.CheckCircle else Icons.Outlined.Circle,
                contentDescription = null,
                tint = if (isSelected) ListerAccent else ListerMuted,
                modifier = Modifier.size(24.dp),
            )
            Column(Modifier.weight(1f)) {
                Text(
                    name,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (isSelected) ListerAccent else MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    "$itemCount item${if (itemCount == 1) "" else "s"}",
                    style = MaterialTheme.typography.bodySmall,
                    color = ListerMuted,
                )
            }
        }
        HorizontalDivider(color = ListerHighlight.copy(alpha = 0.6f))
    }
}

@Composable
private fun OperationSectionHeader(
    title: String,
    modifier: Modifier = Modifier,
) {
    Text(
        title,
        modifier = modifier.padding(horizontal = 16.dp, vertical = 10.dp),
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
        color = ListerPrimary,
    )
}

@Composable
private fun InfoCaption(
    text: String,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Top,
    ) {
        androidx.compose.material3.Icon(
            Icons.Default.Info,
            contentDescription = null,
            tint = ListerMuted,
            modifier = Modifier.size(16.dp),
        )
        Text(text, style = MaterialTheme.typography.bodySmall, color = ListerMuted)
    }
}

@Composable
private fun AccentActionButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    containerColor: Color = ListerAccent,
    leadingIcon: androidx.compose.ui.graphics.vector.ImageVector? = null,
) {
    Box(
        modifier
            .fillMaxWidth()
            .background(ListerBackground)
            .padding(16.dp),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .height(45.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(if (enabled) containerColor else containerColor.copy(alpha = 0.4f))
                .clickable(enabled = enabled, onClick = onClick),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (leadingIcon != null) {
                androidx.compose.material3.Icon(
                    leadingIcon,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier
                        .padding(end = 8.dp)
                        .size(20.dp),
                )
            }
            Text(
                label,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ListDropdownPicker(
    label: String,
    lists: List<InventoryNamedList>,
    selectedId: String?,
    onSelect: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedName = lists.firstOrNull { it.id == selectedId }?.name ?: "Select…"

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = Modifier.fillMaxWidth(),
    ) {
        OutlinedTextField(
            value = selectedName,
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .menuAnchor()
                .fillMaxWidth(),
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            lists.forEach { list ->
                DropdownMenuItem(
                    text = { Text(list.name) },
                    onClick = {
                        onSelect(list.id)
                        expanded = false
                    },
                )
            }
        }
    }
}

@Composable
private fun DiffSection(
    title: String,
    items: List<InventoryListItem>,
    defaultListName: String,
    onSaveAsNewList: (String, List<InventoryListItem>) -> Unit,
) {
    var showNameDialog by remember { mutableStateOf(false) }
    var listName by remember { mutableStateOf(defaultListName) }

    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Box(
                Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(ListerPrimary),
            )
            Text(
                title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = ListerPrimary,
            )
        }
        if (items.isEmpty()) {
            Text(
                "No items",
                style = MaterialTheme.typography.bodyMedium,
                color = ListerMuted,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
        } else {
            items.forEach { item ->
                Column(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    Text(
                        item.name.ifEmpty { item.productId.toString() },
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            item.productId.toString(),
                            style = MaterialTheme.typography.bodySmall,
                            color = ListerMuted,
                            fontFamily = FontFamily.Monospace,
                        )
                        item.productType?.takeIf { it.isNotEmpty() }?.let { type ->
                            Text(type, style = MaterialTheme.typography.bodySmall, color = ListerMuted)
                        }
                    }
                }
            }
            TextButton(
                onClick = {
                    listName = defaultListName
                    showNameDialog = true
                },
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            ) {
                Text("Put into New List", color = ListerAccent, fontWeight = FontWeight.SemiBold)
            }
        }
    }

    if (showNameDialog) {
        AlertDialog(
            onDismissRequest = { showNameDialog = false },
            title = { Text("New List") },
            text = {
                Column {
                    Text("Enter a name for the new list")
                    OutlinedTextField(
                        value = listName,
                        onValueChange = { listName = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 12.dp),
                        singleLine = true,
                        label = { Text("List name") },
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onSaveAsNewList(listName, items)
                        showNameDialog = false
                    },
                ) { Text("Create") }
            },
            dismissButton = {
                TextButton(onClick = { showNameDialog = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun StepperControl(value: Int, onValueChange: (Int) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        TextButton(onClick = { onValueChange(value - 1) }) { Text("−") }
        Text(
            value.toString(),
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 8.dp),
        )
        TextButton(onClick = { onValueChange(value + 1) }) { Text("+") }
    }
}

private fun computeSplitPreview(
    list: InventoryNamedList?,
    byNumberOfLists: Boolean,
    splitValue: Int,
): List<Int> {
    if (list == null || list.items.isEmpty()) return emptyList()
    val total = list.items.size
    val n = maxOf(1, splitValue)
    val chunkSize = if (byNumberOfLists) {
        ceil(total.toDouble() / n).toInt()
    } else {
        n
    }
    val sizes = mutableListOf<Int>()
    var offset = 0
    while (offset < total) {
        sizes.add(min(chunkSize, total - offset))
        offset += chunkSize
    }
    return sizes
}

private fun sortPreviewDetail(item: InventoryListItem, field: ListSortField): String {
    return when (field) {
        ListSortField.Name -> item.productId.toString()
        ListSortField.ProductType -> item.productType?.takeIf { it.isNotEmpty() } ?: "—"
        ListSortField.ProductId -> item.name
        ListSortField.Barcode -> item.barcode ?: "—"
        ListSortField.Price -> item.priceLabel
        ListSortField.Stock -> item.stockLabel
        ListSortField.PullCount -> "Pull: ${item.pullCount}"
    }
}
