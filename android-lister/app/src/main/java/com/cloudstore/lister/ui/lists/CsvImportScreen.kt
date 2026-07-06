package com.cloudstore.lister.ui.lists

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cloudstore.lister.data.InventoryNamedList
import com.cloudstore.lister.domain.CsvFieldMapping
import com.cloudstore.lister.domain.CsvImportLogic
import com.cloudstore.lister.domain.CsvImportableField
import com.cloudstore.lister.domain.ParsedCsv
import com.cloudstore.lister.ui.theme.ListerAccent
import com.cloudstore.lister.ui.theme.ListerBackground
import com.cloudstore.lister.ui.theme.ListerMuted
import com.cloudstore.lister.ui.theme.ListerPanel
import com.cloudstore.lister.ui.theme.ListerPrimary

private enum class ImportDestination { Existing, NewList }

private val SegmentedTrack = Color(0xFFE5E1D8)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CsvImportScreen(
    lists: List<InventoryNamedList>,
    activeListId: String,
    onClose: () -> Unit,
    onImport: (ParsedCsv, CsvFieldMapping, String?, String) -> Unit,
) {
    val context = LocalContext.current
    var destination by remember { mutableStateOf(ImportDestination.Existing) }
    var selectedListId by remember { mutableStateOf(activeListId) }
    var newListName by remember { mutableStateOf("") }
    var parsed by remember { mutableStateOf<ParsedCsv?>(null) }
    var mapping by remember { mutableStateOf(CsvFieldMapping()) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        runCatching {
            context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
        }.onSuccess { content ->
            if (content.isNullOrBlank()) {
                errorMessage = "The file is empty."
                parsed = null
            } else {
                val p = CsvImportLogic.parseCsv(content)
                if (p == null) {
                    errorMessage = "The file is empty."
                    parsed = null
                } else {
                    parsed = p
                    mapping = CsvImportLogic.suggestedMapping(p)
                    errorMessage = null
                }
            }
        }.onFailure { errorMessage = it.message }
    }

    val canImport = parsed != null &&
        mapping.productIdColumn != null &&
        (destination == ImportDestination.Existing || newListName.trim().isNotEmpty())

    Scaffold(
        containerColor = ListerBackground,
        topBar = {
            TopAppBar(
                title = { Text("Import CSV") },
                navigationIcon = {
                    TextButton(onClick = onClose, modifier = Modifier.padding(start = 4.dp)) {
                        Text("Cancel", color = Color.White, fontWeight = FontWeight.SemiBold)
                    }
                },
                actions = {
                    TextButton(
                        onClick = {
                            val p = parsed ?: return@TextButton
                            val targetId = if (destination == ImportDestination.Existing) {
                                selectedListId
                            } else {
                                null
                            }
                            val name = if (destination == ImportDestination.NewList) newListName else ""
                            onImport(p, mapping, targetId, name)
                        },
                        enabled = canImport,
                    ) {
                        Text(
                            "Import",
                            color = Color.White,
                            fontWeight = FontWeight.SemiBold,
                        )
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
            item {
                CsvSectionHeader("CSV File")
                Column(Modifier.padding(horizontal = 16.dp)) {
                    ImportDestinationPicker(
                        selected = destination,
                        onSelect = { destination = it },
                    )
                    if (destination == ImportDestination.Existing) {
                        ListDestinationPicker(
                            lists = lists,
                            selectedId = selectedListId,
                            onSelect = { selectedListId = it },
                            modifier = Modifier.padding(top = 8.dp),
                        )
                    } else {
                        OutlinedTextField(
                            value = newListName,
                            onValueChange = { newListName = it },
                            label = { Text("New list name") },
                            singleLine = true,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 8.dp),
                        )
                    }
                    TextButton(
                        onClick = { picker.launch(arrayOf("text/*", "text/csv", "application/csv")) },
                        modifier = Modifier.padding(top = 4.dp),
                    ) {
                        Icon(Icons.Default.Description, contentDescription = null, tint = ListerAccent)
                        Text(
                            if (parsed == null) "Choose CSV File" else "Choose Different File",
                            modifier = Modifier.padding(start = 8.dp),
                            color = ListerAccent,
                        )
                    }
                }
            }

            parsed?.let { csv ->
                item {
                    CsvSectionHeader("Required Column")
                    Column(Modifier.padding(horizontal = 16.dp)) {
                        CsvColumnPicker(
                            label = "Product ID",
                            headers = csv.headers,
                            selected = mapping.productIdColumn,
                            onSelect = { mapping = mapping.copy(productIdColumn = it) },
                        )
                        Text(
                            "Product ID is required. Map it to the column that contains each item's numeric product ID.",
                            style = MaterialTheme.typography.bodySmall,
                            color = ListerMuted,
                            modifier = Modifier.padding(top = 8.dp, bottom = 8.dp),
                        )
                    }
                }

                item {
                    CsvSectionHeader("Optional Columns")
                    Text(
                        "Enable only the fields you want to import from the CSV. Unmapped fields use defaults (— or empty).",
                        style = MaterialTheme.typography.bodySmall,
                        color = ListerMuted,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                    )
                }

                items(CsvImportableField.optionalFields, key = { it.name }) { field ->
                    OptionalCsvFieldRow(
                        field = field,
                        headers = csv.headers,
                        mapping = mapping,
                        onMappingChange = { mapping = it },
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                    )
                }

                item {
                    CsvSectionHeader("Preview")
                    Text(
                        "${csv.rows.size} row${if (csv.rows.size == 1) "" else "s"} detected",
                        style = MaterialTheme.typography.bodyMedium,
                        color = ListerMuted,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
            }

            errorMessage?.let { message ->
                item {
                    Text(
                        message,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun ImportDestinationPicker(
    selected: ImportDestination,
    onSelect: (ImportDestination) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(SegmentedTrack)
            .padding(4.dp),
    ) {
        listOf(ImportDestination.Existing to "Existing List", ImportDestination.NewList to "New List")
            .forEach { (value, label) ->
                val isSelected = selected == value
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(20.dp))
                        .background(if (isSelected) ListerPanel else Color.Transparent)
                        .clickable { onSelect(value) }
                        .padding(vertical = 10.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        label,
                        fontSize = 13.sp,
                        fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                        color = if (isSelected) ListerPrimary else ListerMuted,
                    )
                }
            }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ListDestinationPicker(
    lists: List<InventoryNamedList>,
    selectedId: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedName = lists.firstOrNull { it.id == selectedId }?.name ?: "Select list…"

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = modifier.fillMaxWidth(),
    ) {
        OutlinedTextField(
            value = selectedName,
            onValueChange = {},
            readOnly = true,
            label = { Text("List") },
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CsvColumnPicker(
    label: String,
    headers: List<String>,
    selected: String?,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    val display = selected?.takeIf { it.isNotEmpty() } ?: "Select column…"

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = modifier.fillMaxWidth(),
    ) {
        OutlinedTextField(
            value = display,
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
            headers.forEach { header ->
                DropdownMenuItem(
                    text = { Text(header) },
                    onClick = {
                        onSelect(header)
                        expanded = false
                    },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun OptionalCsvFieldRow(
    field: CsvImportableField,
    headers: List<String>,
    mapping: CsvFieldMapping,
    onMappingChange: (CsvFieldMapping) -> Unit,
    modifier: Modifier = Modifier,
) {
    val enabled = mapping.enabledFields.contains(field)

    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(ListerBackground.copy(alpha = 0.5f))
            .padding(12.dp),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(field.label, style = MaterialTheme.typography.bodyLarge)
            Switch(
                checked = enabled,
                onCheckedChange = { checked ->
                    onMappingChange(mapping.withFieldEnabled(field, checked, headers))
                },
                colors = SwitchDefaults.colors(
                    checkedThumbColor = Color.White,
                    checkedTrackColor = ListerAccent,
                    uncheckedThumbColor = Color.White,
                    uncheckedTrackColor = ListerMuted.copy(alpha = 0.4f),
                ),
            )
        }
        if (enabled) {
            CsvColumnPicker(
                label = "Column",
                headers = headers,
                selected = mapping.columnByField[field],
                onSelect = { column ->
                    onMappingChange(
                        mapping.copy(
                            columnByField = mapping.columnByField.toMutableMap().apply {
                                this[field] = column
                            },
                        ),
                    )
                },
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }
}

@Composable
private fun CsvSectionHeader(title: String) {
    Text(
        title,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
        color = ListerPrimary,
    )
}

private fun CsvFieldMapping.withFieldEnabled(
    field: CsvImportableField,
    enabled: Boolean,
    headers: List<String>,
): CsvFieldMapping {
    val newEnabled = enabledFields.toMutableSet()
    val newColumns = columnByField.toMutableMap()
    if (enabled) {
        newEnabled.add(field)
        if (newColumns[field] == null) {
            val guessed = CsvImportLogic.guessColumn(field, headers) ?: headers.firstOrNull()
            if (guessed != null) {
                newColumns[field] = guessed
            }
        }
    } else {
        newEnabled.remove(field)
        newColumns.remove(field)
    }
    return copy(enabledFields = newEnabled, columnByField = newColumns)
}
