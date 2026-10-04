package jiamin.chen.orangecloud.ui.dns

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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import jiamin.chen.orangecloud.R
import jiamin.chen.orangecloud.core.design.SkyBackground
import jiamin.chen.orangecloud.core.design.SkyPhase
import jiamin.chen.orangecloud.core.design.theme.OcOrange
import jiamin.chen.orangecloud.data.model.DnsRecord
import jiamin.chen.orangecloud.data.model.DnsShadowInfo
import kotlinx.coroutines.launch
import java.time.LocalTime

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DnsListScreen(
    onBack: () -> Unit,
    viewModel: DnsListViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val isDark = jiamin.chen.orangecloud.core.design.theme.LocalIsDark.current
    val phase = remember(isDark) { SkyPhase.current(isDark, LocalTime.now().hour) }
    val onSky = if (phase.isDark) Color(0xFFF3ECE4) else Color(0xFF24190F)

    var showSheet by remember { mutableStateOf(false) }
    var sheetRecord by remember { mutableStateOf<DnsRecord?>(null) }
    var pendingDelete by remember { mutableStateOf<DnsRecord?>(null) }
    // 点「已被遮蔽」徽标弹出的说明（只读用户也能看）
    var shadowInfoFor by remember { mutableStateOf<DnsRecord?>(null) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    val savedMsg = stringResource(R.string.dns_saved)
    val deletedMsg = stringResource(R.string.dns_deleted)
    val genericErr = stringResource(R.string.error_generic)

    fun hideSheet() {
        scope.launch { sheetState.hide() }.invokeOnCompletion {
            if (!sheetState.isVisible) showSheet = false
        }
    }

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                DnsEvent.Saved -> {
                    hideSheet()
                    snackbarHostState.showSnackbar(savedMsg)
                }
                DnsEvent.Deleted -> {
                    pendingDelete = null
                    hideSheet()
                    snackbarHostState.showSnackbar(deletedMsg)
                }
                is DnsEvent.Error -> snackbarHostState.showSnackbar(event.cfMessage ?: genericErr)
            }
        }
    }

    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize().systemBarsPadding()) {
            Column(Modifier.fillMaxSize()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 8.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.common_back), tint = onSky)
                    }
                    Text(
                        text = uiState.zoneName.ifBlank { stringResource(R.string.dns_title_fallback) },
                        color = onSky,
                        fontSize = 22.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    if (uiState.isLoading) {
                        CircularProgressIndicator(modifier = Modifier.size(22.dp), color = onSky, strokeWidth = 2.dp)
                        Spacer(Modifier.width(12.dp))
                    } else {
                        IconButton(onClick = { viewModel.refresh() }) {
                            Icon(Icons.Outlined.Refresh, stringResource(R.string.common_refresh), tint = onSky)
                        }
                    }
                }

                if (!uiState.canEdit) {
                    Text(
                        text = stringResource(R.string.dns_readonly),
                        color = onSky.copy(alpha = 0.7f),
                        fontSize = 13.sp,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 2.dp),
                    )
                }

                when {
                    uiState.records.isEmpty() && uiState.isLoading ->
                        Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = onSky) }

                    uiState.records.isEmpty() && uiState.loadFailed ->
                        StateMessage(Icons.Outlined.Dns, stringResource(R.string.error_generic), onSky) { viewModel.refresh() }

                    uiState.records.isEmpty() ->
                        StateMessage(Icons.Outlined.Dns, stringResource(R.string.dns_empty), onSky) { viewModel.refresh() }

                    else -> LazyColumn(
                        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 96.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        items(uiState.records, key = { it.id }) { record ->
                            DnsRow(
                                record,
                                enabled = uiState.canEdit,
                                shadow = uiState.shadow[record.id],
                                onShadowInfo = { shadowInfoFor = record },
                            ) {
                                sheetRecord = record
                                showSheet = true
                            }
                        }
                    }
                }
            }

            if (uiState.canEdit) {
                FloatingActionButton(
                    onClick = {
                        sheetRecord = null
                        showSheet = true
                    },
                    containerColor = OcOrange,
                    contentColor = Color.White,
                    modifier = Modifier.align(Alignment.BottomEnd).padding(20.dp),
                ) {
                    Icon(Icons.Filled.Add, stringResource(R.string.dns_add))
                }
            }

            SnackbarHost(snackbarHostState, modifier = Modifier.align(Alignment.BottomCenter))
        }
    }

    if (showSheet) {
        DnsRecordSheet(
            record = sheetRecord,
            shadowed = sheetRecord?.let { uiState.shadow[it.id]?.shadowed } == true,
            isSaving = uiState.isSaving,
            sheetState = sheetState,
            onSave = { viewModel.save(sheetRecord?.id, it) },
            onDelete = { sheetRecord?.let { pendingDelete = it } },
            onDismiss = { showSheet = false },
        )
    }

    if (shadowInfoFor != null) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { shadowInfoFor = null },
            title = { Text(stringResource(R.string.dns_shadowed)) },
            text = { Text(stringResource(R.string.dns_shadowed_detail)) },
            confirmButton = {
                TextButton(onClick = { shadowInfoFor = null }) { Text(stringResource(R.string.common_done)) }
            },
        )
    }

    pendingDelete?.let { record ->
        DeleteConfirmDialog(
            recordName = record.name,
            onConfirm = { viewModel.delete(record.id) },
            onDismiss = { pendingDelete = null },
        )
    }
}

