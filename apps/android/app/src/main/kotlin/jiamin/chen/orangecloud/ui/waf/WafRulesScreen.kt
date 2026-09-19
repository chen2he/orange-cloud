package jiamin.chen.orangecloud.ui.waf

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
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
import jiamin.chen.orangecloud.data.model.WafRule

/** 自定义规则可创建的动作（skip 需额外参数，暂不提供），对齐 iOS WAFRuleAction。 */
private enum class WafCreateAction(val value: String, val labelRes: Int) {
    BLOCK("block", R.string.waf_action_block),
    MANAGED_CHALLENGE("managed_challenge", R.string.waf_action_managed_challenge),
    JS_CHALLENGE("js_challenge", R.string.waf_action_js_challenge),
    CHALLENGE("challenge", R.string.waf_action_challenge),
    LOG("log", R.string.waf_action_log),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WafRulesScreen(
    onBack: () -> Unit,
    viewModel: WafRulesViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    val snackbarHostState = remember { SnackbarHostState() }
    var showForm by remember { mutableStateOf(false) }
    var editingRule by remember { mutableStateOf<WafRule?>(null) }
    var showUnsupportedEdit by remember { mutableStateOf(false) }
    var ruleToDelete by remember { mutableStateOf<WafRule?>(null) }

    val savedMsg = stringResource(R.string.waf_saved)
    val deletedMsg = stringResource(R.string.waf_deleted)
    val genericErrorMsg = stringResource(R.string.error_generic)

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                WafEvent.Saved -> { showForm = false; editingRule = null; snackbarHostState.showSnackbar(savedMsg) }
                WafEvent.Deleted -> snackbarHostState.showSnackbar(deletedMsg)
                is WafEvent.Error -> snackbarHostState.showSnackbar(event.message?.takeIf { it.isNotBlank() } ?: genericErrorMsg)
            }
        }
    }

    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().systemBarsPadding()) {
                SkyHeader(
                    title = stringResource(R.string.waf_title),
                    onSky = onSky,
                    isLoading = state.isLoading,
                    onRefresh = { viewModel.load() },
                    onBack = onBack,
                    titleSize = 22,
                    backDescription = stringResource(R.string.common_back),
                    refreshDescription = stringResource(R.string.common_refresh),
                )
                if (!state.canWrite && !state.missingScope) {
                    Text(
                        stringResource(R.string.waf_readonly),
                        color = onSky.copy(alpha = 0.7f),
                        fontSize = 13.sp,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 2.dp),
                    )
                }
                when {
                    state.missingScope ->
                        SkyEmptyState(Icons.Outlined.Lock, stringResource(R.string.scope_missing), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }

                    state.rules.isEmpty() && state.isLoading ->
                        Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = onSky) }

                    state.rules.isEmpty() && state.hasError ->
                        SkyEmptyState(Icons.Outlined.Shield, stringResource(R.string.error_generic), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }

                    state.rules.isEmpty() ->
                        SkyEmptyState(Icons.Outlined.Shield, stringResource(R.string.waf_empty), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }

                    else -> LazyColumn(
                        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = if (state.canWrite) 96.dp else 8.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        items(state.rules, key = { it.id }) { rule ->
                            WafRuleRow(
                                rule,
                                canWrite = state.canWrite,
                                isToggling = rule.id in state.togglingIds,
                                onToggle = { viewModel.toggle(rule, it) },
                                onDelete = { ruleToDelete = rule },
                                onClick = {
                                    // skip 等带额外参数的动作不在表单支持范围，整条 PATCH 会丢参数
                                    if (WafCreateAction.entries.any { it.value == rule.action }) {
                                        editingRule = rule
                                    } else {
                                        showUnsupportedEdit = true
                                    }
                                },
                            )
                        }
                    }
                }
            }

            if (state.canWrite && !state.missingScope) {
                FloatingActionButton(
                    onClick = { showForm = true },
                    containerColor = OcOrange,
                    contentColor = Color.White,
                    modifier = Modifier.align(Alignment.BottomEnd).padding(20.dp).systemBarsPadding(),
                ) {
                    Icon(Icons.Outlined.Add, contentDescription = stringResource(R.string.waf_add_title))
                }
            }
            SnackbarHost(snackbarHostState, Modifier.align(Alignment.BottomCenter).systemBarsPadding())
        }
    }

    if (showForm) {
        ModalBottomSheet(
            onDismissRequest = { if (!state.isSaving) showForm = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            WafRuleForm(
                isSaving = state.isSaving,
                onSave = { action, expression, name, enabled -> viewModel.addRule(action, expression, name, enabled) },
            )
        }
    }

    editingRule?.let { rule ->
        ModalBottomSheet(
            onDismissRequest = { if (!state.isSaving) editingRule = null },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            WafRuleForm(
                isSaving = state.isSaving,
                initial = rule,
                onSave = { action, expression, name, enabled ->
                    viewModel.updateRule(rule.id, action, expression, name, enabled)
                },
            )
        }
    }

    if (showUnsupportedEdit) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showUnsupportedEdit = false },
            title = { Text(stringResource(R.string.waf_edit_unsupported_title)) },
            text = { Text(stringResource(R.string.waf_edit_unsupported_msg)) },
            confirmButton = {
                TextButton(onClick = { showUnsupportedEdit = false }) { Text(stringResource(R.string.common_confirm)) }
            },
        )
    }

    ruleToDelete?.let { rule ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { ruleToDelete = null },
            title = { Text(stringResource(R.string.waf_delete_confirm_title)) },
            text = { Text(stringResource(R.string.waf_delete_confirm_msg)) },
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

@Composable
private fun WafRuleRow(
    rule: WafRule,
    canWrite: Boolean,
    isToggling: Boolean,
    onToggle: (Boolean) -> Unit,
    onDelete: () -> Unit,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        enabled = canWrite,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(Modifier.padding(start = 14.dp, top = 14.dp, bottom = 14.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier
                            .background(OcOrange.copy(alpha = 0.16f), RoundedCornerShape(6.dp))
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                    ) {
                        Text(stringResource(actionLabel(rule.action)), color = OcOrange, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    }
                    rule.description?.takeIf { it.isNotBlank() }?.let {
                        Spacer(Modifier.width(8.dp))
                        Text(it, fontSize = 14.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onSurface)
                    }
                }
                rule.expression?.let {
                    Spacer(Modifier.width(4.dp))
                    Text(
                        it,
                        fontSize = 12.sp,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            Switch(checked = rule.enabled ?: false, onCheckedChange = onToggle, enabled = canWrite && !isToggling)
            if (canWrite) {
                IconButton(onClick = onDelete) {
                    Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.dns_delete), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WafRuleForm(
    isSaving: Boolean,
    initial: WafRule? = null,
    onSave: (action: String, expression: String, name: String, enabled: Boolean) -> Unit,
) {
    var name by rememberSaveable { mutableStateOf(initial?.description.orEmpty()) }
    var expression by rememberSaveable { mutableStateOf(initial?.expression.orEmpty()) }
    var enabled by rememberSaveable { mutableStateOf(initial?.enabled ?: true) }
    var action by rememberSaveable {
        mutableStateOf(WafCreateAction.entries.firstOrNull { it.value == initial?.action } ?: WafCreateAction.BLOCK)
    }
    var expanded by remember { mutableStateOf(false) }
    var showBuilder by remember { mutableStateOf(false) }

    val canSave = name.isNotBlank() && expression.isNotBlank() && !isSaving

    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .padding(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            stringResource(if (initial == null) R.string.waf_add_title else R.string.waf_edit_title),
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface,
        )

        OutlinedTextField(
            value = name,
            onValueChange = { name = it },
            label = { Text(stringResource(R.string.waf_field_name)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )

        ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
            OutlinedTextField(
                value = stringResource(action.labelRes),
                onValueChange = {},
                readOnly = true,
                label = { Text(stringResource(R.string.waf_field_action)) },
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                modifier = Modifier.menuAnchor(MenuAnchorType.PrimaryNotEditable).fillMaxWidth(),
            )
            ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                WafCreateAction.entries.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(stringResource(option.labelRes)) },
                        onClick = { action = option; expanded = false },
                    )
                }
            }
        }

        OutlinedTextField(
            value = expression,
            onValueChange = { expression = it },
            label = { Text(stringResource(R.string.waf_field_expression)) },
            textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
            minLines = 3,
            modifier = Modifier.fillMaxWidth(),
        )
        Text(
            stringResource(R.string.waf_expression_hint),
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        TextButton(onClick = { showBuilder = true }) {
            Icon(Icons.Outlined.Tune, contentDescription = null, tint = OcOrange)
            Spacer(Modifier.width(6.dp))
            Text(stringResource(R.string.wafb_open), color = OcOrange)
        }

        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.waf_field_enabled), fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurface)
            Spacer(Modifier.weight(1f))
            Switch(checked = enabled, onCheckedChange = { enabled = it })
        }

        Button(
            onClick = { onSave(action.value, expression, name, enabled) },
            enabled = canSave,
            colors = ButtonDefaults.buttonColors(containerColor = OcOrange, contentColor = Color.White),
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (isSaving) {
                CircularProgressIndicator(Modifier.height(18.dp).width(18.dp), strokeWidth = 2.dp, color = Color.White)
                Spacer(Modifier.width(8.dp))
            }
            Text(stringResource(R.string.dns_save))
        }

        if (showBuilder) {
            ModalBottomSheet(
                onDismissRequest = { showBuilder = false },
                sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            ) {
                WafExpressionBuilder(onApply = { expr -> expression = expr; showBuilder = false })
            }
        }
    }
}

private fun actionLabel(action: String?): Int = when (action) {
    "block" -> R.string.waf_action_block
    "challenge" -> R.string.waf_action_challenge
    "managed_challenge" -> R.string.waf_action_managed_challenge
    "js_challenge" -> R.string.waf_action_js_challenge
    "log" -> R.string.waf_action_log
    "skip", "allow" -> R.string.waf_action_allow
    else -> R.string.waf_action_other
}
