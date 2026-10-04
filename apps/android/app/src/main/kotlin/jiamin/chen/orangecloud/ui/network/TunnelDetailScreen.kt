package jiamin.chen.orangecloud.ui.network

import android.text.format.DateUtils
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Hub
import androidx.compose.material.icons.outlined.SettingsEthernet
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
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
import jiamin.chen.orangecloud.core.util.copyToClipboard
import jiamin.chen.orangecloud.data.model.IngressRule
import jiamin.chen.orangecloud.data.model.IngressServiceKind
import jiamin.chen.orangecloud.data.model.TunnelConnection
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** 隧道详情：信息 + 连接令牌 + 公共主机名管理 + 活跃连接 + 危险操作（对齐 iOS TunnelDetailView）。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TunnelDetailScreen(
    onBack: () -> Unit,
    viewModel: TunnelDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    val snackbarHostState = remember { SnackbarHostState() }
    val errMsg = stringResource(R.string.error_generic)

    var hostnameEdit by remember { mutableStateOf<HostnameEdit?>(null) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var showCleanupConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(state.canWrite) { if (state.canWrite) viewModel.loadToken() }
    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                TunnelDetailEvent.Deleted -> onBack()
                is TunnelDetailEvent.Notice -> snackbarHostState.showSnackbar(event.message)
                is TunnelDetailEvent.Error -> snackbarHostState.showSnackbar(event.message ?: errMsg)
            }
        }
    }

    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize().systemBarsPadding()) {
            Column(Modifier.fillMaxSize()) {
                SkyHeader(
                    title = state.tunnel?.name?.ifBlank { viewModel.tunnelName } ?: viewModel.tunnelName.ifBlank { stringResource(R.string.tunnel_title) },
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
                        SkyEmptyState(Icons.Outlined.Hub, stringResource(R.string.scope_missing), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }

                    state.tunnel == null && state.isLoading ->
                        Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = onSky) }

                    state.tunnel == null ->
                        SkyEmptyState(Icons.Outlined.Hub, stringResource(R.string.error_generic), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }

                    else -> {
                        val tunnel = state.tunnel!!
                        // config_src 优先，缺失才回退 remote_config（已弃用）
                        val isRemote = tunnel.isRemotelyManaged == true
                        Column(
                            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                                .padding(horizontal = 16.dp).padding(bottom = 24.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            SectionCard(stringResource(R.string.tunnel_section_info)) {
                                StatusRow(tunnel.status)
                                tunnel.tunType?.let { InfoRow(stringResource(R.string.tunnel_field_type), it) }
                                tunnel.isRemotelyManaged?.let {
                                    InfoRow(
                                        stringResource(R.string.tunnel_field_config),
                                        stringResource(if (it) R.string.tunnel_config_remote else R.string.tunnel_config_local),
                                    )
                                }
                                formatDate(tunnel.createdAt)?.let { InfoRow(stringResource(R.string.tunnel_field_created), it) }
                                InfoRow(stringResource(R.string.tunnel_field_id), tunnel.id, mono = true)
                            }

                            if (state.canWrite) ConnectCard(state)

                            if (isRemote) {
                                PublicHostnamesCard(
                                    state = state,
                                    onAdd = { hostnameEdit = HostnameEdit.New },
                                    onEdit = { index, rule -> hostnameEdit = HostnameEdit.Edit(index, rule) },
                                    onDelete = { viewModel.deleteHostname(it) },
                                )
                            } else {
                                SectionCard(stringResource(R.string.tunnel_hostnames_section)) {
                                    Text(stringResource(R.string.tunnel_local_note), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }

                            SectionCard(stringResource(R.string.tunnel_section_connections)) {
                                val connections = state.connections
                                if (connections.isEmpty()) {
                                    Text(stringResource(R.string.tunnel_no_connections), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                } else {
                                    connections.forEachIndexed { index, conn ->
                                        ConnectionRow(conn)
                                        if (index < connections.lastIndex) Spacer(Modifier.size(10.dp))
                                    }
                                }
                            }

                            if (state.canWrite) {
                                SectionCard(stringResource(R.string.tunnel_danger_section)) {
                                    DangerButton(stringResource(R.string.tunnel_cleanup)) { showCleanupConfirm = true }
                                    DangerButton(stringResource(R.string.tunnel_delete)) { showDeleteConfirm = true }
                                }
                            }
                        }
                    }
                }
            }
            SnackbarHost(snackbarHostState, modifier = Modifier.align(Alignment.BottomCenter))
        }
    }

    hostnameEdit?.let { edit ->
        val initial = (edit as? HostnameEdit.Edit)?.rule
        val index = (edit as? HostnameEdit.Edit)?.index
        HostnameFormSheet(
            initial = initial,
            isSaving = state.isSaving,
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            onSubmit = { rule -> viewModel.saveHostname(rule, index); hostnameEdit = null },
            onDismiss = { hostnameEdit = null },
        )
    }

    if (showCleanupConfirm) {
        ConfirmDialog(
            title = stringResource(R.string.tunnel_cleanup_confirm_title),
            message = stringResource(R.string.tunnel_cleanup_confirm_msg),
            confirmLabel = stringResource(R.string.tunnel_cleanup),
            onConfirm = { showCleanupConfirm = false; viewModel.cleanupConnections() },
            onDismiss = { showCleanupConfirm = false },
        )
    }
    if (showDeleteConfirm) {
        ConfirmDialog(
            title = stringResource(R.string.tunnel_delete_confirm_title),
            message = stringResource(R.string.tunnel_delete_confirm_msg),
            confirmLabel = stringResource(R.string.tunnel_delete),
            onConfirm = { showDeleteConfirm = false; viewModel.deleteTunnel() },
            onDismiss = { showDeleteConfirm = false },
        )
    }
}

