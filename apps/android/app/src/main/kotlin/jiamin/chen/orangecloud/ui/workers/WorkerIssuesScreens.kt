package jiamin.chen.orangecloud.ui.workers

import android.text.format.DateUtils
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import jiamin.chen.orangecloud.core.design.StatusDot
import jiamin.chen.orangecloud.core.design.onSky
import jiamin.chen.orangecloud.core.design.rememberSkyPhase
import jiamin.chen.orangecloud.core.design.showApiError
import jiamin.chen.orangecloud.core.design.theme.OcOrange
import jiamin.chen.orangecloud.data.model.WorkerIssue
import jiamin.chen.orangecloud.data.model.WorkerIssueOccurrence
import jiamin.chen.orangecloud.data.model.WorkerIssueStatus
import jiamin.chen.orangecloud.data.model.WorkerIssuesSummary
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * Workers Issues 列表（公开测试）。全账户，或从 Worker 详情带 service 进来只看该 Worker。
 * 状态分段：活跃 / 已解决 / 已忽略（默认活跃）。Pro 闸门与实时日志相同，由路由 ProGate 负责。
 */
@Composable
fun WorkerIssuesScreen(
    onBack: () -> Unit,
    onOpenIssue: (String) -> Unit,
    viewModel: WorkerIssuesViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    val genericErr = stringResource(R.string.error_generic)

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                is WorkerIssuesEvent.Error ->
                    snackbarHostState.showApiError(context, event.message ?: genericErr, event.documentationUrl)
            }
        }
    }

    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize().systemBarsPadding()) {
            Column(Modifier.fillMaxSize()) {
                SkyHeader(
                    title = state.service?.let { "${stringResource(R.string.wi_title)} · $it" }
                        ?: stringResource(R.string.wi_title),
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
                    Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        val options = WorkerIssueStatus.filters
                        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                            options.forEachIndexed { index, option ->
                                SegmentedButton(
                                    selected = state.status == option,
                                    onClick = { viewModel.selectStatus(option) },
                                    shape = SegmentedButtonDefaults.itemShape(index, options.size),
                                ) { Text(issueStatusLabel(option), fontSize = 13.sp, maxLines = 1) }
                            }
                        }
                        state.summary?.let { SummaryLine(it, onSky) }
                    }
                    Spacer(Modifier.height(8.dp))
                    when {
                        state.issues.isEmpty() && state.isLoading ->
                            Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = onSky) }

                        state.issues.isEmpty() && state.hasError ->
                            SkyEmptyState(Icons.Outlined.BugReport, stringResource(R.string.error_generic), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }

                        state.issues.isEmpty() -> IssuesEmptyState(onSky)

                        else -> LazyColumn(
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            items(state.issues, key = { it.id }) { issue ->
                                IssueRow(issue, showService = state.service == null, onClick = { onOpenIssue(issue.id) })
                            }
                            if (state.hasMore) {
                                item(key = "more") {
                                    Box(Modifier.fillMaxWidth(), Alignment.Center) {
                                        if (state.isLoadingMore) {
                                            CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp, color = onSky)
                                        } else {
                                            TextButton(onClick = { viewModel.loadMore() }) {
                                                Text(stringResource(R.string.common_load_more), color = onSky)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            SnackbarHost(snackbarHostState, modifier = Modifier.align(Alignment.BottomCenter))
        }
    }
}

@Composable
private fun SummaryLine(summary: WorkerIssuesSummary, onSky: Color) {
    Text(
        stringResource(
            R.string.wi_summary,
            (summary.activeIssues ?: 0L).toInt(),
            (summary.activeOccurrences ?: 0L).toInt(),
        ),
        fontSize = 13.sp,
        color = onSky.copy(alpha = 0.8f),
        modifier = Modifier.padding(horizontal = 4.dp),
    )
}

/** 空态：一句结论 + 一句说明（公开测试、哪些错误会被归类）。 */
@Composable
private fun IssuesEmptyState(onSky: Color) {
    Box(Modifier.fillMaxSize().padding(horizontal = 32.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            androidx.compose.material3.Icon(
                Icons.Outlined.CheckCircle,
                contentDescription = null,
                tint = onSky.copy(alpha = 0.6f),
                modifier = Modifier.size(48.dp),
            )
            Spacer(Modifier.height(12.dp))
            Text(stringResource(R.string.wi_empty), color = onSky.copy(alpha = 0.85f), fontSize = 16.sp)
            Spacer(Modifier.height(6.dp))
            Text(
                stringResource(R.string.wi_empty_hint),
                color = onSky.copy(alpha = 0.65f),
                fontSize = 13.sp,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}

@Composable
private fun IssueRow(issue: WorkerIssue, showService: Boolean, onClick: () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    ) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    issue.title?.takeIf { it.isNotBlank() } ?: issue.id,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                val meta = listOfNotNull(
                    issue.service?.takeIf { showService && it.isNotBlank() },
                    relativeTime(issue.lastObservedMillis),
                ).joinToString(" · ")
                if (meta.isNotEmpty()) {
                    Text(
                        meta,
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            issue.count?.let { count ->
                Spacer(Modifier.width(10.dp))
                Surface(color = OcOrange.copy(alpha = 0.14f), shape = RoundedCornerShape(8.dp)) {
                    Text(
                        stringResource(R.string.wi_count, formatIssueCount(count)),
                        color = OcOrange,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                    )
                }
            }
        }
    }
}

/**
 * 问题详情：字段 + 改状态（需 workers-observability.write，没有就不显示按钮）+ 最近发生（堆栈可折叠）。
 */
@Composable
fun WorkerIssueDetailScreen(
    onBack: () -> Unit,
    viewModel: WorkerIssueDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    val genericErr = stringResource(R.string.error_generic)
    val changedMsg = stringResource(R.string.wi_status_changed)

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                is WorkerIssueDetailEvent.StatusChanged -> snackbarHostState.showSnackbar(changedMsg)
                is WorkerIssueDetailEvent.Error ->
                    snackbarHostState.showApiError(context, event.message ?: genericErr, event.documentationUrl)
            }
        }
    }

    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize().systemBarsPadding()) {
            Column(Modifier.fillMaxSize()) {
                SkyHeader(
                    title = state.issue?.service?.takeIf { it.isNotBlank() } ?: stringResource(R.string.wi_title),
                    onSky = onSky,
                    isLoading = state.isLoading,
                    onRefresh = { viewModel.load() },
                    onBack = onBack,
                    titleSize = 22,
                    backDescription = stringResource(R.string.common_back),
                    refreshDescription = stringResource(R.string.common_refresh),
                )
                val issue = state.issue
                when {
                    state.missingScope ->
                        SkyEmptyState(Icons.Outlined.Lock, stringResource(R.string.scope_missing), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }

                    issue == null && state.isLoading ->
                        Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = onSky) }

                    issue == null ->
                        SkyEmptyState(Icons.Outlined.BugReport, stringResource(R.string.error_generic), onSky, stringResource(R.string.common_refresh)) { viewModel.load() }

                    else -> Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = 16.dp)
                            .padding(bottom = 24.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        IssueInfoCard(issue)
                        if (state.canWrite) {
                            IssueActions(
                                status = issue.status,
                                enabled = !state.isUpdating,
                                onUpdate = viewModel::updateStatus,
                            )
                        }
                        Text(
                            stringResource(R.string.wi_recent),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = onSky.copy(alpha = 0.85f),
                            modifier = Modifier.padding(start = 4.dp, top = 4.dp),
                        )
                        when {
                            state.occurrences.isEmpty() && !state.occurrencesLoaded ->
                                Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), Alignment.Center) {
                                    CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp, color = onSky)
                                }

                            state.occurrences.isEmpty() ->
                                Text(
                                    stringResource(R.string.wi_occurrences_empty),
                                    fontSize = 13.sp,
                                    color = onSky.copy(alpha = 0.7f),
                                    modifier = Modifier.padding(start = 4.dp),
                                )

                            else -> {
                                state.occurrences.forEach { OccurrenceCard(it) }
                                if (state.hasMoreOccurrences) {
                                    Box(Modifier.fillMaxWidth(), Alignment.Center) {
                                        if (state.isLoadingOccurrences) {
                                            CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp, color = onSky)
                                        } else {
                                            TextButton(onClick = { viewModel.loadMoreOccurrences() }) {
                                                Text(stringResource(R.string.common_load_more), color = onSky)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            SnackbarHost(snackbarHostState, modifier = Modifier.align(Alignment.BottomCenter))
        }
    }
}

@Composable
private fun IssueInfoCard(issue: WorkerIssue) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                issue.title?.takeIf { it.isNotBlank() } ?: issue.id,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            issue.service?.takeIf { it.isNotBlank() }?.let { IssueInfoRow(stringResource(R.string.wi_field_worker), it) }
            issue.status?.let { status ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.wi_field_status), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.weight(1f))
                    StatusDot(issueStatusColor(status), size = 7.dp)
                    Spacer(Modifier.width(4.dp))
                    Text(issueStatusLabel(status), fontSize = 14.sp, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurface)
                }
            }
            issue.count?.let { IssueInfoRow(stringResource(R.string.wi_field_count), formatIssueCount(it)) }
            formatTime(issue.firstObservedMillis)?.let { IssueInfoRow(stringResource(R.string.wi_field_first), it) }
            formatTime(issue.lastObservedMillis)?.let { IssueInfoRow(stringResource(R.string.wi_field_last), it) }
            issue.type?.takeIf { it.isNotBlank() }?.let { IssueInfoRow(stringResource(R.string.wi_field_type), it) }
        }
    }
}

