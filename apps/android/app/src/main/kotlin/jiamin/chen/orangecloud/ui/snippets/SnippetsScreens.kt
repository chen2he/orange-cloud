package jiamin.chen.orangecloud.ui.snippets

import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
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
import jiamin.chen.orangecloud.data.model.SnippetRule
import jiamin.chen.orangecloud.ui.storage.StorageRow

@Composable
fun SnippetsListScreen(
    onBack: () -> Unit,
    onOpenSnippet: (String) -> Unit,
    onCreate: () -> Unit,
    viewModel: SnippetsViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky

    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize().systemBarsPadding()) {
            Column(Modifier.fillMaxSize()) {
                SkyHeader(
                    title = stringResource(R.string.snippets_title),
                    onSky = onSky,
                    isLoading = state.isLoading,
                    onRefresh = { viewModel.load() },
                    onBack = onBack,
                    titleSize = 22,
                    backDescription = stringResource(R.string.common_back),
                    refreshDescription = stringResource(R.string.common_refresh),
                )
                when {
                    state.missingScope ->
                        SkyEmptyState(Icons.Outlined.Lock, stringResource(R.string.scope_missing), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }

                    state.snippets.isEmpty() && state.isLoading ->
                        Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = onSky) }

                    state.snippets.isEmpty() && state.hasError ->
                        SkyEmptyState(Icons.Outlined.Code, stringResource(R.string.error_generic), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }

                    state.snippets.isEmpty() ->
                        SkyEmptyState(Icons.Outlined.Code, stringResource(R.string.snippets_empty), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }

                    else -> LazyColumn(
                        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 96.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        items(state.snippets, key = { it.snippetName }) { snippet ->
                            StorageRow(Icons.Outlined.Code, snippet.snippetName, onClick = { onOpenSnippet(snippet.snippetName) })
                        }
                    }
                }
            }
            if (state.canWrite) {
                FloatingActionButton(
                    onClick = onCreate,
                    containerColor = OcOrange,
                    contentColor = Color.White,
                    modifier = Modifier.align(Alignment.BottomEnd).padding(20.dp),
                ) {
                    Icon(Icons.Outlined.Add, contentDescription = stringResource(R.string.snippets_new))
                }
            }
        }
    }
}