private sealed interface HostnameEdit {
    data object New : HostnameEdit
    data class Edit(val index: Int, val rule: IngressRule) : HostnameEdit
}

// MARK: - 连接令牌

@Composable
private fun ConnectCard(state: TunnelDetailUiState) {
    val context = LocalContext.current
    var revealed by remember { mutableStateOf(false) }
    var copied by remember { mutableStateOf(false) }
    val token = state.token
    val command = "cloudflared service install ${token ?: ""}"

    SectionCard(stringResource(R.string.tunnel_connect_section)) {
        Text(stringResource(R.string.tunnel_connect_intro), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        when {
            token != null -> {
                Text(
                    if (revealed) command else "cloudflared service install ${token.take(8)}…••••",
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { revealed = !revealed }, modifier = Modifier.weight(1f)) {
                        Text(stringResource(if (revealed) R.string.tunnel_connect_hide else R.string.tunnel_connect_reveal))
                    }
                    Button(
                        onClick = { copyToClipboard(context, command); copied = true },
                        colors = ButtonDefaults.buttonColors(containerColor = OcOrange, contentColor = Color.White),
                        modifier = Modifier.weight(1f),
                    ) {
                        Text(stringResource(if (copied) R.string.tunnel_connect_copied else R.string.tunnel_connect_copy))
                    }
                }
                Text(stringResource(R.string.tunnel_connect_token_warn), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            state.isLoadingToken -> Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = OcOrange)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.tunnel_connect_loading), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            else -> Text(stringResource(R.string.tunnel_connect_failed), fontSize = 13.sp, color = Color(0xFFE5484D))
        }
    }
}

// MARK: - 公共主机名