@Composable
private fun DnsRow(
    record: DnsRecord,
    enabled: Boolean,
    shadow: DnsShadowInfo?,
    onShadowInfo: () -> Unit,
    onClick: () -> Unit,
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onClick),
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TypeBadge(record.type)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    text = record.name,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = record.content,
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                // 被 NS 委派遮蔽：Cloudflare 不会响应这条记录；点徽标看说明
                if (shadow?.shadowed == true) {
                    Spacer(Modifier.height(4.dp))
                    Box(
                        Modifier
                            .background(Color(0xFFE08600).copy(alpha = 0.16f), RoundedCornerShape(6.dp))
                            .clickable(onClick = onShadowInfo)
                            .padding(horizontal = 6.dp, vertical = 2.dp),
                    ) {
                        Text(
                            stringResource(R.string.dns_shadowed),
                            color = Color(0xFFE08600),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
                // NS 委派记录：遮蔽了多少条记录
                if (record.type == "NS" && (shadow?.shadowsCount ?: 0) > 0) {
                    Text(
                        stringResource(R.string.dns_shadows_count, shadow?.shadowsCount ?: 0),
                        fontSize = 12.sp,
                        color = Color(0xFFE08600),
                    )
                }
            }
            ProxyIndicator(record)
        }
    }
}

@Composable
private fun TypeBadge(type: String) {
    val tone = dnsTypeColor(type)
    Box(
        modifier = Modifier
            .size(width = 52.dp, height = 28.dp)
            .background(tone.copy(alpha = 0.16f), RoundedCornerShape(9.dp)),
        contentAlignment = Alignment.Center,
    ) {
        Text(text = type, color = tone, fontSize = 12.5.sp, fontWeight = FontWeight.Bold, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, maxLines = 1)
    }
}

private fun dnsTypeColor(type: String): Color = when (type) {
    "A" -> Color(0xFF3D86E0)
    "AAAA" -> Color(0xFF2BAFA6)
    "CNAME" -> Color(0xFFAF52DE)
    "TXT" -> Color(0xFF2E9D5B)
    "MX" -> Color(0xFFE08600)
    "NS" -> Color(0xFF5856D6)
    else -> Color(0xFF8E8E93)
}

@Composable
private fun ProxyIndicator(record: DnsRecord) {
    when {
        record.isProxied -> Icon(
            Icons.Filled.Cloud,
            contentDescription = stringResource(R.string.dns_proxied),
            tint = OcOrange,
            modifier = Modifier.size(20.dp),
        )
        DnsForm.supportsProxy(record.type) -> Icon(
            Icons.Outlined.CloudOff,
            contentDescription = stringResource(R.string.dns_dns_only),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            modifier = Modifier.size(20.dp),
        )
    }
}

@Composable
private fun StateMessage(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    message: String,
    onSky: Color,
    onRetry: () -> Unit,
) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, contentDescription = null, tint = onSky.copy(alpha = 0.6f), modifier = Modifier.size(48.dp))
            Spacer(Modifier.height(12.dp))
            Text(message, color = onSky.copy(alpha = 0.85f), fontSize = 16.sp)
            Spacer(Modifier.height(8.dp))
            TextButton(onClick = onRetry) { Text(stringResource(R.string.common_refresh)) }
        }
    }
}

@Composable
private fun DeleteConfirmDialog(recordName: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.dns_delete_confirm_title)) },
        text = { Text(stringResource(R.string.dns_delete_confirm_msg, recordName)) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(stringResource(R.string.dns_delete), color = Color(0xFFE5484D))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.dns_cancel)) }
        },
    )
}
