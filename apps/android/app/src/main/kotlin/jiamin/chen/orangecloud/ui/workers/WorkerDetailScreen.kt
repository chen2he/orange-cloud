package jiamin.chen.orangecloud.ui.workers

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.clickable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Build
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import jiamin.chen.orangecloud.R
import jiamin.chen.orangecloud.core.design.SkyBackground
import jiamin.chen.orangecloud.core.design.SkyHeader
import jiamin.chen.orangecloud.core.design.onSky
import jiamin.chen.orangecloud.core.design.rememberSkyPhase
import jiamin.chen.orangecloud.core.design.StatusDot
import jiamin.chen.orangecloud.core.design.theme.OcOrange
import jiamin.chen.orangecloud.data.model.AnalyticsTimeRange
import jiamin.chen.orangecloud.data.model.WorkerPreview
import jiamin.chen.orangecloud.data.model.WorkerSeriesPoint
import jiamin.chen.orangecloud.core.util.launchCustomTab
import jiamin.chen.orangecloud.data.model.WorkerStatusCount
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkerDetailScreen(
    onBack: () -> Unit,
    onOpenTail: () -> Unit,
    onOpenSecrets: () -> Unit = {},
    onOpenTriggers: () -> Unit = {},
    onOpenDomains: () -> Unit = {},
    onOpenDeployments: () -> Unit = {},
    onOpenBuilds: () -> Unit = {},
    /** 该 Worker 的 Workers Issues（筛选后的问题列表，Pro 闸门在路由上）。 */
    onOpenIssues: () -> Unit = {},
    onEditCode: () -> Unit = {},
    // 查看免费；写操作（编辑/删除）门控 Pro：编辑走路由 ProGate，删除在此按 isPro 拦（非 Pro → onShowPaywall）
    isPro: Boolean = true,
    onShowPaywall: () -> Unit = {},
    viewModel: WorkerDetailViewModel = hiltViewModel(),
) {
    val worker by viewModel.worker.collectAsStateWithLifecycle()
    val isDeleting by viewModel.isDeleting.collectAsStateWithLifecycle()
    val activeIssues by viewModel.activeIssues.collectAsStateWithLifecycle()
    val previews by viewModel.previews.collectAsStateWithLifecycle()
    val context = androidx.compose.ui.platform.LocalContext.current
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    val snackbar = remember { androidx.compose.material3.SnackbarHostState() }
    var showDelete by remember { mutableStateOf(false) }
    val deleteErr = stringResource(R.string.error_generic)

    LaunchedEffect(Unit) {
        viewModel.deleteEvents.collect { event ->
            when (event) {
                WorkerDeleteEvent.Deleted -> { showDelete = false; onBack() }
                is WorkerDeleteEvent.Error -> { showDelete = false; snackbar.showSnackbar(event.message ?: deleteErr) }
            }
        }
    }

    SkyBackground(phase = phase) {
        Column(Modifier.fillMaxSize().systemBarsPadding()) {
            SkyHeader(
                title = viewModel.scriptName,
                onSky = onSky,
                isLoading = false,
                onRefresh = {},
                onBack = onBack,
                titleSize = 22,
                backDescription = stringResource(R.string.common_back),
            )

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp)
                    .padding(bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Button(
                    onClick = onOpenTail,
                    colors = ButtonDefaults.buttonColors(containerColor = OcOrange, contentColor = Color.White),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Outlined.Terminal, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.tail_title))
                }

                // 管理：变量与密钥 / 触发器 / 域名（各页 Pro 闸门）
                Surface(
                    color = MaterialTheme.colorScheme.surfaceContainerLow,
                    shape = RoundedCornerShape(16.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(Modifier.padding(vertical = 4.dp)) {
                        if (viewModel.canWrite) {
                            ManageRow(Icons.Outlined.Edit, stringResource(R.string.worker_manage_edit), onEditCode)
                        }
                        ManageRow(Icons.Outlined.Key, stringResource(R.string.worker_manage_secrets), onOpenSecrets)
                        ManageRow(Icons.Outlined.Schedule, stringResource(R.string.worker_manage_triggers), onOpenTriggers)
                        ManageRow(Icons.Outlined.Public, stringResource(R.string.worker_manage_domains), onOpenDomains)
                        ManageRow(Icons.Outlined.History, stringResource(R.string.worker_manage_deployments), onOpenDeployments)
                        ManageRow(Icons.Outlined.Build, stringResource(R.string.builds_title), onOpenBuilds)
                        // Workers Issues：带该 Worker 的活跃问题数，点进筛选后的列表
                        if (viewModel.canViewIssues) {
                            ManageRow(
                                Icons.Outlined.BugReport,
                                stringResource(R.string.wi_title),
                                onOpenIssues,
                                trailing = activeIssues?.let { formatIssueCount(it) },
                                trailingHighlight = (activeIssues ?: 0L) > 0L,
                            )
                        }
                    }
                }

                if (viewModel.canViewMetrics) {
                    val metrics by viewModel.metrics.collectAsStateWithLifecycle()
                    val series by viewModel.series.collectAsStateWithLifecycle()
                    val metricsLoading by viewModel.metricsLoading.collectAsStateWithLifecycle()
                    val range by viewModel.range.collectAsStateWithLifecycle()

                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        val options = AnalyticsTimeRange.entries
                        options.forEachIndexed { index, option ->
                            SegmentedButton(
                                selected = option == range,
                                onClick = { viewModel.selectRange(option) },
                                shape = SegmentedButtonDefaults.itemShape(index, options.size),
                            ) {
                                Text(stringResource(rangeLabel(option)))
                            }
                        }
                    }

                    Surface(
                        color = MaterialTheme.colorScheme.surfaceContainerLow,
                        shape = RoundedCornerShape(16.dp),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            when {
                                metricsLoading && metrics == null ->
                                    Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), Alignment.Center) {
                                        androidx.compose.material3.CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp, color = OcOrange)
                                    }

                                else -> metrics?.let { m ->
                                    if (series.size > 1) {
                                        WorkerTrendChart(series, Modifier.fillMaxWidth().height(120.dp))
                                    }
                                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        MetricCell(stringResource(R.string.worker_metric_requests), formatCount(m.requests), Modifier.weight(1f))
                                        MetricCell(stringResource(R.string.worker_metric_errors), formatCount(m.errors), Modifier.weight(1f))
                                        MetricCell(stringResource(R.string.worker_metric_subrequests), formatCount(m.subrequests), Modifier.weight(1f))
                                        MetricCell(stringResource(R.string.worker_metric_error_rate), "%.1f%%".format(m.errorRate), Modifier.weight(1f))
                                    }
                                    m.cpuP50Us?.let { p50 ->
                                        InfoRow(
                                            stringResource(R.string.worker_metric_cpu),
                                            "P50 %.1f ms · P99 %.1f ms".format(p50 / 1000.0, (m.cpuP99Us ?: 0.0) / 1000.0),
                                        )
                                    }
                                }
                            }
                        }
                    }

                    metrics?.statusBreakdown?.takeIf { it.isNotEmpty() }?.let { StatusBreakdownCard(it) }
                }

                Surface(
                    color = MaterialTheme.colorScheme.surfaceContainerLow,
                    shape = RoundedCornerShape(16.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        InfoRow(stringResource(R.string.worker_usage_model), worker?.usageModel ?: "—")
                        InfoRow(
                            stringResource(R.string.worker_logpush),
                            stringResource(if (worker?.logpush == true) R.string.common_on else R.string.common_off),
                        )
                        InfoRow(stringResource(R.string.worker_created), formatIso(worker?.createdOn) ?: "—")
                        InfoRow(stringResource(R.string.worker_modified), formatIso(worker?.modifiedOn) ?: "—")

                        val handlers = worker?.handlers?.takeIf { it.isNotEmpty() }
                        if (handlers != null) {
                            Text(
                                stringResource(R.string.worker_handlers),
                                fontSize = 13.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Handlers(handlers)
                        }
                    }
                }

                // 预览（beta，只读）：列表为空或请求失败时整段不显示
                if (previews.isNotEmpty()) {
                    PreviewsCard(previews) { url ->
                        runCatching { context.launchCustomTab(android.net.Uri.parse(url)) }
                    }
                }

                if (viewModel.canWrite) {
                    androidx.compose.material3.OutlinedButton(
                        onClick = { if (isPro) showDelete = true else onShowPaywall() },
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Color(0xFFE5484D)),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(Icons.Outlined.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.worker_delete_button))
                    }
                }
            }
            androidx.compose.material3.SnackbarHost(snackbar)
        }
    }

    if (showDelete) {
        WorkerDeleteDialog(
            scriptName = viewModel.scriptName,
            isDeleting = isDeleting,
            onConfirm = { viewModel.delete() },
            onDismiss = { if (!isDeleting) showDelete = false },
        )
    }
}