@Composable
private fun PublicHostnamesCard(
    state: TunnelDetailUiState,
    onAdd: () -> Unit,
    onEdit: (Int, IngressRule) -> Unit,
    onDelete: (Int) -> Unit,
) {
    SectionCard(stringResource(R.string.tunnel_hostnames_section)) {
        when {
            state.isLoadingConfig && !state.configLoaded -> Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = OcOrange)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.tunnel_hostnames_loading), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            state.publicHostnames.isEmpty() -> Text(
                stringResource(if (state.canWrite) R.string.tunnel_hostnames_empty else R.string.tunnel_hostnames_empty_ro),
                fontSize = 14.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            else -> state.publicHostnames.forEachIndexed { index, rule ->
                Row(
                    modifier = Modifier.fillMaxWidth().let { if (state.canWrite) it.clickable { onEdit(index, rule) } else it },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(rule.hostname ?: "—", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface)
                        Text("→ ${rule.service}", fontSize = 12.sp, fontFamily = FontFamily.Monospace, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                        rule.path?.takeIf { it.isNotEmpty() }?.let {
                            Text(it, fontSize = 11.sp, fontFamily = FontFamily.Monospace, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    if (state.canWrite) {
                        IconButton(onClick = { onDelete(index) }) {
                            Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.dns_delete), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
        if (state.canWrite) {
            Row(
                modifier = Modifier.fillMaxWidth().clickable(onClick = onAdd).padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Outlined.Add, contentDescription = null, tint = OcOrange, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.tunnel_hostnames_add), color = OcOrange, fontSize = 14.sp, fontWeight = FontWeight.Medium)
            }
            Text(stringResource(R.string.tunnel_hostnames_footer), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HostnameFormSheet(
    initial: IngressRule?,
    isSaving: Boolean,
    sheetState: androidx.compose.material3.SheetState,
    onSubmit: (IngressRule) -> Unit,
    onDismiss: () -> Unit,
) {
    var hostname by remember { mutableStateOf(initial?.hostname ?: "") }
    var kind by remember { mutableStateOf(initial?.serviceKind ?: IngressServiceKind.HTTP) }
    var target by remember { mutableStateOf(if (initial?.serviceKind == IngressServiceKind.OTHER) "" else initial?.serviceTarget ?: "localhost:8000") }
    var rawService by remember { mutableStateOf(if (initial?.serviceKind == IngressServiceKind.OTHER) initial.service else "") }
    var path by remember { mutableStateOf(initial?.path ?: "") }
    var protoExpanded by remember { mutableStateOf(false) }

    val isOther = kind == IngressServiceKind.OTHER
    val canSave = hostname.trim().isNotEmpty() &&
        (if (isOther) rawService.trim().isNotEmpty() else target.trim().isNotEmpty()) && !isSaving

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier.fillMaxWidth().navigationBarsPadding().imePadding().padding(horizontal = 24.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                stringResource(if (initial == null) R.string.tunnel_host_form_add else R.string.tunnel_host_form_edit),
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
            )
            OutlinedTextField(
                value = hostname,
                onValueChange = { hostname = it },
                label = { Text(stringResource(R.string.tunnel_host_hostname)) },
                placeholder = { Text("app.example.com") },
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth(),
            )
            ExposedDropdownMenuBox(expanded = protoExpanded, onExpandedChange = { protoExpanded = !protoExpanded }) {
                OutlinedTextField(
                    value = protoLabel(kind),
                    onValueChange = {},
                    readOnly = true,
                    label = { Text(stringResource(R.string.tunnel_host_protocol)) },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = protoExpanded) },
                    modifier = Modifier.menuAnchor(MenuAnchorType.PrimaryNotEditable).fillMaxWidth(),
                )
                ExposedDropdownMenu(expanded = protoExpanded, onDismissRequest = { protoExpanded = false }) {
                    IngressServiceKind.entries.forEach { option ->
                        DropdownMenuItem(text = { Text(protoLabel(option)) }, onClick = { kind = option; protoExpanded = false })
                    }
                }
            }
            if (isOther) {
                OutlinedTextField(
                    value = rawService,
                    onValueChange = { rawService = it },
                    label = { Text(stringResource(R.string.tunnel_host_service)) },
                    placeholder = { Text(stringResource(R.string.tunnel_host_service_other)) },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier.fillMaxWidth(),
                )
            } else {
                OutlinedTextField(
                    value = target,
                    onValueChange = { target = it },
                    label = { Text(stringResource(R.string.tunnel_host_service)) },
                    placeholder = { Text(kind.targetPlaceholder) },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Text(stringResource(R.string.tunnel_host_service_footer), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedTextField(
                value = path,
                onValueChange = { path = it },
                label = { Text(stringResource(R.string.tunnel_host_path)) },
                placeholder = { Text(stringResource(R.string.tunnel_host_path_hint)) },
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth(),
            )
            Button(
                onClick = {
                    val service = if (isOther) rawService.trim() else kind.scheme + target.trim()
                    onSubmit(
                        IngressRule(
                            hostname = hostname.trim(),
                            service = service,
                            path = path.trim().ifEmpty { null },
                            originRequest = initial?.originRequest,
                        ),
                    )
                },
                enabled = canSave,
                colors = ButtonDefaults.buttonColors(containerColor = OcOrange, contentColor = Color.White),
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (isSaving) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = Color.White)
                    Spacer(Modifier.width(8.dp))
                }
                Text(stringResource(R.string.dns_save))
            }
        }
    }
}

@Composable
private fun protoLabel(kind: IngressServiceKind): String =
    if (kind == IngressServiceKind.OTHER) stringResource(R.string.tunnel_proto_other) else kind.label

@Composable
private fun ConfirmDialog(
    title: String,
    message: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = { TextButton(onClick = onConfirm) { Text(confirmLabel, color = Color(0xFFE5484D)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel)) } },
    )
}

@Composable
private fun DangerButton(label: String, onClick: () -> Unit) {
    OutlinedButton(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Icon(Icons.Outlined.Delete, contentDescription = null, tint = Color(0xFFE5484D), modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Text(label, color = Color(0xFFE5484D))
    }
}

// MARK: - 复用小组件

@Composable
private fun SectionCard(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            title,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 4.dp),
        )
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerLow,
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { content() }
        }
    }
}

