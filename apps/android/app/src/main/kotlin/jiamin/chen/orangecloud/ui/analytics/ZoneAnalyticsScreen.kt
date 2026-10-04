package jiamin.chen.orangecloud.ui.analytics

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.automirrored.outlined.ShowChart
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.FilterChip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import jiamin.chen.orangecloud.data.model.FirewallEvent
import jiamin.chen.orangecloud.data.model.SecurityEvents
import jiamin.chen.orangecloud.data.model.TopItem
import jiamin.chen.orangecloud.data.model.TrafficDetails
import jiamin.chen.orangecloud.data.model.TrafficDimension
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
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
import jiamin.chen.orangecloud.core.design.onSky
import jiamin.chen.orangecloud.core.design.rememberSkyPhase
import jiamin.chen.orangecloud.core.design.theme.OcOrange
import jiamin.chen.orangecloud.data.model.AnalyticsTimeRange
import jiamin.chen.orangecloud.data.model.TrafficDataPoint

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ZoneAnalyticsScreen(
    onBack: () -> Unit,
    onShowPaywall: () -> Unit = {},
    viewModel: ZoneAnalyticsViewModel = hiltViewModel(),
) {
    val ui by viewModel.uiState.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky

    androidx.compose.runtime.LaunchedEffect(Unit) {
        viewModel.needsPro.collect { onShowPaywall() }
    }

    SkyBackground(phase = phase) {
        Column(Modifier.fillMaxSize().systemBarsPadding()) {
            SkyHeader(
                title = ui.zoneName.ifBlank { stringResource(R.string.analytics_title) },
                onSky = onSky,
                isLoading = ui.isLoading,
                onRefresh = { viewModel.refresh() },
                onBack = onBack,
                titleSize = 22,
                backDescription = stringResource(R.string.common_back),
                refreshDescription = stringResource(R.string.common_refresh),
            )

            when {
                ui.missingScope ->
                    SkyEmptyState(Icons.Outlined.Lock, stringResource(R.string.scope_missing), onSky, stringResource(R.string.common_refresh)) { viewModel.refresh() }

                ui.points.isEmpty() && ui.isLoading ->
                    Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = onSky) }

                else -> Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp)
                        .padding(bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    RangeSelector(ui.range, onSky) { viewModel.selectRange(it) }

                    if (ui.points.isEmpty()) {
                        Spacer(Modifier.height(40.dp))
                        SkyEmptyState(Icons.AutoMirrored.Outlined.ShowChart, stringResource(R.string.analytics_empty), onSky, stringResource(R.string.common_refresh)) { viewModel.refresh() }
                    } else {
                        ui.summary?.let { SummaryGrid(it) }
                        ChartCard(stringResource(R.string.analytics_requests), ui.points) { it.requests.toFloat() }
                        ChartCard(stringResource(R.string.analytics_bandwidth), ui.points) { it.bytes.toFloat() }
                        if (ui.countries.isNotEmpty()) CountryBreakdownCard(ui.countries)
                        // adaptive 明细（同一时间范围、同一 Pro 门槛），与上面的图表互不影响
                        TrafficDetailsCard(ui.details)
                        SecurityEventsCard(ui.security)
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RangeSelector(range: AnalyticsTimeRange, onSky: Color, onSelect: (AnalyticsTimeRange) -> Unit) {
    val options = AnalyticsTimeRange.entries
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        options.forEachIndexed { index, option ->
            SegmentedButton(
                selected = option == range,
                onClick = { onSelect(option) },
                shape = SegmentedButtonDefaults.itemShape(index, options.size),
            ) {
                Text(stringResource(rangeLabel(option)))
            }
        }
    }
}

@Composable
private fun SummaryGrid(summary: TrafficSummary) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatCard(stringResource(R.string.analytics_requests), formatCount(summary.requests), Modifier.weight(1f))
            StatCard(stringResource(R.string.analytics_bandwidth), formatBytes(summary.bytes), Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatCard(stringResource(R.string.analytics_uniques), formatCount(summary.uniques), Modifier.weight(1f))
            StatCard(stringResource(R.string.analytics_cache_hit), "${(summary.cacheHitRate * 100).toInt()}%", Modifier.weight(1f))
        }
    }
}

@Composable
private fun StatCard(label: String, value: String, modifier: Modifier = Modifier) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = modifier,
    ) {
        Column(Modifier.padding(14.dp)) {
            Text(value, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
            Spacer(Modifier.height(2.dp))
            Text(label, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ChartCard(title: String, points: List<TrafficDataPoint>, value: (TrafficDataPoint) -> Float) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp)) {
            Text(title, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(12.dp))
            TrafficChart(points, value, Modifier.fillMaxWidth().height(120.dp))
        }
    }
}