@Composable
fun SnippetEditorScreen(
    onBack: () -> Unit,
    onClosed: () -> Unit,
    viewModel: SnippetEditorViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    val snackbarHostState = remember { SnackbarHostState() }
    val savedMsg = stringResource(R.string.dns_saved)
    val contentUnavailableMsg = stringResource(R.string.snippet_content_unavailable)
    val deletedMsg = stringResource(R.string.dns_deleted)
    val genericErr = stringResource(R.string.error_generic)
    val ruleSavedMsg = stringResource(R.string.snippets_rule_saved)
    val ruleGoneMsg = stringResource(R.string.snippets_rule_gone)
    var ruleEditTarget by remember { mutableStateOf<SnippetRuleTarget?>(null) }
    var ruleToDelete by remember { mutableStateOf<SnippetRule?>(null) }

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                SnippetEditEvent.ContentUnavailable -> snackbarHostState.showSnackbar(contentUnavailableMsg)
                SnippetEditEvent.Saved -> { snackbarHostState.showSnackbar(savedMsg); onClosed() }
                SnippetEditEvent.Deleted -> { snackbarHostState.showSnackbar(deletedMsg); onClosed() }
                SnippetEditEvent.RuleSaved -> snackbarHostState.showSnackbar(ruleSavedMsg)
                SnippetEditEvent.RuleGone -> snackbarHostState.showSnackbar(ruleGoneMsg)
                is SnippetEditEvent.Error -> snackbarHostState.showSnackbar(event.message ?: genericErr)
            }
        }
    }

    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize().systemBarsPadding()) {
            Column(Modifier.fillMaxSize()) {
                SkyHeader(
                    title = if (state.isNew) stringResource(R.string.snippets_new) else state.name,
                    onSky = onSky,
                    isLoading = state.isLoading || state.isSaving,
                    onRefresh = {},
                    onBack = onBack,
                    titleSize = 20,
                    backDescription = stringResource(R.string.common_back),
                )
                Column(
                    modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp).padding(bottom = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    if (state.isNew) {
                        OutlinedTextField(
                            value = state.name,
                            onValueChange = viewModel::updateName,
                            label = { Text(stringResource(R.string.snippets_name)) },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    OutlinedTextField(
                        value = state.code,
                        onValueChange = viewModel::updateCode,
                        label = { Text(stringResource(R.string.snippets_code)) },
                        textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                        modifier = Modifier.fillMaxWidth().weight(1f),
                    )
                    val rules by viewModel.rules.collectAsStateWithLifecycle()
                    val ruleBusyKey by viewModel.ruleBusyKey.collectAsStateWithLifecycle()
                    // 新建的 snippet 还没落地，先存了才能挂触发规则
                    if (!state.isNew) {
                        Surface(
                            color = MaterialTheme.colorScheme.surfaceContainerLow,
                            shape = RoundedCornerShape(14.dp),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Column(Modifier.padding(14.dp).heightIn(max = 260.dp).verticalScroll(rememberScrollState())) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(
                                        stringResource(R.string.snippets_rules, rules.size),
                                        fontSize = 13.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.weight(1f),
                                    )
                                    if (state.canWrite) {
                                        TextButton(onClick = { ruleEditTarget = SnippetRuleTarget(null) }) {
                                            Text(stringResource(R.string.tf_add), color = OcOrange, fontSize = 13.sp)
                                        }
                                    }
                                }
                                if (rules.isEmpty()) {
                                    Text(
                                        stringResource(R.string.snippets_rule_none),
                                        fontSize = 12.sp,
                                        color = OcOrange,
                                    )
                                } else {
                                    rules.forEach { rule ->
                                        Spacer(Modifier.height(6.dp))
                                        SnippetRuleRow(
                                            rule = rule,
                                            canWrite = state.canWrite,
                                            isBusy = ruleBusyKey == viewModel.ruleKey(rule),
                                            onEdit = { ruleEditTarget = SnippetRuleTarget(rule) },
                                            onToggle = { viewModel.setRuleEnabled(rule, it) },
                                            onDelete = { ruleToDelete = rule },
                                        )
                                    }
                                    Spacer(Modifier.height(8.dp))
                                    Text(
                                        stringResource(R.string.snippets_rule_hint),
                                        fontSize = 11.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                    if (state.canWrite) {
                        Button(
                            onClick = viewModel::save,
                            enabled = state.name.isNotBlank() && !state.isSaving && !state.isLoading,
                            colors = ButtonDefaults.buttonColors(containerColor = OcOrange, contentColor = Color.White),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            if (state.isSaving) {
                                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = Color.White)
                                Spacer(Modifier.width(8.dp))
                            }
                            Text(stringResource(R.string.dns_save))
                        }
                        if (!state.isNew) {
                            OutlinedButton(onClick = viewModel::delete, modifier = Modifier.fillMaxWidth()) {
                                Text(stringResource(R.string.dns_delete))
                            }
                        }
                    } else {
                        Text(stringResource(R.string.snippets_readonly), color = onSky.copy(alpha = 0.7f), fontSize = 13.sp)
                    }
                }
            }
            SnackbarHost(snackbarHostState, modifier = Modifier.align(Alignment.BottomCenter))
        }
    }

    ruleEditTarget?.let { target ->
        SnippetRuleDialog(
            existing = target.rule,
            onDismiss = { ruleEditTarget = null },
            onConfirm = { expression, description, enabled ->
                val rule = target.rule
                if (rule == null) {
                    viewModel.addRule(expression, description, enabled)
                } else {
                    viewModel.updateRule(rule, expression, description, enabled)
                }
                ruleEditTarget = null
            },
        )
    }

    ruleToDelete?.let { rule ->
        AlertDialog(
            onDismissRequest = { ruleToDelete = null },
            title = { Text(stringResource(R.string.snippets_rule_delete_title)) },
            text = { Text(stringResource(R.string.snippets_rule_delete_msg, ruleTitle(rule))) },
            confirmButton = {
                TextButton(onClick = { viewModel.deleteRule(rule); ruleToDelete = null }) {
                    Text(stringResource(R.string.dns_delete), color = Color(0xFFE5484D))
                }
            },
            dismissButton = {
                TextButton(onClick = { ruleToDelete = null }) { Text(stringResource(R.string.common_cancel)) }
            },
        )
    }
}

/** 规则编辑目标：rule == null 表示新增。 */
private data class SnippetRuleTarget(val rule: SnippetRule?)

@Composable
private fun ruleTitle(rule: SnippetRule): String =
    rule.description?.takeIf { it.isNotBlank() } ?: stringResource(R.string.snippets_rule_untitled)

@Composable
private fun SnippetRuleRow(
    rule: SnippetRule,
    canWrite: Boolean,
    isBusy: Boolean,
    onEdit: () -> Unit,
    onToggle: (Boolean) -> Unit,
    onDelete: () -> Unit,
) {
    val enabled = rule.enabled != false
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .let { if (canWrite) it.clickable(onClick = onEdit) else it },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f).padding(vertical = 4.dp)) {
            Text(
                ruleTitle(rule),
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = if (enabled) 1f else 0.5f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                rule.expression,
                fontSize = 12.sp,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (isBusy) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = OcOrange)
        } else if (canWrite) {
            Switch(checked = enabled, onCheckedChange = onToggle)
            IconButton(onClick = onDelete) {
                Icon(
                    Icons.Outlined.Delete,
                    contentDescription = stringResource(R.string.dns_delete),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun SnippetRuleDialog(
    existing: SnippetRule?,
    onDismiss: () -> Unit,
    onConfirm: (expression: String, description: String?, enabled: Boolean) -> Unit,
) {
    var description by remember { mutableStateOf(existing?.description.orEmpty()) }
    var expression by remember { mutableStateOf(existing?.expression.orEmpty()) }
    var enabled by remember { mutableStateOf(existing?.enabled != false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                stringResource(
                    if (existing == null) R.string.snippets_rule_add else R.string.snippets_rule_edit,
                ),
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = description,
                    onValueChange = { description = it },
                    label = { Text(stringResource(R.string.snippets_rule_desc)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = expression,
                    onValueChange = { expression = it },
                    label = { Text(stringResource(R.string.snippets_rule_expr)) },
                    textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                    minLines = 3,
                    maxLines = 6,
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    stringResource(R.string.snippets_rule_expr_hint),
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        stringResource(R.string.snippets_rule_enabled),
                        fontSize = 13.sp,
                        modifier = Modifier.weight(1f),
                    )
                    Switch(checked = enabled, onCheckedChange = { enabled = it })
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(expression.trim(), description.trim().ifBlank { null }, enabled) },
                enabled = expression.isNotBlank(),
            ) {
                Text(stringResource(R.string.dns_save), color = OcOrange)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel)) }
        },
    )
}
