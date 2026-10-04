package jiamin.chen.orangecloud.ui.cache

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.AlertDialog
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
import androidx.compose.foundation.horizontalScroll
import androidx.compose.material3.AssistChip
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
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
import jiamin.chen.orangecloud.core.design.RuleValidation
import jiamin.chen.orangecloud.core.design.RuleValidationResult
import jiamin.chen.orangecloud.core.design.showApiError
import jiamin.chen.orangecloud.core.design.onSky
import jiamin.chen.orangecloud.core.design.rememberSkyPhase
import jiamin.chen.orangecloud.core.design.theme.OcOrange
import jiamin.chen.orangecloud.data.model.CacheActionParameters
import jiamin.chen.orangecloud.data.model.CacheBrowserTTL
import jiamin.chen.orangecloud.data.model.CacheEdgeTTL
import jiamin.chen.orangecloud.data.model.CacheRule
import jiamin.chen.orangecloud.data.model.CacheResponseRule
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** TTL 模式（对齐 iOS CacheTTLMode）。 */
private enum class TtlMode(val raw: String, val labelRes: Int) {
    RESPECT_ORIGIN("respect_origin", R.string.cache_ttl_respect),
    OVERRIDE_ORIGIN("override_origin", R.string.cache_ttl_override),
    BYPASS_BY_DEFAULT("bypass_by_default", R.string.cache_ttl_bypass);