/** 晨昏面积图：橙色描边 + 橙→透明面积填充。 */
@Composable
private fun TrafficChart(points: List<TrafficDataPoint>, value: (TrafficDataPoint) -> Float, modifier: Modifier) {
    val values = points.map(value)
    val max = (values.maxOrNull() ?: 0f).coerceAtLeast(1f)
    Canvas(modifier) {
        val n = values.size
        if (n == 0) return@Canvas
        val w = size.width
        val h = size.height
        val stepX = if (n > 1) w / (n - 1) else 0f
        fun px(i: Int) = if (n > 1) i * stepX else w / 2
        fun py(v: Float) = h - (v / max) * h * 0.92f - h * 0.04f

        val line = Path().apply {
            moveTo(px(0), py(values[0]))
            for (i in 1 until n) lineTo(px(i), py(values[i]))
        }
        val area = Path().apply {
            addPath(line)
            lineTo(px(n - 1), h)
            lineTo(px(0), h)
            close()
        }
        drawPath(
            area,
            Brush.verticalGradient(listOf(OcOrange.copy(alpha = 0.35f), OcOrange.copy(alpha = 0f))),
        )
        drawPath(line, color = OcOrange, style = Stroke(width = 3f))
        // 末点高亮
        drawCircle(OcOrange, radius = 4f, center = Offset(px(n - 1), py(values[n - 1])))
    }
}

/** 按国家/地区请求量（晨昏地图的数据替身：旗帜 + 占比条 + 计数，取前 8）。 */
@Composable
private fun CountryBreakdownCard(countries: List<jiamin.chen.orangecloud.data.model.CountryTraffic>) {
    val top = countries.take(8)
    val max = (top.maxOfOrNull { it.requests } ?: 1L).coerceAtLeast(1L)
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(stringResource(R.string.analytics_top_countries), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            top.forEach { c ->
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(flagEmoji(c.country), fontSize = 16.sp)
                        Spacer(Modifier.height(0.dp))
                        Text(
                            "  ${c.country}",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.weight(1f),
                        )
                        Text(formatCount(c.requests), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    // 占比条
                    Box(Modifier.fillMaxWidth().height(6.dp).background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(3.dp))) {
                        Box(
                            Modifier
                                .fillMaxWidth(fraction = (c.requests.toFloat() / max).coerceIn(0.02f, 1f))
                                .height(6.dp)
                                .background(OcOrange, RoundedCornerShape(3.dp)),
                        )
                    }
                }
            }
        }
    }
}

/** 「访问明细」：四个维度切换，各显示前 10。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TrafficDetailsCard(section: AdaptiveSection<TrafficDetails>) {
    var dimension by rememberSaveable { mutableStateOf(TrafficDimension.COUNTRY) }
    AdaptiveCard(stringResource(R.string.an_details), section) { data, clamped ->
        if (clamped) AdaptiveNote(stringResource(R.string.an_clamped))
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            TrafficDimension.entries.forEach { d ->
                FilterChip(
                    selected = dimension == d,
                    onClick = { dimension = d },
                    label = { Text(stringResource(dimensionLabel(d)), fontSize = 12.sp) },
                )
            }
        }
        val items = data.top[dimension].orEmpty()
        if (items.isEmpty()) {
            AdaptiveNote(stringResource(R.string.an_no_data))
        } else {
            TopList(items) { label ->
                if (dimension == TrafficDimension.COUNTRY) "${flagEmoji(label)}  $label" else label
            }
        }
    }
}

/** 「安全事件」：按处置方式 / 按来源计数 + 最近 20 条事件。 */
@Composable
private fun SecurityEventsCard(section: AdaptiveSection<SecurityEvents>) {
    AdaptiveCard(stringResource(R.string.an_security), section) { data, clamped ->
        if (clamped) AdaptiveNote(stringResource(R.string.an_clamped))
        if (data.isEmpty) {
            AdaptiveNote(stringResource(R.string.an_no_data))
        } else {
            if (data.byAction.isNotEmpty()) {
                AdaptiveSubheading(stringResource(R.string.an_by_action))
                TopList(data.byAction) { actionText(it) }
            }
            if (data.bySource.isNotEmpty()) {
                AdaptiveSubheading(stringResource(R.string.an_by_source))
                TopList(data.bySource) { it }
            }
            if (data.recent.isNotEmpty()) {
                AdaptiveSubheading(stringResource(R.string.an_recent_events))
                data.recent.forEach { FirewallEventRow(it) }
            }
        }
    }
}

