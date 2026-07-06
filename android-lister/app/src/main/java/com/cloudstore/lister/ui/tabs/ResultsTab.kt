package com.cloudstore.lister.ui.tabs

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cloudstore.lister.data.InventoryNamedList
import com.cloudstore.lister.data.InventoryProduct
import com.cloudstore.lister.ui.theme.ListerAccent
import com.cloudstore.lister.ui.theme.ListerBackground
import com.cloudstore.lister.ui.theme.ListerPrimary

@Composable
fun ResultsTab(
    isLoading: Boolean,
    errorMessage: String?,
    product: InventoryProduct?,
    lists: List<InventoryNamedList>,
    activeListId: String,
    lastQuery: String,
    onAddToList: (InventoryProduct, String) -> Unit,
    onCreateList: (String) -> String?,
) {
    Column(
        Modifier
            .fillMaxSize()
            .background(ListerBackground),
    ) {
        when {
            isLoading -> {
                Column(
                    Modifier
                        .fillMaxSize()
                        .padding(24.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    CircularProgressIndicator(color = ListerPrimary)
                    Text("Looking up…", modifier = Modifier.padding(top = 12.dp))
                }
            }
            errorMessage != null -> {
                Column(
                    Modifier
                        .fillMaxSize()
                        .padding(24.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        if (lastQuery.isBlank()) "No Results" else "No Results for $lastQuery",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        errorMessage,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(top = 8.dp),
                    )
                }
            }
            product == null -> {
                Column(
                    Modifier
                        .fillMaxSize()
                        .padding(24.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        if (lastQuery.isBlank()) "No Results" else "No Results for $lastQuery",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        "Enter a product ID or barcode on the Input tab.",
                        modifier = Modifier.padding(top = 8.dp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            else -> {
                Column(
                    Modifier
                        .weight(1f)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    ProductCard(product)
                }
                AddToListBar(
                    product = product,
                    lists = lists,
                    activeListId = activeListId,
                    onAddToList = onAddToList,
                    onCreateList = onCreateList,
                )
            }
        }
    }
}

@Composable
private fun AddToListBar(
    product: InventoryProduct,
    lists: List<InventoryNamedList>,
    activeListId: String,
    onAddToList: (InventoryProduct, String) -> Unit,
    onCreateList: (String) -> String?,
) {
    var targetListId by remember { mutableStateOf<String?>(null) }
    var listMenuOpen by remember { mutableStateOf(false) }
    var showNewListAlert by remember { mutableStateOf(false) }
    var newListName by remember { mutableStateOf("") }

    LaunchedEffect(activeListId) {
        targetListId = null
    }

    val effectiveListId = targetListId ?: activeListId
    val targetListName = lists.firstOrNull { it.id == effectiveListId }?.name ?: "MyList"

    Column(
        Modifier
            .fillMaxWidth()
            .background(ListerBackground)
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Button(
                onClick = { onAddToList(product, effectiveListId) },
                modifier = Modifier
                    .weight(1f)
                    .height(45.dp),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = ListerAccent,
                    contentColor = Color.White,
                ),
            ) {
                Icon(Icons.Default.AddCircle, contentDescription = null, modifier = Modifier.padding(end = 6.dp))
                Text("Add to List", fontWeight = FontWeight.SemiBold)
            }

            Box(Modifier.weight(1f)) {
                Button(
                    onClick = { listMenuOpen = true },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(45.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = ListerPrimary,
                        contentColor = Color.White,
                    ),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("List:", style = MaterialTheme.typography.bodyMedium)
                        Text(
                            text = targetListName,
                            modifier = Modifier
                                .padding(horizontal = 4.dp)
                                .weight(1f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            fontWeight = FontWeight.Medium,
                        )
                        Icon(
                            Icons.Default.UnfoldMore,
                            contentDescription = "Choose list",
                        )
                    }
                }
                DropdownMenu(
                    expanded = listMenuOpen,
                    onDismissRequest = { listMenuOpen = false },
                ) {
                    lists.forEach { list ->
                        DropdownMenuItem(
                            text = {
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    Text(list.name)
                                    if (list.id == effectiveListId) {
                                        Text("✓", fontWeight = FontWeight.Bold)
                                    }
                                }
                            },
                            onClick = {
                                targetListId = list.id
                                listMenuOpen = false
                            },
                        )
                    }
                    HorizontalDivider()
                    DropdownMenuItem(
                        text = { Text("New List…") },
                        onClick = {
                            listMenuOpen = false
                            showNewListAlert = true
                        },
                    )
                }
            }
        }
    }

    if (showNewListAlert) {
        AlertDialog(
            onDismissRequest = {
                showNewListAlert = false
                newListName = ""
            },
            title = { Text("New List") },
            text = {
                Column {
                    Text("Enter a name for the new list", modifier = Modifier.padding(bottom = 12.dp))
                    OutlinedTextField(
                        value = newListName,
                        onValueChange = { newListName = it },
                        label = { Text("List name") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onCreateList(newListName)?.let { targetListId = it }
                        newListName = ""
                        showNewListAlert = false
                    },
                ) { Text("Create") }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        newListName = ""
                        showNewListAlert = false
                    },
                ) { Text("Cancel") }
            },
        )
    }
}
