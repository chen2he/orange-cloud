package jiamin.chen.orangecloud.ui.storage

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import jiamin.chen.orangecloud.R
import jiamin.chen.orangecloud.core.design.SkyEmptyState
import jiamin.chen.orangecloud.core.design.theme.OcOrange
import jiamin.chen.orangecloud.data.model.R2Bandwidth

/** 存储各只读列表的通用渲染（权限拦截 / 加载 / 空 / 错误 / 列表）。 */
@Composable
fun <T> StorageListBody(
    state: StorageListUiState<T>,
    onSky: Color,
    emptyIcon: ImageVector,
    emptyText: String,
    onRetry: () -> Unit,
    itemContent: @Composable (T) -> Unit,
) {
    when {
        state.missingScope ->
            SkyEmptyState(Icons.Outlined.Lock, stringResource(R.string.scope_missing), onSky, stringResource(R.string.common_refresh), onRetry)

        state.items.isEmpty() && state.isLoading ->
            Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = onSky) }

        state.items.isEmpty() && state.hasError ->
            SkyEmptyState(emptyIcon, stringResource(R.string.error_generic), onSky, stringResource(R.string.common_refresh), onRetry)

        state.items.isEmpty() ->
            SkyEmptyState(emptyIcon, emptyText, onSky, stringResource(R.string.common_refresh), onRetry)

        else -> LazyColumn(
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            itemsIndexed(state.items) { _, item -> itemContent(item) }
        }
    }
}

/**
 * 与 StorageListBody 同样的状态外壳，但把条目按 groupOf 分组成小节（参考 iOS Workers AI 按任务类型分组）。
 * 排序：「Text Generation」置顶，其余按任务名字母序。空任务归入「其它」。
 */
@Composable
fun <T> StorageGroupedListBody(
    state: StorageListUiState<T>,
    onSky: Color,
    emptyIcon: ImageVector,
    emptyText: String,
    onRetry: () -> Unit,
    groupOf: (T) -> String,
    itemContent: @Composable (T) -> Unit,
) {
    when {
        state.missingScope ->
            SkyEmptyState(Icons.Outlined.Lock, stringResource(R.string.scope_missing), onSky, stringResource(R.string.common_refresh), onRetry)

        state.items.isEmpty() && state.isLoading ->
            Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = onSky) }

        state.items.isEmpty() && state.hasError ->
            SkyEmptyState(emptyIcon, stringResource(R.string.error_generic), onSky, stringResource(R.string.common_refresh), onRetry)

        state.items.isEmpty() ->
            SkyEmptyState(emptyIcon, emptyText, onSky, stringResource(R.string.common_refresh), onRetry)

        else -> {
            val other = stringResource(R.string.dev_ai_task_other)
            val groups = state.items.groupBy { groupOf(it).ifBlank { other } }
                .toList()
                .sortedWith(
                    compareByDescending<Pair<String, List<T>>> { it.first == "Text Generation" }.thenBy { it.first },
                )
            LazyColumn(
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                groups.forEach { (group, rows) ->
                    item(key = "h:$group") {
                        Text(
                            group,
                            color = onSky,
                            fontWeight = FontWeight.Bold,
                            fontSize = 13.sp,
                            modifier = Modifier.padding(top = 6.dp, bottom = 2.dp, start = 4.dp),
                        )
                    }
                    rows.forEach { row -> item { itemContent(row) } }
                }
            }
        }
    }
}

/** 字节人类可读（B/KB/MB/GB/TB）。 */
fun formatBytes(bytes: Long): String {
    if (bytes < 1024) return "$bytes B"
    val units = listOf("KB", "MB", "GB", "TB")
    var v = bytes.toDouble() / 1024
    var i = 0
    while (v >= 1024 && i < units.size - 1) {
        v /= 1024; i++
    }
    return "%.1f %s".format(v, units[i])
}

/**
 * 存储通用列表行：图标 + 标题 + 可选副标题 + 右箭头。onLongClick 提供长按操作（如删除）。
 * badge 是标题右侧的小徽标（如 R2 区域限制桶的「欧盟」）。
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun StorageRow(
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
    showChevron: Boolean = true,
    onClick: (() -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    badge: String? = null,
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier
            .fillMaxWidth()
            .let {
                when {
                    onLongClick != null -> it.combinedClickable(onClick = onClick ?: {}, onLongClick = onLongClick)
                    onClick != null -> it.clickable(onClick = onClick)
                    else -> it
                }
            },
    ) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null, tint = OcOrange, modifier = Modifier.size(24.dp))
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        title,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    if (badge != null) {
                        Spacer(Modifier.width(6.dp))
                        StorageBadge(badge)
                    }
                }
                if (subtitle != null) {
                    Text(
                        subtitle,
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (showChevron && onClick != null) {
                Icon(
                    Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/** 小号描边徽标（R2 / KV 数据驻留区域等）。 */
@Composable
fun StorageBadge(text: String) {
    Surface(
        color = OcOrange.copy(alpha = 0.14f),
        shape = RoundedCornerShape(6.dp),
    ) {
        Text(
            text,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = OcOrange,
            maxLines = 1,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

/** 数据驻留徽标文案（R2 桶 / KV 命名空间共用）：欧盟 / 美国 / FedRAMP；默认区域返回 null（不显示）。 */
@Composable
fun jurisdictionLabel(jurisdiction: String?): String? = when (jurisdiction?.trim()?.lowercase()) {
    null, "", "default" -> null
    "eu" -> stringResource(R.string.r2_jurisdiction_eu)
    "us" -> stringResource(R.string.r2_jurisdiction_us)
    "fedramp", "fedramp-high" -> "FedRAMP"
    else -> jurisdiction.uppercase()
}

/** 近 30 天 R2 带宽卡：上传 / 下载合计 + 统计口径脚注（不含 < 100 KiB 的传输）。 */
@Composable
fun R2BandwidthCard(bandwidth: R2Bandwidth, modifier: Modifier = Modifier) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp)) {
            Text(
                stringResource(R.string.r2_bandwidth),
                fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(Modifier.fillMaxWidth().padding(top = 8.dp)) {
                BandwidthValue(stringResource(R.string.r2_bandwidth_upload), formatBytes(bandwidth.uploadBytes), Modifier.weight(1f))
                BandwidthValue(stringResource(R.string.r2_bandwidth_download), formatBytes(bandwidth.downloadBytes), Modifier.weight(1f))
            }
            Text(
                stringResource(R.string.r2_bandwidth_note),
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }
}

@Composable
private fun BandwidthValue(label: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier) {
        Text(value, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
        Text(label, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