@Composable
private fun StatusRow(status: String?) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(stringResource(R.string.tunnel_field_status), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.weight(1f))
        Box(Modifier.size(8.dp).clip(CircleShape).background(tunnelStatusColor(status)))
        Spacer(Modifier.width(6.dp))
        Text(stringResource(tunnelStatusLabel(status)), fontSize = 14.sp, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurface)
    }
}

@Composable
private fun InfoRow(label: String, value: String, mono: Boolean = false) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(12.dp))
        Spacer(Modifier.weight(1f))
        Text(
            value,
            fontSize = if (mono) 12.sp else 14.sp,
            fontFamily = if (mono) FontFamily.Monospace else FontFamily.Default,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun ConnectionRow(conn: TunnelConnection) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Outlined.SettingsEthernet, contentDescription = null, tint = Color(0xFF2FBF71), modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                conn.coloName ?: stringResource(R.string.tunnel_unknown_colo),
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            val sub = listOfNotNull(
                conn.clientVersion?.let { "cloudflared $it" },
                relativeTime(conn.openedAt),
            ).joinToString(" · ")
            if (sub.isNotEmpty()) {
                Text(sub, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

private val dateFormatter: DateTimeFormatter = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)

private fun formatDate(iso: String?): String? {
    if (iso.isNullOrEmpty()) return null
    return runCatching {
        Instant.parse(iso).atZone(ZoneId.systemDefault()).format(dateFormatter)
    }.getOrNull()
}

private fun relativeTime(iso: String?): String? {
    if (iso.isNullOrEmpty()) return null
    return runCatching {
        val millis = Instant.parse(iso).toEpochMilli()
        DateUtils.getRelativeTimeSpanString(millis, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS).toString()
    }.getOrNull()
}