/** 按当前状态给出可做的变更：非已解决 → 标记为已解决；非已忽略 → 忽略；非活跃 → 重新打开。 */
@Composable
private fun IssueActions(status: String?, enabled: Boolean, onUpdate: (String) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (status != WorkerIssueStatus.RESOLVED) {
            OutlinedButton(onClick = { onUpdate(WorkerIssueStatus.RESOLVED) }, enabled = enabled, modifier = Modifier.weight(1f)) {
                Text(stringResource(R.string.wi_resolve), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (status != WorkerIssueStatus.IGNORED) {
            OutlinedButton(onClick = { onUpdate(WorkerIssueStatus.IGNORED) }, enabled = enabled, modifier = Modifier.weight(1f)) {
                Text(stringResource(R.string.wi_ignore), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (status != WorkerIssueStatus.ACTIVE) {
            OutlinedButton(onClick = { onUpdate(WorkerIssueStatus.ACTIVE) }, enabled = enabled, modifier = Modifier.weight(1f)) {
                Text(stringResource(R.string.wi_reopen), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun OccurrenceCard(occurrence: WorkerIssueOccurrence) {
    var showStack by rememberSaveable(occurrence.id) { mutableStateOf(false) }
    val error = occurrence.error
    val invocation = occurrence.invocation
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            val headline = listOfNotNull(
                error?.name?.takeIf { it.isNotBlank() },
                error?.message?.takeIf { it.isNotBlank() },
            ).joinToString(": ")
            if (headline.isNotEmpty()) {
                Text(
                    headline,
                    fontSize = 13.sp,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 4,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            // 请求类调用给 方法 + 路径；cron / queue 触发的给对应来源
            val target = listOfNotNull(
                invocation?.method?.takeIf { it.isNotBlank() },
                invocation?.path?.takeIf { it.isNotBlank() } ?: invocation?.url?.takeIf { it.isNotBlank() },
            ).joinToString(" ").ifEmpty {
                invocation?.cron?.takeIf { it.isNotBlank() } ?: invocation?.queue?.takeIf { it.isNotBlank() } ?: invocation?.type.orEmpty()
            }
            val meta = listOfNotNull(
                target.takeIf { it.isNotBlank() },
                invocation?.statusCode?.toString(),
                formatTime(occurrence.timestampMillis),
            ).joinToString(" · ")
            if (meta.isNotEmpty()) {
                Text(meta, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            val stack = error?.stack?.takeIf { it.isNotBlank() }
            if (stack != null) {
                Text(
                    stringResource(if (showStack) R.string.wi_stack_hide else R.string.wi_stack_show),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    color = OcOrange,
                    modifier = Modifier.clickable { showStack = !showStack }.padding(vertical = 4.dp),
                )
                if (showStack) {
                    Text(
                        stack,
                        fontSize = 11.sp,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun IssueInfoRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(12.dp))
        Spacer(Modifier.weight(1f))
        Text(value, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurface)
    }
}

/** 状态 → 文案；未知状态显示原文。 */
@Composable
internal fun issueStatusLabel(status: String): String = when (status) {
    WorkerIssueStatus.ACTIVE -> stringResource(R.string.wi_status_active)
    WorkerIssueStatus.RESOLVED -> stringResource(R.string.wi_status_resolved)
    WorkerIssueStatus.IGNORED -> stringResource(R.string.wi_status_ignored)
    else -> status
}

private fun issueStatusColor(status: String): Color = when (status) {
    WorkerIssueStatus.ACTIVE -> Color(0xFFE5484D)
    WorkerIssueStatus.RESOLVED -> Color(0xFF2FBF71)
    else -> Color(0xFF9AA0A6)
}

internal fun formatIssueCount(n: Long): String = when {
    n >= 1_000_000 -> "%.1fM".format(n / 1_000_000.0)
    n >= 10_000 -> "%.1fK".format(n / 1_000.0)
    else -> n.toString()
}

private fun relativeTime(millis: Long?): String? = millis?.let {
    DateUtils.getRelativeTimeSpanString(it, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS).toString()
}

private val timeFormatter: DateTimeFormatter = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM)

private fun formatTime(millis: Long?): String? = millis?.let {
    runCatching { Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()).format(timeFormatter) }.getOrNull()
}
