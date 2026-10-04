package jiamin.chen.orangecloud.ui.storage

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.TableRows
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import jiamin.chen.orangecloud.R
import jiamin.chen.orangecloud.core.design.SkyBackground
import jiamin.chen.orangecloud.core.design.SkyEmptyState
import jiamin.chen.orangecloud.core.design.SkyHeader
import jiamin.chen.orangecloud.core.design.onSky
import jiamin.chen.orangecloud.core.design.rememberSkyPhase
import jiamin.chen.orangecloud.core.design.theme.OcOrange
import jiamin.chen.orangecloud.data.model.D1Column
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive

/** D1 表浏览器：列结构 + rowid 分页行，点行进编辑器（仅更新变更列）。对齐 iOS D1TableView。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun D1TableScreen(
    onBack: () -> Unit,
    viewModel: D1TableViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    var editingRow by remember { mutableStateOf<Map<String, JsonElement>?>(null) }
    val snackbarHostState = remember { SnackbarHostState() }
    val readonlyMsg = stringResource(R.string.d1_row_readonly)
    val dailyLimitMsg = stringResource(R.string.d1_daily_limit)

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                D1RowEvent.Saved, D1RowEvent.Deleted -> editingRow = null
                is D1RowEvent.Error -> snackbarHostState.showSnackbar(
                    event.message?.let { if (isD1DailyLimitError(it)) "$dailyLimitMsg\n\n$it" else it } ?: readonlyMsg,
                )
            }
        }
    }

    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().systemBarsPadding()) {
                SkyHeader(
                    title = viewModel.tableName,
                    onSky = onSky,
                    isLoading = state.isLoading && state.rows.isNotEmpty(),
                    onRefresh = { viewModel.load() },
                    onBack = onBack,
                    titleSize = 22,
                    backDescription = stringResource(R.string.common_back),
                    refreshDescription = stringResource(R.string.common_refresh),
                )
                when {
                    state.missingScope ->
                        SkyEmptyState(Icons.Outlined.TableRows, stringResource(R.string.scope_missing), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }

                    state.rows.isEmpty() && state.isLoading ->
                        Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = onSky) }

                    state.rows.isEmpty() && state.error != null ->
                        SkyEmptyState(
                            Icons.Outlined.TableRows,
                            // 额度用尽时给出原因与原文，而不是笼统的「出错了」
                            state.error?.takeIf { isD1DailyLimitError(it) }?.let { d1ErrorText(it) }
                                ?: stringResource(R.string.error_generic),
                            onSky,
                            stringResource(R.string.common_refresh),
                        ) { viewModel.load() }

                    state.rows.isEmpty() ->
                        SkyEmptyState(Icons.Outlined.TableRows, stringResource(R.string.d1_table_empty), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }

                    else -> Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        DataGrid(
                            columns = state.columns,
                            rows = state.rows,
                            onRowClick = { row ->
                                if (state.canWrite) editingRow = row
                            },
                        )
                        if (state.hasMore) {
                            OutlinedButton(
                                onClick = { viewModel.loadMore() },
                                enabled = !state.isLoading,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text(stringResource(if (state.isLoading) R.string.common_loading else R.string.common_load_more))
                            }
                        }
                        if (state.indexesLoaded) {
                            IndexCard(state.indexes)
                        }
                        Text(
                            stringResource(if (state.canWrite) R.string.d1_row_tap_edit else R.string.d1_row_readonly_hint),
                            color = onSky.copy(alpha = 0.7f),
                            fontSize = 12.sp,
                        )
                    }
                }
            }
            SnackbarHost(snackbarHostState, Modifier.align(Alignment.BottomCenter).systemBarsPadding())
        }
    }

    editingRow?.let { row ->
        val rowid = (row[D1TableViewModel.ROWID_KEY] as? JsonPrimitive)?.content.orEmpty()
        ModalBottomSheet(
            onDismissRequest = { if (!state.isSaving) editingRow = null },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            RowEditor(
                row = row,
                rowid = rowid,
                columns = state.columns,
                canWrite = state.canWrite,
                isSaving = state.isSaving,
                onSave = { changes -> viewModel.updateRow(rowid, changes) },
                onDelete = { viewModel.deleteRow(rowid) },
            )
        }
    }
}

// MARK: - 表结构索引卡（PRAGMA index_list）

/** 索引清单：索引名 + 唯一标记 + 来源（主键 / UNIQUE 约束 / CREATE INDEX）。 */
@Composable
private fun IndexCard(indexes: List<D1IndexInfo>) {
    androidx.compose.material3.Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                stringResource(R.string.d1_index_section),
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            if (indexes.isEmpty()) {
                Text(
                    stringResource(R.string.d1_index_empty),
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                indexes.forEach { index ->
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            index.name,
                            fontSize = 12.sp,
                            fontFamily = FontFamily.Monospace,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.weight(1f),
                        )
                        if (index.unique) {
                            Text(
                                stringResource(R.string.d1_index_unique),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                                color = OcOrange,
                            )
                            Spacer(Modifier.width(8.dp))
                        }
                        Text(
                            stringResource(
                                when (index.origin) {
                                    "pk" -> R.string.d1_index_origin_pk
                                    "u" -> R.string.d1_index_origin_unique
                                    else -> R.string.d1_index_origin_create
                                },
                            ),
                            fontSize = 11.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 数据网格（横向滚动，表头 + 数据行）

@Composable
private fun DataGrid(
    columns: List<D1Column>,
    rows: List<Map<String, JsonElement>>,
    onRowClick: (Map<String, JsonElement>) -> Unit,
) {
    val cellWidth = 150.dp
    androidx.compose.material3.Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.horizontalScroll(rememberScrollState()).padding(12.dp)) {
            Row {
                columns.forEach { column ->
                    Column(Modifier.width(cellWidth).padding(end = 8.dp, bottom = 6.dp)) {
                        Row {
                            Text(
                                column.name,
                                fontWeight = FontWeight.Bold,
                                fontSize = 12.sp,
                                fontFamily = FontFamily.Monospace,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                            if (column.isPrimaryKey) {
                                Text(
                                    " PK",
                                    fontSize = 9.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = OcOrange,
                                )
                            }
                        }
                        Text(
                            column.type.ifEmpty { "—" },
                            fontSize = 10.sp,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                        )
                    }
                }
            }
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            rows.forEach { row ->
                Row(
                    Modifier
                        .clickable { onRowClick(row) }
                        .padding(vertical = 7.dp),
                ) {
                    columns.forEach { column ->
                        val value = row[column.name]
                        Text(
                            value.d1Display(),
                            modifier = Modifier.width(cellWidth).padding(end = 8.dp),
                            fontSize = 12.sp,
                            fontFamily = FontFamily.Monospace,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            color = if (value.d1IsNull()) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
                HorizontalDivider()
            }
        }
    }
}

// MARK: - 行编辑器（仅提交变更列）

@Composable
private fun RowEditor(
    row: Map<String, JsonElement>,
    rowid: String,
    columns: List<D1Column>,
    canWrite: Boolean,
    isSaving: Boolean,
    onSave: (Map<String, String>) -> Unit,
    onDelete: () -> Unit,
) {
    // rowid 别名只用于定位，不参与编辑
    val editable = remember(columns) { columns.filter { it.name != D1TableViewModel.ROWID_KEY } }
    val fields = remember(row) {
        mutableStateMapOf<String, String>().apply {
            editable.forEach { col -> put(col.name, row[col.name].d1Edit()) }
        }
    }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    // 仅变更的列：原值 NULL 且输入仍为空视为未变更
    fun changes(): Map<String, String> = buildMap {
        editable.forEach { col ->
            val original = row[col.name]
            val originalText = if (original.d1IsNull()) null else original.d1Edit()
            val current = fields[col.name].orEmpty()
            if (originalText == null) {
                if (current.isNotEmpty()) put(col.name, current)
            } else if (current != originalText) {
                put(col.name, current)
            }
        }
    }

    Column(
        Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            stringResource(R.string.d1_row_edit_title),
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            "rowid $rowid",
            fontSize = 12.sp,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        editable.forEach { col ->
            OutlinedTextField(
                value = fields[col.name].orEmpty(),
                onValueChange = { fields[col.name] = it },
                label = {
                    Text(
                        buildString {
                            append(col.name)
                            if (col.isPrimaryKey) append(" · PK")
                            if (col.type.isNotEmpty()) append(" · ${col.type}")
                        },
                    )
                },
                singleLine = !col.type.uppercase().contains("TEXT"),
                placeholder = { if (row[col.name].d1IsNull()) Text("NULL") },
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                    keyboardType = if (col.type.isNumericAffinity()) KeyboardType.Number else KeyboardType.Text,
                ),
                textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                enabled = canWrite && !isSaving,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        Text(
            stringResource(R.string.d1_row_changed_only),
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Button(
            onClick = { onSave(changes()) },
            enabled = canWrite && !isSaving && changes().isNotEmpty(),
            colors = ButtonDefaults.buttonColors(containerColor = OcOrange, contentColor = Color.White),
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (isSaving) {
                CircularProgressIndicator(Modifier.height(18.dp).width(18.dp), strokeWidth = 2.dp, color = Color.White)
                Spacer(Modifier.width(8.dp))
            }
            Text(stringResource(R.string.dns_save))
        }

        if (canWrite) {
            if (showDeleteConfirm) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { showDeleteConfirm = false }, enabled = !isSaving, modifier = Modifier.weight(1f)) {
                        Text(stringResource(R.string.common_cancel))
                    }
                    Button(
                        onClick = onDelete,
                        enabled = !isSaving,
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFE5484D), contentColor = Color.White),
                        modifier = Modifier.weight(1f),
                    ) {
                        Text(stringResource(R.string.d1_row_delete))
                    }
                }
            } else {
                TextButton(onClick = { showDeleteConfirm = true }, enabled = !isSaving, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Outlined.Delete, contentDescription = null, tint = Color(0xFFE5484D), modifier = Modifier.height(18.dp).width(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(stringResource(R.string.d1_row_delete), color = Color(0xFFE5484D))
                }
            }
        }
    }
}

// MARK: - JsonElement 单元格显示 / 编辑助手

private fun JsonElement?.d1IsNull(): Boolean = this == null || this is JsonNull

/** 文本框初始值：NULL → 空串，基础值 → 原文。 */
private fun JsonElement?.d1Edit(): String = when {
    this == null || this is JsonNull -> ""
    this is JsonPrimitive -> content
    else -> toString()
}

/** 网格显示：NULL → "NULL"，空串 → "''"。 */
private fun JsonElement?.d1Display(): String = when {
    this == null || this is JsonNull -> "NULL"
    this is JsonPrimitive -> content.ifEmpty { "''" }
    else -> toString()
}

/** SQLite 列类型亲和性是否为数值（决定编辑键盘类型）。 */
private fun String.isNumericAffinity(): Boolean {
    val t = uppercase()
    return listOf("INT", "REAL", "FLOA", "DOUB", "DEC", "NUM").any { t.contains(it) } && !t.contains("BOOL")
}
