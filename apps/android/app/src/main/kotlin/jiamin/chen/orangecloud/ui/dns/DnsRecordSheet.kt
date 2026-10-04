package jiamin.chen.orangecloud.ui.dns

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SheetState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import jiamin.chen.orangecloud.R
import jiamin.chen.orangecloud.data.model.CreateDnsRecord
import jiamin.chen.orangecloud.data.model.DnsRecord

/**
 * DNS 记录新建 / 编辑底部表单。record == null 表示新建。
 * 规则与 iOS DNSRecordFormView 一致：仅 A/AAAA/CNAME 可代理；仅 MX 有优先级；代理开启时 TTL 锁自动。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DnsRecordSheet(
    record: DnsRecord?,
    isSaving: Boolean,
    /** 该记录被 NS 委派遮蔽（include_shadow_metadata），表单顶部给出提示。 */
    shadowed: Boolean = false,
    sheetState: SheetState,
    onSave: (CreateDnsRecord) -> Unit,
    onDelete: () -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        DnsRecordForm(record, shadowed, isSaving, onSave, onDelete)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DnsRecordForm(
    record: DnsRecord?,
    shadowed: Boolean,
    isSaving: Boolean,
    onSave: (CreateDnsRecord) -> Unit,
    onDelete: () -> Unit,
) {
    val key = record?.id
    var type by rememberSaveable(key) { mutableStateOf(record?.type ?: "A") }
    var name by rememberSaveable(key) { mutableStateOf(record?.name ?: "") }
    var content by rememberSaveable(key) { mutableStateOf(record?.content ?: "") }
    var proxied by rememberSaveable(key) { mutableStateOf(record?.isProxied ?: false) }
    var ttl by rememberSaveable(key) { mutableStateOf(record?.ttl ?: 1) }
    var priority by rememberSaveable(key) { mutableStateOf((record?.priority ?: 10).toString()) }
    var comment by rememberSaveable(key) { mutableStateOf(record?.comment ?: "") }

    val supportsProxy = DnsForm.supportsProxy(type)
    val needsPriority = DnsForm.needsPriority(type)
    val effectiveProxied = supportsProxy && proxied
    val canSave = name.isNotBlank() && content.isNotBlank() && !isSaving

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding()
            .imePadding()
            .padding(horizontal = 24.dp)
            .padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(
            text = stringResource(if (record == null) R.string.dns_new_title else R.string.dns_edit_title),
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
        )

        // 被 NS 委派遮蔽的记录：改了也不会生效，先说清楚
        if (shadowed) {
            Text(
                stringResource(R.string.dns_shadowed) + " · " + stringResource(R.string.dns_shadowed_detail),
                fontSize = 13.sp,
                color = androidx.compose.ui.graphics.Color(0xFFE08600),
            )
        }

        // 2026-06-30 起 CF API 不再允许修改已有记录的类型：编辑时锁定，仅新建可选（对齐 iOS .disabled(isEditing)）
        FieldDropdown(
            label = stringResource(R.string.dns_field_type),
            options = DnsForm.recordTypes,
            selected = type,
            optionLabel = { it },
            onSelect = { type = it },
            enabled = record == null,
        )

        OutlinedTextField(
            value = name,
            onValueChange = { name = it },
            label = { Text(stringResource(R.string.dns_field_name)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )

        OutlinedTextField(
            value = content,
            onValueChange = { content = it },
            label = { Text(stringResource(R.string.dns_field_content)) },
            placeholder = { Text(contentHint(type)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )

        if (supportsProxy) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.dns_field_proxy), modifier = Modifier.weight(1f))
                Switch(checked = proxied, onCheckedChange = { proxied = it })
            }
        }

        FieldDropdown(
            label = stringResource(R.string.dns_field_ttl),
            options = DnsForm.ttlValues,
            selected = if (effectiveProxied) 1 else ttl,
            enabled = !effectiveProxied,
            optionLabel = { ttlLabel(it) },
            onSelect = { ttl = it },
        )

        if (needsPriority) {
            OutlinedTextField(
                value = priority,
                onValueChange = { new -> priority = new.filter { it.isDigit() }.take(5) },
                label = { Text(stringResource(R.string.dns_field_priority)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        OutlinedTextField(
            value = comment,
            onValueChange = { comment = it },
            label = { Text(stringResource(R.string.dns_field_comment)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )

        Spacer(Modifier.size(4.dp))

        Button(
            onClick = {
                onSave(
                    CreateDnsRecord(
                        type = type,
                        name = name.trim(),
                        content = content.trim(),
                        proxied = effectiveProxied,
                        ttl = if (effectiveProxied) 1 else ttl,
                        priority = if (needsPriority) priority.toIntOrNull() ?: 10 else null,
                        comment = comment.trim().ifBlank { null },
                    ),
                )
            },
            enabled = canSave,
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (isSaving) {
                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(8.dp))
            }
            Text(stringResource(R.string.dns_save))
        }

        if (record != null) {
            OutlinedButton(
                onClick = onDelete,
                enabled = !isSaving,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.dns_delete))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun <T> FieldDropdown(
    label: String,
    options: List<T>,
    selected: T,
    onSelect: (T) -> Unit,
    optionLabel: @Composable (T) -> String,
    enabled: Boolean = true,
) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded && enabled,
        onExpandedChange = { if (enabled) expanded = !expanded },
    ) {
        OutlinedTextField(
            value = optionLabel(selected),
            onValueChange = {},
            readOnly = true,
            enabled = enabled,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded && enabled) },
            modifier = Modifier
                .menuAnchor(MenuAnchorType.PrimaryNotEditable, enabled)
                .fillMaxWidth(),
        )
        ExposedDropdownMenu(expanded = expanded && enabled, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(optionLabel(option)) },
                    onClick = {
                        onSelect(option)
                        expanded = false
                    },
                )
            }
        }
    }
}

@Composable
private fun contentHint(type: String): String = stringResource(
    when (type) {
        "A" -> R.string.dns_hint_a
        "AAAA" -> R.string.dns_hint_aaaa
        "CNAME" -> R.string.dns_hint_cname
        "TXT" -> R.string.dns_hint_txt
        "MX" -> R.string.dns_hint_mx
        "NS" -> R.string.dns_hint_ns
        else -> R.string.dns_field_content
    },
)

@Composable
private fun ttlLabel(value: Int): String = stringResource(
    when (value) {
        60 -> R.string.ttl_1m
        300 -> R.string.ttl_5m
        1800 -> R.string.ttl_30m
        3600 -> R.string.ttl_1h
        86400 -> R.string.ttl_1d
        else -> R.string.ttl_auto
    },
)
