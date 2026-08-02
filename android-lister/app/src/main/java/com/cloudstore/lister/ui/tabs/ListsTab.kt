package com.cloudstore.lister.ui.tabs

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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DriveFileMove
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt
import kotlinx.coroutines.launch
import com.cloudstore.lister.data.InventoryListItem
import com.cloudstore.lister.data.InventoryNamedList
import com.cloudstore.lister.domain.ListExportLogic
import com.cloudstore.lister.domain.ListSearchLogic
import com.cloudstore.lister.ui.theme.ListerAccent
import com.cloudstore.lister.ui.theme.ListerBackground
import com.cloudstore.lister.ui.theme.ListerDanger
import com.cloudstore.lister.ui.theme.ListerHighlight
import com.cloudstore.lister.ui.theme.ListerMuted
import com.cloudstore.lister.ui.theme.ListerPrimary
import com.cloudstore.lister.ui.theme.ListerRose
import com.cloudstore.lister.ui.theme.ListerRoseHighlight
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures

@Composable
fun ListsTab(
    lists: List<InventoryNamedList>,
    activeListId: String,
    onIncrement: (String) -> Unit,
    onDecrement: (String) -> Unit,
    onDeleteItem: (String) -> Unit,
    onCopyItem: (InventoryListItem, String) -> Unit,
    onMoveItem: (InventoryListItem, String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val active = lists.firstOrNull { it.id == activeListId }
    val items = active?.items.orEmpty()
    var searchQuery by remember { mutableStateOf("") }
    val filteredItems = remember(items, searchQuery) {
        ListSearchLogic.filtered(items, searchQuery)
    }
    val isFiltering = searchQuery.trim().isNotEmpty()
    val summary = ListExportLogic.summary(filteredItems)
    var transferItem by remember { mutableStateOf<InventoryListItem?>(null) }
    var transferMode by remember { mutableStateOf<ItemTransferMode?>(null) }
    var roseHighlightedIds by remember { mutableStateOf(setOf<String>()) }

    LaunchedEffect(activeListId) {
        roseHighlightedIds = emptySet()
        searchQuery = ""
    }

    val pendingItem = transferItem
    val pendingMode = transferMode
    if (pendingItem != null && pendingMode != null) {
        DestinationListPickerDialog(
            lists = lists,
            activeListId = activeListId,
            item = pendingItem,
            mode = pendingMode,
            onDismiss = {
                transferItem = null
                transferMode = null
            },
            onCopy = onCopyItem,
            onMove = onMoveItem,
        )
    }

    Box(
        modifier
            .fillMaxSize()
            .background(ListerBackground),
    ) {
        if (items.isEmpty()) {
            Column(
                Modifier
                    .fillMaxSize()
                    .padding(24.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("No Items", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(
                    "Items you add will appear here",
                    modifier = Modifier.padding(top = 8.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                contentPadding = PaddingValues(
                    horizontal = 16.dp,
                    vertical = 12.dp,
                ),
            ) {
                item(key = "list_search") {
                    ListSearchField(
                        query = searchQuery,
                        onQueryChange = { searchQuery = it },
                    )
                }
                item(key = "list_count_summary") {
                    ListCountSummary(
                        itemCount = summary.itemCount,
                        totalPullCount = summary.totalPullCount,
                        totalItemCount = if (isFiltering) items.size else null,
                    )
                }
                if (filteredItems.isEmpty()) {
                    item(key = "no_matches") {
                        Column(
                            Modifier
                                .fillMaxWidth()
                                .padding(vertical = 32.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Text(
                                "No Matches",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                "No items match \"${searchQuery.trim()}\"",
                                modifier = Modifier.padding(top = 8.dp),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                textAlign = TextAlign.Center,
                            )
                        }
                    }
                } else {
                    items(filteredItems, key = { it.id }) { item ->
                        val highlighted = item.id in roseHighlightedIds
                        SwipeActionsCard(
                            onCopy = {
                                transferItem = item
                                transferMode = ItemTransferMode.Copy
                            },
                            onMove = {
                                transferItem = item
                                transferMode = ItemTransferMode.Move
                            },
                            onDelete = { onDeleteItem(item.id) },
                            onLongPress = {
                                roseHighlightedIds = if (highlighted) {
                                    roseHighlightedIds - item.id
                                } else {
                                    roseHighlightedIds + item.id
                                }
                            },
                        ) {
                            ListItemCard(
                                item = item,
                                highlighted = highlighted,
                                onIncrement = { onIncrement(item.id) },
                                onDecrement = { onDecrement(item.id) },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun ListsTabDialogs(
    activeListName: String,
    itemCount: Int,
    showDeleteAll: Boolean,
    onDismissDeleteAll: () -> Unit,
    onConfirmDeleteAll: () -> Unit,
) {
    if (showDeleteAll) {
        AlertDialog(
            onDismissRequest = onDismissDeleteAll,
            title = { Text("Delete All Items?") },
            text = {
                Text(
                    "Are you sure you want to delete all $itemCount item(s) from $activeListName? " +
                        "This action cannot be undone.",
                )
            },
            confirmButton = {
                TextButton(onClick = onConfirmDeleteAll) { Text("Delete All") }
            },
            dismissButton = { TextButton(onClick = onDismissDeleteAll) { Text("Cancel") } },
        )
    }
}

@Composable
private fun ListSearchField(
    query: String,
    onQueryChange: (String) -> Unit,
) {
    OutlinedTextField(
        value = query,
        onValueChange = onQueryChange,
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        placeholder = { Text("Search list") },
        leadingIcon = {
            Icon(Icons.Default.Search, contentDescription = null, tint = ListerMuted)
        },
        trailingIcon = {
            if (query.isNotEmpty()) {
                IconButton(onClick = { onQueryChange("") }) {
                    Icon(Icons.Default.Clear, contentDescription = "Clear search")
                }
            }
        },
    )
}

@Composable
private fun ListCountSummary(
    itemCount: Int,
    totalPullCount: Int,
    totalItemCount: Int? = null,
) {
    val itemsLabel = if (itemCount == 1) "1 item" else "$itemCount items"
    val countLabel = if (totalItemCount != null) {
        "$itemsLabel of $totalItemCount · $totalPullCount pull"
    } else {
        "$itemsLabel · $totalPullCount pull"
    }
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(ListerHighlight)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            "List Count",
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = ListerAccent,
        )
        Text(
            countLabel,
            style = MaterialTheme.typography.bodyMedium,
            color = ListerMuted,
        )
    }
}

@Composable
private fun SwipeActionsCard(
    onCopy: () -> Unit,
    onMove: () -> Unit,
    onDelete: () -> Unit,
    onLongPress: () -> Unit,
    content: @Composable () -> Unit,
) {
    val density = LocalDensity.current
    val actionWidthPx = with(density) { 72.dp.toPx() }
    val maxReveal = actionWidthPx * 3f
    var offsetX by remember { mutableFloatStateOf(0f) }

    Box(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .matchParentSize(),
            horizontalArrangement = Arrangement.End,
        ) {
            SwipeActionButton(
                label = "Copy",
                icon = Icons.Filled.ContentCopy,
                color = ListerAccent,
                onClick = {
                    offsetX = 0f
                    onCopy()
                },
            )
            SwipeActionButton(
                label = "Move",
                icon = Icons.AutoMirrored.Filled.DriveFileMove,
                color = ListerRose,
                onClick = {
                    offsetX = 0f
                    onMove()
                },
            )
            SwipeActionButton(
                label = "Delete",
                icon = Icons.Filled.Delete,
                color = ListerPrimary,
                onClick = {
                    offsetX = 0f
                    onDelete()
                },
            )
        }

        Box(
            modifier = Modifier
                .offset { IntOffset(offsetX.roundToInt(), 0) }
                .pointerInput(Unit) {
                    detectTapGestures(onLongPress = { onLongPress() })
                }
                .pointerInput(Unit) {
                    detectHorizontalDragGestures(
                        onDragEnd = {
                            offsetX = if (offsetX < -maxReveal * 0.4f) -maxReveal else 0f
                        },
                        onHorizontalDrag = { _, dragAmount ->
                            offsetX = (offsetX + dragAmount).coerceIn(-maxReveal, 0f)
                        },
                    )
                },
        ) {
            content()
        }
    }
}

@Composable
private fun SwipeActionButton(
    label: String,
    icon: ImageVector,
    color: Color,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .width(72.dp)
            .fillMaxHeight()
            .background(color)
            .clickable(onClick = onClick)
            .padding(horizontal = 4.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            icon,
            contentDescription = label,
            tint = Color.White,
            modifier = Modifier.height(20.dp),
        )
        Text(
            label,
            color = Color.White,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
    }
}

private enum class ItemTransferMode { Copy, Move }

@Composable
private fun DestinationListPickerDialog(
    lists: List<InventoryNamedList>,
    activeListId: String,
    item: InventoryListItem,
    mode: ItemTransferMode,
    onDismiss: () -> Unit,
    onCopy: (InventoryListItem, String) -> Unit,
    onMove: (InventoryListItem, String) -> Unit,
) {
    val destinations = lists.filter { it.id != activeListId }
    val title = if (mode == ItemTransferMode.Copy) "Copy to List" else "Move to List"
    val displayName = item.name.ifEmpty { item.productId.toString() }
    val prompt = if (mode == ItemTransferMode.Copy) {
        "Copy \"$displayName\" to:"
    } else {
        "Move \"$displayName\" to:"
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            if (destinations.isEmpty()) {
                Text(
                    if (mode == ItemTransferMode.Copy) {
                        "Create another list to copy this item into."
                    } else {
                        "Create another list to move this item into."
                    },
                )
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(prompt)
                    destinations.forEach { list ->
                        TextButton(
                            onClick = {
                                when (mode) {
                                    ItemTransferMode.Copy -> onCopy(item, list.id)
                                    ItemTransferMode.Move -> onMove(item, list.id)
                                }
                                onDismiss()
                            },
                        ) {
                            Text("${list.name}  (${list.items.size})")
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

@Composable
private fun ListItemCard(
    item: InventoryListItem,
    highlighted: Boolean,
    onIncrement: () -> Unit,
    onDecrement: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(if (highlighted) ListerRoseHighlight else ListerHighlight)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        ListerFieldRow(label = "Name:", value = item.name, valueBold = true)
        ListerFieldDivider()
        ListerFieldRow(label = "Type:", value = item.productType?.takeIf { it.isNotBlank() } ?: "—")
        ListerFieldDivider()
        ListerFieldRow(label = "Product ID:", value = item.productId.toString())
        ListerFieldDivider()
        ListerFieldRow(label = "Price:", value = item.priceLabel)
        ListerFieldDivider()
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Text("Stock:", style = MaterialTheme.typography.bodyMedium, color = ListerMuted)
            Spacer(Modifier.weight(1f))
            Text(
                text = item.stockLabel,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = if (item.stockEmphasis) ListerDanger else MaterialTheme.colorScheme.onBackground,
                textAlign = TextAlign.End,
            )
        }
        ListerFieldDivider()
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Pull Count:", style = MaterialTheme.typography.bodyMedium)
            Spacer(Modifier.weight(1f))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                IconButton(onClick = onDecrement) {
                    Icon(
                        Icons.Default.RemoveCircle,
                        contentDescription = "Decrease pull count",
                        tint = ListerAccent,
                        modifier = Modifier.padding(0.dp),
                    )
                }
                Text(
                    text = "${item.pullCount}",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 4.dp),
                    textAlign = TextAlign.Center,
                )
                IconButton(onClick = onIncrement) {
                    Icon(
                        Icons.Default.AddCircle,
                        contentDescription = "Increase pull count",
                        tint = ListerAccent,
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AllListsScreen(
    lists: List<InventoryNamedList>,
    activeListId: String,
    onDismiss: () -> Unit,
    onSwitch: (String) -> Unit,
    onCreate: (String) -> String?,
    onRename: (String, String) -> Unit,
    onDelete: (String) -> Unit,
) {
    var showAddList by remember { mutableStateOf(false) }
    var newListName by remember { mutableStateOf("") }
    var revealedListId by remember { mutableStateOf<String?>(null) }
    var listToRename by remember { mutableStateOf<InventoryNamedList?>(null) }
    var renameText by remember { mutableStateOf("") }
    var listToDelete by remember { mutableStateOf<InventoryNamedList?>(null) }

    Scaffold(
        containerColor = ListerBackground,
        topBar = {
            TopAppBar(
                title = { Text("My Lists") },
                navigationIcon = {
                    TextButton(onClick = onDismiss, modifier = Modifier.padding(start = 4.dp)) {
                        Text("Done", color = Color.White, fontWeight = FontWeight.SemiBold)
                    }
                },
                actions = {
                    IconButton(onClick = { showAddList = true }) {
                        Icon(Icons.Default.Add, contentDescription = "New list", tint = Color.White)
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
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            items(lists, key = { it.id }) { list ->
                SwipeRevealListRow(
                    list = list,
                    isActive = list.id == activeListId,
                    isRevealed = revealedListId == list.id,
                    onRevealChange = { revealed ->
                        revealedListId = if (revealed) list.id else null
                    },
                    onSwitch = { onSwitch(list.id) },
                    onRename = {
                        revealedListId = null
                        listToRename = list
                        renameText = list.name
                    },
                    onDelete = {
                        revealedListId = null
                        listToDelete = list
                    },
                )
            }
        }
    }

    if (showAddList) {
        AlertDialog(
            onDismissRequest = { showAddList = false; newListName = "" },
            title = { Text("New List") },
            text = {
                Column {
                    Text("Enter a name for the new list")
                    OutlinedTextField(
                        value = newListName,
                        onValueChange = { newListName = it },
                        label = { Text("List name") },
                        singleLine = true,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp),
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    onCreate(newListName)
                    newListName = ""
                    showAddList = false
                    onDismiss()
                }) { Text("Create") }
            },
            dismissButton = {
                TextButton(onClick = { showAddList = false; newListName = "" }) { Text("Cancel") }
            },
        )
    }

    listToRename?.let { list ->
        AlertDialog(
            onDismissRequest = { listToRename = null },
            title = { Text("Rename List") },
            text = {
                Column {
                    Text("Enter a new name for this list")
                    OutlinedTextField(
                        value = renameText,
                        onValueChange = { renameText = it },
                        label = { Text("List name") },
                        singleLine = true,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp),
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    onRename(list.id, renameText)
                    listToRename = null
                }) { Text("Save") }
            },
            dismissButton = {
                TextButton(onClick = { listToRename = null }) { Text("Cancel") }
            },
        )
    }

    listToDelete?.let { list ->
        val isDefault = list.isDefault
        AlertDialog(
            onDismissRequest = { listToDelete = null },
            title = {
                Text(if (isDefault) "Clear ${list.name}?" else "Delete ${list.name}?")
            },
            text = {
                Text(
                    if (isDefault) {
                        "This will clear all ${list.items.size} item(s). The list itself will remain."
                    } else {
                        "This will permanently delete ${list.name} and all ${list.items.size} item(s) in it."
                    },
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    onDelete(list.id)
                    listToDelete = null
                }) { Text(if (isDefault) "Clear" else "Delete") }
            },
            dismissButton = {
                TextButton(onClick = { listToDelete = null }) { Text("Cancel") }
            },
        )
    }
}

private val ListerRename = Color(0xFFEA580C)
private const val LIST_SWIPE_ACTION_WIDTH_DP = 80

@Composable
private fun SwipeRevealListRow(
    list: InventoryNamedList,
    isActive: Boolean,
    isRevealed: Boolean,
    onRevealChange: (Boolean) -> Unit,
    onSwitch: () -> Unit,
    onRename: () -> Unit,
    onDelete: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val actionWidth = LIST_SWIPE_ACTION_WIDTH_DP.dp
    val renameEnabled = !list.isDefault
    val actionsCount = if (renameEnabled) 2 else 1
    val maxRevealPx = with(density) { (actionWidth * actionsCount).toPx() }
    val offsetX = remember(list.id, maxRevealPx) { Animatable(0f) }

    suspend fun snapOpen(open: Boolean) {
        offsetX.animateTo(if (open) -maxRevealPx else 0f, spring())
        onRevealChange(open)
    }

    LaunchedEffect(isRevealed, maxRevealPx) {
        val target = if (isRevealed) -maxRevealPx else 0f
        if (offsetX.value != target) {
            offsetX.animateTo(target, spring())
        }
    }

    Box(
        Modifier
            .fillMaxWidth()
            .clipToBounds(),
    ) {
        Row(
            Modifier
                .align(Alignment.CenterEnd)
                .height(64.dp),
        ) {
            if (renameEnabled) {
                ListSwipeAction(
                    label = "Rename",
                    icon = Icons.Default.Edit,
                    color = ListerRename,
                    width = actionWidth,
                    onClick = {
                        scope.launch { snapOpen(false) }
                        onRename()
                    },
                )
            }
            ListSwipeAction(
                label = if (list.isDefault) "Clear" else "Delete",
                icon = Icons.Default.Delete,
                color = ListerDanger,
                width = actionWidth,
                onClick = {
                    scope.launch { snapOpen(false) }
                    onDelete()
                },
            )
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .offset { IntOffset(offsetX.value.roundToInt(), 0) }
                .pointerInput(maxRevealPx) {
                    detectHorizontalDragGestures(
                        onHorizontalDrag = { _, dragAmount ->
                            scope.launch {
                                offsetX.snapTo(
                                    (offsetX.value + dragAmount).coerceIn(-maxRevealPx, 0f),
                                )
                            }
                        },
                        onDragEnd = {
                            scope.launch {
                                snapOpen(offsetX.value < -maxRevealPx / 2f)
                            }
                        },
                    )
                }
                .background(if (isActive) ListerHighlight else ListerBackground)
                .clickable {
                    if (offsetX.value < 0f) {
                        scope.launch { snapOpen(false) }
                    } else {
                        onSwitch()
                    }
                }
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                Modifier
                    .width(4.dp)
                    .height(40.dp)
                    .clip(RoundedCornerShape(3.dp))
                    .background(if (isActive) ListerAccent else ListerHighlight),
            )
            Column(Modifier.weight(1f)) {
                Text(
                    list.name,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = if (isActive) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (isActive) ListerAccent else MaterialTheme.colorScheme.onBackground,
                )
                Text(
                    "${list.items.size} item${if (list.items.size == 1) "" else "s"}",
                    style = MaterialTheme.typography.bodySmall,
                    color = ListerMuted,
                )
            }
            if (isActive) {
                Icon(
                    Icons.Default.CheckCircle,
                    contentDescription = null,
                    tint = ListerAccent,
                )
            }
        }
    }
}

@Composable
private fun ListSwipeAction(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    color: Color,
    width: androidx.compose.ui.unit.Dp,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .width(width)
            .fillMaxHeight()
            .background(color)
            .clickable(onClick = onClick)
            .padding(horizontal = 4.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(icon, contentDescription = label, tint = Color.White, modifier = Modifier.height(20.dp))
        Text(
            label,
            color = Color.White,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
    }
}
