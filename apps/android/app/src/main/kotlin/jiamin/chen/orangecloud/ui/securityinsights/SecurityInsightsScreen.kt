package jiamin.chen.orangecloud.ui.securityinsights

import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.GppGood
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import jiamin.chen.orangecloud.R
import jiamin.chen.orangecloud.core.design.SkyBackground
import jiamin.chen.orangecloud.core.design.SkyEmptyState
import jiamin.chen.orangecloud.core.design.SkyHeader
import jiamin.chen.orangecloud.core.design.StatusDot
import jiamin.chen.orangecloud.core.design.onSky
import jiamin.chen.orangecloud.core.design.rememberSkyPhase
import jiamin.chen.orangecloud.core.design.showApiError
import jiamin.chen.orangecloud.core.util.launchCustomTab
import jiamin.chen.orangecloud.data.model.SecurityInsight
import jiamin.chen.orangecloud.data.model.SecurityInsightSeverity
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * 域名安全洞察：按严重度分组（严重 > 中等 > 低），每条可「去处理」/「忽略」，页头「立即扫描」。
 * 扫描是异步的，发起后提示稍后刷新；每个账户每 24 小时最多 5 次。
 */
@Composable
fun SecurityInsightsScreen(
    onBack: () -> Unit,
    viewModel: SecurityInsightsViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    val scanStartedMsg = stringResource(R.string.si_scan_started)
    val dismissedMsg = stringResource(R.string.si_dismissed)
    val genericErr = stringResource(R.string.error_generic)

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                SecurityInsightsEvent.ScanStarted -> snackbarHostState.showSnackbar(scanStartedMsg)
                SecurityInsightsEvent.Dismissed -> snackbarHostState.showSnackbar(dismissedMsg)
                is SecurityInsightsEvent.Error ->
                    snackbarHostState.showApiError(context, event.message ?: genericErr, event.documentationUrl)
            }
        }
    }

    // 严重 > 中等 > 低 > 未知；组内按出现时间倒序
    val groups = remember(state.insights) {
        state.insights
            .groupBy { it.severityLevel }
            .toSortedMap(compareBy { it.ordinal })
            .mapValues { (_, list) -> list.sortedByDescending { it.since.orEmpty() } }
    }

    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize().systemBarsPadding()) {
            Column(Modifier.fillMaxSize()) {
                SkyHeader(
                    title = stringResource(R.string.si_title),
                    onSky = onSky,
                    isLoading = state.isLoading,
                    onRefresh = { viewModel.load() },
                    onBack = onBack,
                    titleSize = 22,
                    backDescription = stringResource(R.string.common_back),
                    refreshDescription = stringResource(R.string.common_refresh),
                    actions = {
                        if (state.canWrite && !state.missingScope) {
                            TextButton(onClick = { viewModel.scan() }, enabled = !state.isScanning) {
                                if (state.isScanning) {
                                    CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp, color = onSky)
                                    Spacer(Modifier.width(6.dp))
                                }
                                Text(stringResource(R.string.si_scan_now), color = onSky)
                            }
                        }
                    },
                )
                when {
                    state.missingScope ->
                        SkyEmptyState(Icons.Outlined.Lock, stringResource(R.string.scope_missing), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }

                    state.insights.isEmpty() && state.isLoading ->
                        Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = onSky) }

                    state.insights.isEmpty() && state.hasError ->
                        SkyEmptyState(Icons.Outlined.Security, stringResource(R.string.error_generic), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }

                    state.insights.isEmpty() -> Column(Modifier.fillMaxSize()) {
                        Box(Modifier.weight(1f)) {
                            SkyEmptyState(Icons.Outlined.GppGood, stringResource(R.string.si_empty), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }
                        }
                        ScanLimitNote(onSky, Modifier.padding(horizontal = 24.dp, vertical = 16.dp))
                    }

                    else -> LazyColumn(
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        groups.forEach { (severity, list) ->
                            item(key = "h:${severity.name}") {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    modifier = Modifier.padding(start = 4.dp, top = 6.dp),
                                ) {
                                    StatusDot(severityColor(severity), size = 7.dp)
                                    Spacer(Modifier.width(6.dp))
                                    Text(
                                        "${severityLabel(severity, list.firstOrNull()?.severity)} · ${list.size}",
                                        color = onSky,
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 13.sp,
                                    )
                                }
                            }
                            items(list, key = { it.id }) { insight ->
                                InsightCard(
                                    insight = insight,
                                    canDismiss = state.canWrite,
                                    dismissing = insight.id in state.dismissing,
                                    onResolve = { url -> runCatching { context.launchCustomTab(Uri.parse(url)) } },
                                    onDismiss = { viewModel.dismiss(insight) },
                                )
                            }
                        }
                        item(key = "note") { ScanLimitNote(onSky, Modifier.padding(horizontal = 8.dp, vertical = 12.dp)) }
                    }
                }
            }
            SnackbarHost(snackbarHostState, modifier = Modifier.align(Alignment.BottomCenter))
        }
    }
}