/** 明细段外壳：标题 + 加载中 / 不可用说明 / 内容。 */
@Composable
private fun <T> AdaptiveCard(
    title: String,
    section: AdaptiveSection<T>,
    content: @Composable (data: T, clamped: Boolean) -> Unit,
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            when (section) {
                AdaptiveSection.Loading -> Box(Modifier.fillMaxWidth().padding(vertical = 8.dp), Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp, color = OcOrange)
                }
                AdaptiveSection.Unavailable -> AdaptiveNote(stringResource(R.string.an_unavailable))
                is AdaptiveSection.Ready -> content(section.data, section.clamped)
            }
        }
    }
}

@Composable
private fun AdaptiveNote(text: String) {
    Text(text, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun AdaptiveSubheading(text: String) {
    Text(text, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface)
}

/** 排行列表：取值 + 次数 + 占比条（相对第一名）。 */
@Composable
private fun TopList(items: List<TopItem>, labelOf: @Composable (String) -> String) {
    val max = (items.maxOfOrNull { it.count } ?: 1L).coerceAtLeast(1L)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items.forEach { item ->
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        labelOf(item.label),
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(formatCount(item.count), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Box(Modifier.fillMaxWidth().height(4.dp).background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(2.dp))) {
                    Box(
                        Modifier
                            .fillMaxWidth(fraction = (item.count.toFloat() / max).coerceIn(0.02f, 1f))
                            .height(4.dp)
                            .background(OcOrange, RoundedCornerShape(2.dp)),
                    )
                }
            }
        }
    }
}

/** 一条安全事件：处置 + 主机/路径，下一行 IP · 国家 · 时间 · Ray ID。 */
@Composable
private fun FirewallEventRow(event: FirewallEvent) {
    Column(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            event.action?.let {
                Box(
                    Modifier
                        .background(OcOrange.copy(alpha = 0.16f), RoundedCornerShape(6.dp))
                        .padding(horizontal = 6.dp, vertical = 1.dp),
                ) { Text(actionText(it), color = OcOrange, fontSize = 11.sp, fontWeight = FontWeight.SemiBold) }
                Spacer(Modifier.width(6.dp))
            }
            Text(
                listOfNotNull(event.clientRequestHTTPHost, event.clientRequestPath).joinToString(""),
                fontSize = 12.sp,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        val meta = listOfNotNull(
            event.clientIP,
            event.clientCountryName?.takeIf { it.isNotBlank() },
            event.source,
            formatEventTime(event.datetime),
            event.rayName,
        ).joinToString(" · ")
        if (meta.isNotEmpty()) {
            Text(meta, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

private fun dimensionLabel(d: TrafficDimension): Int = when (d) {
    TrafficDimension.COUNTRY -> R.string.an_dim_country
    TrafficDimension.STATUS -> R.string.an_dim_status
    TrafficDimension.PATH -> R.string.an_dim_path
    TrafficDimension.HOST -> R.string.an_dim_host
}

/** 防火墙处置方式 → 复用 WAF 动作文案；其余（bypass / connection_close 等）原样显示。 */
@Composable
private fun actionText(action: String): String = when (action) {
    "block" -> stringResource(R.string.waf_action_block)
    "challenge" -> stringResource(R.string.waf_action_challenge)
    "managed_challenge" -> stringResource(R.string.waf_action_managed_challenge)
    "jschallenge", "js_challenge" -> stringResource(R.string.waf_action_js_challenge)
    "log" -> stringResource(R.string.waf_action_log)
    "allow", "skip" -> stringResource(R.string.waf_action_allow)
    else -> action
}

private val eventTimeFormatter: DateTimeFormatter = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.SHORT)

private fun formatEventTime(iso: String?): String? = iso?.let {
    runCatching { Instant.parse(it).atZone(ZoneId.systemDefault()).format(eventTimeFormatter) }.getOrNull()
}

/** 两位国家码 → 国旗 emoji（区域指示符）。非两位字母回退地球。 */
private fun flagEmoji(code: String): String {
    val c = code.trim().uppercase()
    if (c.length != 2 || !c.all { it in 'A'..'Z' }) return "🌍"
    val first = Character.toChars(0x1F1E6 + (c[0] - 'A'))
    val second = Character.toChars(0x1F1E6 + (c[1] - 'A'))
    return String(first) + String(second)
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

private fun formatBytes(bytes: Long): String {
    val units = listOf("B", "KB", "MB", "GB", "TB")
    var v = bytes.toDouble()
    var i = 0
    while (v >= 1024 && i < units.size - 1) {
        v /= 1024; i++
    }
    return if (i == 0) "${bytes} ${units[i]}" else "%.1f %s".format(v, units[i])
}
