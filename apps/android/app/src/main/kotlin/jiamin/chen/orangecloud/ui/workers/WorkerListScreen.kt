package jiamin.chen.orangecloud.ui.workers

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import jiamin.chen.orangecloud.R
import androidx.compose.runtime.remember
import jiamin.chen.orangecloud.core.design.SkyBackground
import jiamin.chen.orangecloud.core.design.SkyEmptyState
import jiamin.chen.orangecloud.core.design.SkyHeader
import jiamin.chen.orangecloud.core.design.SortMenuButton
import jiamin.chen.orangecloud.core.design.onSky
import jiamin.chen.orangecloud.core.design.rememberSkyPhase
import jiamin.chen.orangecloud.core.design.sorted
import jiamin.chen.orangecloud.core.design.theme.OcOrange
import jiamin.chen.orangecloud.data.model.WorkerScript

@Composable
fun WorkerListScreen(
    onWorkerClick: (String) -> Unit = {},
    onCreate: () -> Unit = {},
    /** Workers Issues（全账户问题列表，Pro 闸门在路由上）。 */
    onOpenIssues: () -> Unit = {},
    viewModel: WorkerListViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val issuesSummary by viewModel.issuesSummary.collectAsStateWithLifecycle()
    val sort by viewModel.sort.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky
    val sortedWorkers = remember(uiState.workers, sort) {
        sort.sorted(uiState.workers, created = { it.createdOn }, modified = { it.modifiedOn })
    }

    SkyBackground(phase = phase) {
      Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().systemBarsPadding()) {
            SkyHeader(
                title = stringResource(R.string.nav_workers),
                onSky = onSky,
                isLoading = uiState.isLoading,
                onRefresh = { viewModel.refresh() },
                refreshDescription = stringResource(R.string.common_refresh),
                actions = {
                    if (uiState.workers.isNotEmpty()) {
                        SortMenuButton(sort = sort, onSky = onSky, onSelect = { viewModel.setSort(it) })
                    }
                },
            )

            when {
                uiState.missingScope ->
                    SkyEmptyState(Icons.Outlined.Lock, stringResource(R.string.scope_missing), onSky, stringResource(R.string.common_refresh)) { viewModel.refresh() }

                uiState.workers.isEmpty() && uiState.isLoading ->
                    Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = onSky) }

                uiState.workers.isEmpty() && uiState.hasError ->
                    SkyEmptyState(Icons.Outlined.Bolt, stringResource(R.string.error_generic), onSky, stringResource(R.string.common_refresh)) { viewModel.refresh() }

                uiState.workers.isEmpty() ->
                    SkyEmptyState(Icons.Outlined.Bolt, stringResource(R.string.workers_empty), onSky, stringResource(R.string.common_refresh)) { viewModel.refresh() }

                else -> LazyColumn(
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    // 「问题」入口：Workers Issues 把未捕获异常 / 5xx / 错误日志归并成问题
                    item(key = "issues") {
                        IssuesEntryRow(
                            subtitle = issuesSummary?.let {
                                stringResource(
                                    R.string.wi_summary,
                                    (it.activeIssues ?: 0L).toInt(),
                                    (it.activeOccurrences ?: 0L).toInt(),
                                )
                            },
                            onClick = onOpenIssues,
                        )
                    }
                    items(sortedWorkers, key = { it.id }) { worker ->
                        WorkerRow(worker, onClick = { onWorkerClick(worker.id) })
                    }
                }
            }
        }
        if (uiState.canWrite && !uiState.missingScope) {
            FloatingActionButton(
                onClick = onCreate,
                containerColor = OcOrange,
                contentColor = Color.White,
                modifier = Modifier.align(Alignment.BottomEnd).padding(20.dp).systemBarsPadding(),
            ) { Icon(Icons.Outlined.Add, contentDescription = stringResource(R.string.worker_create_title)) }
        }
      }
    }
}

@Composable
private fun IssuesEntryRow(subtitle: String?, onClick: () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    ) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier.size(40.dp).clip(CircleShape).background(OcOrange.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Outlined.BugReport, contentDescription = null, tint = OcOrange, modifier = Modifier.size(22.dp))
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    text = stringResource(R.string.wi_title),
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                if (subtitle != null) {
                    Text(
                        text = subtitle,
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun WorkerRow(worker: WorkerScript, onClick: () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    ) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier.size(40.dp).clip(CircleShape).background(OcOrange),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Bolt, contentDescription = null, tint = Color.White, modifier = Modifier.size(22.dp))
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    text = worker.id,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                val subtitle = worker.handlers?.takeIf { it.isNotEmpty() }?.joinToString(" · ")
                    ?: worker.usageModel
                if (subtitle != null) {
                    Text(
                        text = subtitle,
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}