    companion object {
        fun fromRaw(raw: String?): TtlMode = entries.firstOrNull { it.raw == raw } ?: RESPECT_ORIGIN
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ZoneCacheRulesScreen(
    onBack: () -> Unit,
    viewModel: ZoneCacheRulesViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    val snackbarHostState = remember { SnackbarHostState() }
    var editing by remember { mutableStateOf<CacheEditTarget?>(null) }
    var ruleToDelete by remember { mutableStateOf<CacheRule?>(null) }
    var responseRuleToDelete by remember { mutableStateOf<CacheResponseRule?>(null) }

    val savedMsg = stringResource(R.string.cache_saved)
    val deletedMsg = stringResource(R.string.cache_deleted)
    val genericErr = stringResource(R.string.error_generic)
    val context = LocalContext.current

    // 打开 / 关闭编辑器都清掉上一次的校验结果，避免把旧结论套到新规则上
    LaunchedEffect(editing) { viewModel.clearValidation() }

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                CacheEvent.Saved -> { editing = null; snackbarHostState.showSnackbar(savedMsg) }
                CacheEvent.Deleted -> snackbarHostState.showSnackbar(deletedMsg)
                is CacheEvent.Error ->
                    snackbarHostState.showApiError(context, event.message ?: genericErr, event.documentationUrl)
            }
        }
    }

    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().systemBarsPadding()) {
                SkyHeader(
                    title = stringResource(R.string.cache_title),
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
                        stringResource(R.string.cache_readonly),
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

                    state.rules.isEmpty() && state.responseRules.isEmpty() ->
                        SkyEmptyState(Icons.Outlined.Bolt, stringResource(R.string.cache_empty), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }

                    else -> LazyColumn(
                        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = if (state.canWrite) 96.dp else 8.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        if (state.rules.isEmpty()) {
                            item(key = "req-empty") {
                                Text(
                                    stringResource(R.string.cache_empty),
                                    fontSize = 13.sp,
                                    color = onSky.copy(alpha = 0.7f),
                                    modifier = Modifier.padding(horizontal = 4.dp),
                                )
                            }
                        }
                        items(state.rules, key = { it.id }) { rule ->
                            CacheRuleRow(
                                rule = rule,
                                canWrite = state.canWrite,
                                onToggle = { viewModel.toggle(rule, it) },
                                onEdit = if (state.canWrite && rule.actionParameters?.hasAdvancedSettings != true) {
                                    { editing = CacheEditTarget(rule) }
                                } else null,
                                onDelete = { ruleToDelete = rule },
                            )
                        }
                        // 缓存响应规则（响应阶段）：只做查看 / 启停 / 删除，编辑请到控制台
                        if (state.responseAvailable) {
                            item(key = "resp-header") {
                                Text(
                                    stringResource(R.string.cache_response_title),
                                    color = onSky,
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 13.sp,
                                    modifier = Modifier.padding(start = 4.dp, top = 10.dp),
                                )
                            }
                            if (state.responseRules.isEmpty()) {
                                item(key = "resp-empty") {
                                    Text(
                                        stringResource(R.string.cache_response_empty),
                                        fontSize = 13.sp,
                                        color = onSky.copy(alpha = 0.7f),
                                        modifier = Modifier.padding(horizontal = 4.dp),
                                    )
                                }
                            }
                            items(state.responseRules, key = { "resp:" + it.id }) { rule ->
                                CacheResponseRuleRow(
                                    rule = rule,
                                    canWrite = state.canWrite,
                                    toggling = state.togglingResponseRuleId == rule.id,
                                    onToggle = { viewModel.toggleResponse(rule, it) },
                                    onDelete = { responseRuleToDelete = rule },
                                )
                            }
                        }
                    }
                }
            }

            if (state.canWrite && !state.missingScope) {
                FloatingActionButton(
                    onClick = { editing = CacheEditTarget(null) },
                    containerColor = OcOrange,
                    contentColor = Color.White,
                    modifier = Modifier.align(Alignment.BottomEnd).padding(20.dp).systemBarsPadding(),
                ) {
                    Icon(Icons.Outlined.Add, contentDescription = stringResource(R.string.cache_add_title))
                }
            }
            SnackbarHost(snackbarHostState, Modifier.align(Alignment.BottomCenter).systemBarsPadding())
        }
    }

    editing?.let { target ->
        ModalBottomSheet(
            onDismissRequest = { if (!state.isSaving) editing = null },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            CacheRuleForm(
                target = target,
                isSaving = state.isSaving,
                validation = state.validation,
                onSave = { expr, desc, enabled, params -> viewModel.save(target.rule?.id, expr, desc, enabled, params) },
                onValidate = { expr, desc, enabled, params -> viewModel.validate(target.rule?.id, expr, desc, enabled, params) },
            )
        }
    }

    responseRuleToDelete?.let { rule ->
        AlertDialog(
            onDismissRequest = { responseRuleToDelete = null },
            title = { Text(stringResource(R.string.cache_delete_confirm_title)) },
            text = { Text(stringResource(R.string.cache_delete_confirm_msg)) },
            confirmButton = {
                TextButton(onClick = { viewModel.deleteResponse(rule); responseRuleToDelete = null }) {
                    Text(stringResource(R.string.dns_delete), color = Color(0xFFE5484D))
                }
            },
            dismissButton = {
                TextButton(onClick = { responseRuleToDelete = null }) { Text(stringResource(R.string.common_cancel)) }
            },
        )
    }

    ruleToDelete?.let { rule ->
        AlertDialog(
            onDismissRequest = { ruleToDelete = null },
            title = { Text(stringResource(R.string.cache_delete_confirm_title)) },
            text = { Text(stringResource(R.string.cache_delete_confirm_msg)) },
            confirmButton = {
                TextButton(onClick = { viewModel.delete(rule); ruleToDelete = null }) {
                    Text(stringResource(R.string.dns_delete), color = Color(0xFFE5484D))
                }
            },
            dismissButton = {
                TextButton(onClick = { ruleToDelete = null }) { Text(stringResource(R.string.common_cancel)) }
            },
        )
    }
}

/** 编辑目标：rule == null 表示新建。 */
private data class CacheEditTarget(val rule: CacheRule?)