@Composable
private fun ScanLimitNote(onSky: Color, modifier: Modifier = Modifier) {
    Text(
        stringResource(R.string.si_scan_limit_note),
        fontSize = 12.sp,
        color = onSky.copy(alpha = 0.7f),
        modifier = modifier,
    )
}

@Composable
private fun InsightCard(
    insight: SecurityInsight,
    canDismiss: Boolean,
    dismissing: Boolean,
    onResolve: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(start = 16.dp, end = 8.dp, top = 14.dp, bottom = 6.dp)) {
            Text(
                insightTypeLabel(insight.issueType),
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.padding(end = 8.dp),
            )
            insight.subject?.takeIf { it.isNotBlank() }?.let {
                Text(
                    it,
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.padding(top = 2.dp, end = 8.dp),
                )
            }
            formatDate(insight.since)?.let {
                Text(
                    it,
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 2.dp),
                )
            }
            val resolveUrl = insight.resolveUrl
            if (resolveUrl != null || canDismiss) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    if (resolveUrl != null) {
                        TextButton(onClick = { onResolve(resolveUrl) }) {
                            Text(insight.resolveText?.takeIf { it.isNotBlank() } ?: stringResource(R.string.si_resolve))
                        }
                    }
                    if (canDismiss) {
                        TextButton(onClick = onDismiss, enabled = !dismissing) {
                            Text(stringResource(R.string.si_dismiss), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            } else {
                Spacer(Modifier.size(8.dp))
            }
        }
    }
}

/** 洞察类型 → 中文标签；CF 新增的类型显示原文（下划线换空格）。 */
@Composable
private fun insightTypeLabel(type: String?): String = when (type) {
    "compliance_violation" -> stringResource(R.string.si_type_compliance_violation)
    "email_security" -> stringResource(R.string.si_type_email_security)
    "exposed_infrastructure" -> stringResource(R.string.si_type_exposed_infrastructure)
    "insecure_configuration" -> stringResource(R.string.si_type_insecure_configuration)
    "weak_authentication" -> stringResource(R.string.si_type_weak_authentication)
    "configuration_suggestion" -> stringResource(R.string.si_type_configuration_suggestion)
    null, "" -> "—"
    else -> type.replace('_', ' ')
}

@Composable
private fun severityLabel(severity: SecurityInsightSeverity, raw: String?): String = when (severity) {
    SecurityInsightSeverity.CRITICAL -> stringResource(R.string.si_severity_critical)
    SecurityInsightSeverity.MODERATE -> stringResource(R.string.si_severity_moderate)
    SecurityInsightSeverity.LOW -> stringResource(R.string.si_severity_low)
    SecurityInsightSeverity.UNKNOWN -> raw?.takeIf { it.isNotBlank() } ?: "—"
}

private fun severityColor(severity: SecurityInsightSeverity): Color = when (severity) {
    SecurityInsightSeverity.CRITICAL -> Color(0xFFE5484D)
    SecurityInsightSeverity.MODERATE -> Color(0xFFC77C00)
    SecurityInsightSeverity.LOW -> Color(0xFF3E8ED0)
    SecurityInsightSeverity.UNKNOWN -> Color(0xFF9AA0A6)
}

private val dateFormatter: DateTimeFormatter = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM)

private fun formatDate(iso: String?): String? {
    if (iso.isNullOrBlank()) return null
    val instant = runCatching { Instant.parse(iso) }.getOrNull()
        ?: runCatching { OffsetDateTime.parse(iso).toInstant() }.getOrNull()
        ?: return iso
    return instant.atZone(ZoneId.systemDefault()).format(dateFormatter)
}
