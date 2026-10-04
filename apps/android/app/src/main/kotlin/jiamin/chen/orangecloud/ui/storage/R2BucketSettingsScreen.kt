package jiamin.chen.orangecloud.ui.storage

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.foundation.clickable
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
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

@Composable
fun R2BucketSettingsScreen(
    onBack: () -> Unit,
    onOpenSql: (bucket: String) -> Unit = {},
    viewModel: R2BucketSettingsViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    val snackbarHostState = remember { SnackbarHostState() }
    val genericErr = stringResource(R.string.error_generic)
    val corsClearedMsg = stringResource(R.string.r2_cors_cleared)
    var confirmCatalog by remember { mutableStateOf(false) }
    val domainRemovedMsg = stringResource(R.string.r2_domain_removed)

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                BucketSettingsEvent.CorsCleared -> snackbarHostState.showSnackbar(corsClearedMsg)
                BucketSettingsEvent.DomainRemoved -> snackbarHostState.showSnackbar(domainRemovedMsg)
                is BucketSettingsEvent.Error -> snackbarHostState.showSnackbar(event.message ?: genericErr)
            }
        }
    }

    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize().systemBarsPadding()) {
            Column(Modifier.fillMaxSize()) {
                SkyHeader(
                    title = stringResource(R.string.r2_bucket_settings),
                    onSky = onSky,
                    isLoading = state.isLoading,
                    onRefresh = { viewModel.load() },
                    onBack = onBack,
                    titleSize = 22,
                    backDescription = stringResource(R.string.common_back),
                    refreshDescription = stringResource(R.string.common_refresh),
                )
                if (state.missingScope) {
                    SkyEmptyState(Icons.Outlined.Lock, stringResource(R.string.scope_missing), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }
                } else {
                    Column(
                        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        // 本月用量（best-effort：authz 挡 / 免费账号则不显示）
                        state.usage?.let { u ->
                            SectionTitle(stringResource(R.string.r2_usage))
                            Card {
                                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text(stringResource(R.string.r2_usage_storage, formatBytes(u.storageBytes)), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurface)
                                    Text(stringResource(R.string.r2_usage_requests, u.totalRequests, u.classARequests, u.classBRequests), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }

                        // 近 30 天带宽（按桶；区域桶按「区域_桶名」查询，best-effort）
                        state.bandwidth?.let { R2BandwidthCard(it) }

                        // 公开访问 r2.dev
                        Card {
                            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text(stringResource(R.string.r2_public_access), fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface)
                                    Text(
                                        state.publicDomain?.takeIf { state.publicEnabled } ?: stringResource(R.string.r2_public_access_desc),
                                        fontSize = 13.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Spacer(Modifier.width(12.dp))
                                Switch(
                                    checked = state.publicEnabled,
                                    onCheckedChange = { viewModel.setPublic(it) },
                                    enabled = state.canWrite && state.publicLoaded && !state.isTogglingPublic,
                                )
                            }
                        }

                        // 自定义域
                        SectionTitle(stringResource(R.string.r2_custom_domains))
                        if (state.customDomains.isEmpty()) {
                            HintText(stringResource(R.string.r2_custom_domains_empty))
                        } else {
                            state.customDomains.forEach { d ->
                                Card {
                                    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                                        Text(d.domain, fontSize = 14.sp, fontFamily = FontFamily.Monospace, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
                                        if (state.canWrite) {
                                            IconButton(onClick = { viewModel.removeDomain(d.domain) }) {
                                                Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.r2_delete), tint = Color(0xFFE5484D))
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 数据目录（Iceberg）。启用是计费动作，故走二次确认。
                        if (state.canReadCatalog && state.catalogLoaded) {
                            SectionTitle(stringResource(R.string.r2_catalog))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text(
                                        stringResource(R.string.r2_catalog_enable),
                                        fontSize = 15.sp,
                                        color = MaterialTheme.colorScheme.onSurface,
                                    )
                                    Text(
                                        stringResource(R.string.r2_catalog_desc),
                                        fontSize = 12.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Switch(
                                    checked = state.catalogEnabled,
                                    onCheckedChange = { on ->
                                        if (on) confirmCatalog = true else viewModel.setCatalogEnabled(false)
                                    },
                                    enabled = state.canWriteCatalog && !state.isCatalogMutating,
                                )
                            }
                            if (state.catalogEnabled) {
                                state.catalog?.name?.let { HintText(it) }
                                if (state.catalogNamespaces.isEmpty()) {
                                    HintText(stringResource(R.string.r2_catalog_no_namespaces))
                                } else {
                                    state.catalogNamespaces.forEach { HintText(it.displayName) }
                                }
                                // R2 SQL 控制台（2026-08 起按扫描量计费，入口文案见控制台内提示）
                                if (state.canQuerySql) {
                                    Text(
                                        stringResource(R.string.r2sql_entry),
                                        fontSize = 14.sp,
                                        fontWeight = FontWeight.Medium,
                                        color = jiamin.chen.orangecloud.core.design.theme.OcOrange,
                                        modifier = Modifier
                                            .clickable { onOpenSql(state.bucket) }
                                            .padding(vertical = 6.dp),
                                    )
                                }
                            }
                        }

                        // CORS
                        SectionTitle(stringResource(R.string.r2_cors))
                        if (state.corsRules.isEmpty()) {
                            HintText(stringResource(R.string.r2_cors_empty))
                        } else {
                            state.corsRules.forEachIndexed { i, rule ->
                                Card {
                                    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        rule.allowed?.origins?.takeIf { it.isNotEmpty() }?.let {
                                            Text(stringResource(R.string.r2_cors_rule_origins, it.joinToString(", ")), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface)
                                        }
                                        rule.allowed?.methods?.takeIf { it.isNotEmpty() }?.let {
                                            Text(stringResource(R.string.r2_cors_rule_methods, it.joinToString(", ")), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                    }
                                }
                            }
                            if (state.canWrite) {
                                OutlinedButton(onClick = { viewModel.clearCors() }, modifier = Modifier.fillMaxWidth()) {
                                    Text(stringResource(R.string.r2_cors_clear), color = Color(0xFFE5484D))
                                }
                            }
                        }
                    }
                }
            }
            SnackbarHost(snackbarHostState, modifier = Modifier.align(Alignment.BottomCenter))
        }
    }

    if (confirmCatalog) {
        AlertDialog(
            onDismissRequest = { confirmCatalog = false },
            title = { Text(stringResource(R.string.r2_catalog_enable)) },
            text = { Text(stringResource(R.string.r2_catalog_enable_confirm)) },
            confirmButton = {
                TextButton(onClick = { viewModel.setCatalogEnabled(true); confirmCatalog = false }) {
                    Text(stringResource(R.string.r2_catalog_enable))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmCatalog = false }) { Text(stringResource(R.string.dns_cancel)) }
            },
        )
    }
}

@Composable
private fun Card(content: @Composable () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
        content = content,
    )
}

@Composable
private fun SectionTitle(text: String) {
    Text(text, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 4.dp, top = 4.dp))
}

@Composable
private fun HintText(text: String) {
    Text(text, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 4.dp))
}