/** 删除 Worker 二次确认：必须原样输入脚本名才启用删除（对齐 iOS / Dashboard）。 */
@Composable
private fun WorkerDeleteDialog(
    scriptName: String,
    isDeleting: Boolean,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    var typed by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf("") }
    val matches = typed.trim() == scriptName
    androidx.compose.material3.AlertDialog(
        onDismissRequest = { if (!isDeleting) onDismiss() },
        title = { Text(stringResource(R.string.worker_delete_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.worker_delete_warn, scriptName), fontSize = 14.sp)
                androidx.compose.material3.OutlinedTextField(
                    value = typed,
                    onValueChange = { typed = it },
                    label = { Text(stringResource(R.string.worker_delete_confirm_label)) },
                    placeholder = { Text(scriptName) },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            androidx.compose.material3.TextButton(onClick = onConfirm, enabled = matches && !isDeleting) {
                Text(stringResource(R.string.worker_delete_button), color = if (matches && !isDeleting) Color(0xFFE5484D) else MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = onDismiss, enabled = !isDeleting) { Text(stringResource(R.string.common_cancel)) }
        },
    )
}

@Composable
private fun ManageRow(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    /** 右侧计数（如活跃问题数）；trailingHighlight 时用强调色。 */
    trailing: String? = null,
    trailingHighlight: Boolean = false,
) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = OcOrange, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(14.dp))
        Text(label, fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
        if (trailing != null) {
            Text(
                trailing,
                fontSize = 14.sp,
                fontWeight = if (trailingHighlight) FontWeight.SemiBold else FontWeight.Normal,
                color = if (trailingHighlight) Color(0xFFE5484D) else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.width(4.dp))
        }
        Icon(
            Icons.AutoMirrored.Outlined.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** 预览列表：名称、首个 URL（点开）、部署时间。 */
@Composable
private fun PreviewsCard(previews: List<WorkerPreview>, onOpenUrl: (String) -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(vertical = 12.dp)) {
            Text(
                stringResource(R.string.worker_previews),
                fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
            previews.forEach { preview ->
                val url = preview.urls?.firstOrNull { it.isNotBlank() }
                Column(
                    Modifier
                        .fillMaxWidth()
                        .let { if (url != null) it.clickable { onOpenUrl(url) } else it }
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    Text(
                        preview.name?.takeIf { it.isNotBlank() } ?: preview.slug ?: preview.id,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Medium,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    url?.let {
                        Text(
                            it,
                            fontSize = 12.sp,
                            color = OcOrange,
                            maxLines = 1,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                        )
                    }
                    formatIso(preview.deployedOn)?.let {
                        Text(
                            stringResource(R.string.worker_preview_deployed, it),
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MetricCell(label: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary, maxLines = 1)
        Spacer(Modifier.height(2.dp))
        Text(label, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
    }
}

private fun rangeLabel(range: AnalyticsTimeRange): Int = when (range) {
    AnalyticsTimeRange.LAST_24H -> R.string.range_24h
    AnalyticsTimeRange.LAST_7D -> R.string.range_7d
    AnalyticsTimeRange.LAST_30D -> R.string.range_30d
}

private fun formatCount(n: Long): String = when {
    n >= 1_000_000 -> "%.1fM".format(n / 1_000_000.0)
    n >= 1_000 -> "%.1fK".format(n / 1_000.0)
    else -> n.toString()
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.weight(1f))
        Spacer(Modifier.width(12.dp))
        Text(
            value,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Handlers(handlers: List<String>) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        handlers.forEach { handler ->
            Box(
                modifier = Modifier
                    .background(OcOrange.copy(alpha = 0.16f), RoundedCornerShape(8.dp))
                    .padding(horizontal = 10.dp, vertical = 5.dp),
            ) {
                Text(handler, color = OcOrange, fontSize = 12.sp, fontWeight = FontWeight.Medium)
            }
        }
    }
}

/** 调用趋势：请求橙色面积+线，错误红色线（与请求共轴，错误恒 ≤ 请求）。 */
@Composable
private fun WorkerTrendChart(points: List<WorkerSeriesPoint>, modifier: Modifier) {
    val requests = points.map { it.requests.toFloat() }
    val errors = points.map { it.errors.toFloat() }
    val maxV = (requests.maxOrNull() ?: 0f).coerceAtLeast(1f)
    val hasErrors = errors.any { it > 0f }
    val errorColor = Color(0xFFE5484D)
    Canvas(modifier) {
        val n = requests.size
        if (n == 0) return@Canvas
        val w = size.width
        val h = size.height
        val stepX = if (n > 1) w / (n - 1) else 0f
        fun px(i: Int) = i * stepX
        fun py(v: Float) = h - (v / maxV) * h * 0.92f - h * 0.04f

        val line = Path().apply {
            moveTo(px(0), py(requests[0]))
            for (i in 1 until n) lineTo(px(i), py(requests[i]))
        }
        val area = Path().apply {
            addPath(line)
            lineTo(px(n - 1), h)
            lineTo(px(0), h)
            close()
        }
        drawPath(area, Brush.verticalGradient(listOf(OcOrange.copy(alpha = 0.30f), OcOrange.copy(alpha = 0f))))
        drawPath(line, color = OcOrange, style = Stroke(width = 3f))
        if (hasErrors) {
            val errLine = Path().apply {
                moveTo(px(0), py(errors[0]))
                for (i in 1 until n) lineTo(px(i), py(errors[i]))
            }
            drawPath(errLine, color = errorColor, style = Stroke(width = 1.5f))
        }
    }
}

@Composable
private fun StatusBreakdownCard(items: List<WorkerStatusCount>) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(stringResource(R.string.worker_status_title), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            items.forEach { item ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    StatusDot(workerStatusColor(item.status), size = 8.dp)
                    Spacer(Modifier.width(10.dp))
                    Text(workerStatusLabel(item.status), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
                    Text(formatCount(item.requests), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun workerStatusLabel(status: String): String = when (status) {
    "success" -> stringResource(R.string.worker_status_success)
    "scriptThrewException" -> stringResource(R.string.worker_status_exception)
    "exceededCpu" -> stringResource(R.string.worker_status_cpu)
    "exceededMemory" -> stringResource(R.string.worker_status_memory)
    "clientDisconnected" -> stringResource(R.string.worker_status_client_disconnect)
    "canceled" -> stringResource(R.string.worker_status_canceled)
    "responseStreamDisconnected" -> stringResource(R.string.worker_status_stream_disconnect)
    else -> status
}

private fun workerStatusColor(status: String): Color = when (status) {
    "success" -> Color(0xFF2FBF71)
    "clientDisconnected", "canceled", "responseStreamDisconnected" -> Color(0xFF9AA0A6)
    else -> Color(0xFFE5484D)
}

private val isoFormatter: DateTimeFormatter =
    DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM)

private fun formatIso(iso: String?): String? {
    if (iso.isNullOrEmpty()) return null
    return runCatching {
        Instant.parse(iso).atZone(ZoneId.systemDefault()).format(isoFormatter)
    }.getOrNull() ?: iso
}