@Composable
private fun CacheRuleRow(
    rule: CacheRule,
    canWrite: Boolean,
    onToggle: (Boolean) -> Unit,
    onEdit: (() -> Unit)?,
    onDelete: () -> Unit,
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth().let { if (onEdit != null) it.clickable(onClick = onEdit) else it },
    ) {
        Row(Modifier.padding(start = 14.dp, top = 14.dp, bottom = 14.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier
                            .background(OcOrange.copy(alpha = 0.16f), RoundedCornerShape(6.dp))
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                    ) {
                        Text(cacheSummary(rule), color = OcOrange, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    }
                    rule.description?.takeIf { it.isNotBlank() }?.let {
                        Spacer(Modifier.width(8.dp))
                        Text(it, fontSize = 14.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onSurface)
                    }
                }
                rule.expression?.let {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        it,
                        fontSize = 12.sp,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                if (rule.actionParameters?.hasAdvancedSettings == true) {
                    Text(
                        stringResource(R.string.cache_advanced_readonly),
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Switch(checked = rule.enabled ?: false, onCheckedChange = onToggle, enabled = canWrite)
            if (canWrite) {
                IconButton(onClick = onDelete) {
                    Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.dns_delete), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/** 缓存响应规则行：动作参数尽力摘要（认不出的只显示表达式）+ 启停 + 删除。 */
@Composable
private fun CacheResponseRuleRow(
    rule: CacheResponseRule,
    canWrite: Boolean,
    toggling: Boolean,
    onToggle: (Boolean) -> Unit,
    onDelete: () -> Unit,
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(Modifier.padding(start = 14.dp, top = 14.dp, bottom = 14.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                val summary = responseRuleSummary(rule)
                if (summary != null || !rule.description.isNullOrBlank()) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        summary?.let {
                            Box(
                                Modifier
                                    .background(OcOrange.copy(alpha = 0.16f), RoundedCornerShape(6.dp))
                                    .padding(horizontal = 8.dp, vertical = 3.dp),
                            ) {
                                Text(it, color = OcOrange, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            Spacer(Modifier.width(8.dp))
                        }
                        rule.description?.takeIf { it.isNotBlank() }?.let {
                            Text(it, fontSize = 14.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onSurface)
                        }
                    }
                }
                rule.expression?.let {
                    Spacer(Modifier.height(4.dp))
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
            Switch(checked = rule.enabled ?: false, onCheckedChange = onToggle, enabled = canWrite && !toggling)
            if (canWrite) {
                IconButton(onClick = onDelete) {
                    Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.dns_delete), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/**
 * action_parameters 尽力摘要：顶层键里取前 3 个，简单值写成 key=value、嵌套对象只写 key。
 * 形态认不出（非对象 / 空）返回 null，行里只显示表达式。
 */
private fun responseRuleSummary(rule: CacheResponseRule): String? {
    val params = rule.actionParameters as? JsonObject ?: return null
    if (params.isEmpty()) return null
    return params.entries.take(3).joinToString(" · ") { (key, value) ->
        val prim = value as? JsonPrimitive
        if (prim != null && prim !is JsonNull) "$key=${prim.content}" else key
    }
}

@Composable
private fun cacheSummary(rule: CacheRule): String {
    val p = rule.actionParameters ?: return stringResource(R.string.cache_summary_default)
    if (p.cache == false) return stringResource(R.string.cache_summary_bypass)
    return stringResource(R.string.cache_summary_eligible)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CacheRuleForm(
    target: CacheEditTarget,
    isSaving: Boolean,
    validation: RuleValidation?,
    onSave: (expression: String, description: String, enabled: Boolean, params: CacheActionParameters) -> Unit,
    onValidate: (expression: String, description: String, enabled: Boolean, params: CacheActionParameters) -> Unit,
) {
    val rule = target.rule
    var description by rememberSaveable { mutableStateOf(rule?.description.orEmpty()) }
    var expression by rememberSaveable { mutableStateOf(rule?.expression.orEmpty()) }
    var enabled by rememberSaveable { mutableStateOf(rule?.enabled ?: true) }
    var eligible by rememberSaveable { mutableStateOf(rule?.actionParameters?.cache != false) }
    var edgeMode by rememberSaveable { mutableStateOf(TtlMode.fromRaw(rule?.actionParameters?.edgeTtl?.mode)) }
    var edgeTtl by rememberSaveable { mutableStateOf(rule?.actionParameters?.edgeTtl?.defaultTtl?.toString().orEmpty()) }
    var browserMode by rememberSaveable { mutableStateOf(TtlMode.fromRaw(rule?.actionParameters?.browserTtl?.mode)) }
    var browserTtl by rememberSaveable { mutableStateOf(rule?.actionParameters?.browserTtl?.defaultTtl?.toString().orEmpty()) }

    val canSave = expression.isNotBlank() && !isSaving

    Column(
        Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            stringResource(if (rule == null) R.string.cache_add_title else R.string.cache_edit_title),
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface,
        )

        OutlinedTextField(
            value = description,
            onValueChange = { description = it },
            label = { Text(stringResource(R.string.cache_field_description)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )

        OutlinedTextField(
            value = expression,
            onValueChange = { expression = it },
            label = { Text(stringResource(R.string.cache_field_expression)) },
            textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
            minLines = 2,
            modifier = Modifier.fillMaxWidth(),
        )

        // 常用字段速插。cf.bot_management.* 与 ip.src.asnum 是 2026-07-16 才对缓存规则开放的。
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            CACHE_FIELD_CHIPS.forEach { (labelRes, token) ->
                AssistChip(
                    onClick = {
                        expression = if (expression.isBlank()) token else "$expression $token"
                    },
                    label = { Text(stringResource(labelRes), fontSize = 12.sp) },
                )
            }
        }

        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.cache_field_eligible), fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurface)
            Spacer(Modifier.weight(1f))
            Switch(checked = eligible, onCheckedChange = { eligible = it })
        }

        if (eligible) {
            TtlModeField(stringResource(R.string.cache_field_edge_ttl), edgeMode) { edgeMode = it }
            if (edgeMode == TtlMode.OVERRIDE_ORIGIN) {
                OutlinedTextField(
                    value = edgeTtl,
                    onValueChange = { v -> edgeTtl = v.filter { it.isDigit() } },
                    label = { Text(stringResource(R.string.cache_field_edge_ttl_seconds)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            TtlModeField(stringResource(R.string.cache_field_browser_ttl), browserMode) { browserMode = it }
            if (browserMode == TtlMode.OVERRIDE_ORIGIN) {
                OutlinedTextField(
                    value = browserTtl,
                    onValueChange = { v -> browserTtl = v.filter { it.isDigit() } },
                    label = { Text(stringResource(R.string.cache_field_browser_ttl_seconds)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }

        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.cache_field_enabled), fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurface)
            Spacer(Modifier.weight(1f))
            Switch(checked = enabled, onCheckedChange = { enabled = it })
        }

        // 保存与校验发送完全相同的规则体
        fun buildParams(): CacheActionParameters = if (!eligible) {
            CacheActionParameters(cache = false)
        } else {
            CacheActionParameters(
                cache = true,
                edgeTtl = CacheEdgeTTL(
                    mode = edgeMode.raw,
                    defaultTtl = edgeTtl.toIntOrNull().takeIf { edgeMode == TtlMode.OVERRIDE_ORIGIN },
                ),
                browserTtl = CacheBrowserTTL(
                    mode = browserMode.raw,
                    defaultTtl = browserTtl.toIntOrNull().takeIf { browserMode == TtlMode.OVERRIDE_ORIGIN },
                ),
            )
        }

        RuleValidationResult(validation)
        OutlinedButton(
            onClick = { onValidate(expression, description, enabled, buildParams()) },
            enabled = expression.isNotBlank() && !isSaving && validation != RuleValidation.Running,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(stringResource(R.string.rule_validate))
        }

        Button(
            onClick = { onSave(expression, description, enabled, buildParams()) },
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
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TtlModeField(label: String, mode: TtlMode, onSelect: (TtlMode) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = stringResource(mode.labelRes),
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier.menuAnchor(MenuAnchorType.PrimaryNotEditable).fillMaxWidth(),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            TtlMode.entries.forEach { option ->
                DropdownMenuItem(
                    text = { Text(stringResource(option.labelRes)) },
                    onClick = { onSelect(option); expanded = false },
                )
            }
        }
    }
}

/** 表达式常用字段：显示名 → Wireshark 语法 token。 */
private val CACHE_FIELD_CHIPS: List<Pair<Int, String>> = listOf(
    R.string.cache_chip_path to "http.request.uri.path",
    R.string.cache_chip_host to "http.host",
    R.string.cache_chip_query to "http.request.uri.query",
    R.string.cache_chip_method to "http.request.method",
    R.string.cache_chip_cookie to "http.cookie",
    R.string.cache_chip_country to "ip.src.country",
    R.string.cache_chip_bot_score to "cf.bot_management.score",
    R.string.cache_chip_verified_bot to "cf.bot_management.verified_bot",
    R.string.cache_chip_ja3 to "cf.bot_management.ja3_hash",
    R.string.cache_chip_ja4 to "cf.bot_management.ja4",
    R.string.cache_chip_asn to "ip.src.asnum",
)
