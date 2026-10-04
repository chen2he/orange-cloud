package jiamin.chen.orangecloud.ui.zones

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.GppMaybe
import androidx.compose.material.icons.outlined.Hub
import androidx.compose.material.icons.outlined.MonitorHeart
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.MailOutline
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.automirrored.outlined.ShowChart
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material.icons.outlined.SwapHoriz
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import jiamin.chen.orangecloud.R
import jiamin.chen.orangecloud.core.design.PlanBadge
import jiamin.chen.orangecloud.core.design.SkyBackground
import jiamin.chen.orangecloud.core.design.SkyHeader
import jiamin.chen.orangecloud.core.design.StatusDot
import jiamin.chen.orangecloud.core.design.ZoneAvatar
import jiamin.chen.orangecloud.core.design.onSky
import jiamin.chen.orangecloud.core.design.rememberSkyPhase
import jiamin.chen.orangecloud.core.design.theme.OcOrange
import jiamin.chen.orangecloud.core.design.theme.OcSuccess
import jiamin.chen.orangecloud.data.model.Zone

/** 域名级深入工具（统一一个回调，新增工具只加枚举项 + ToolRow，免改签名）。 */
enum class ZoneTool { CACHE, RATE_LIMIT, EMAIL_ROUTING, LOAD_BALANCER, HEALTH_CHECK, DNS_SETTINGS, MANAGED_HEADERS, SECURITY_INSIGHTS }

/** 单个域名的工具中枢 + 概览（hero 卡 + 工具分发 + Name Servers）。对应 iOS ZoneDetailView。 */
@Composable
fun ZoneDetailScreen(
    zoneId: String,
    zoneName: String,
    onBack: () -> Unit,
    onOpenDns: () -> Unit,
    onOpenAnalytics: () -> Unit,
    onOpenWaf: () -> Unit,
    onOpenSnippets: () -> Unit,
    onOpenSsl: () -> Unit,
    onOpenSslCerts: () -> Unit,
    onOpenTransform: () -> Unit,
    onOpenAccessRules: () -> Unit,
    onOpenPerformance: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenZoneTool: (ZoneTool) -> Unit,
    viewModel: ZoneDetailViewModel = hiltViewModel(),
) {
    LaunchedEffect(zoneId) { viewModel.bind(zoneId) }
    val zone by viewModel.zone.collectAsStateWithLifecycle()
    val phase = rememberSkyPhase()
    val onSky = phase.onSky

    SkyBackground(phase = phase) {
        Column(Modifier.fillMaxSize().systemBarsPadding()) {
            SkyHeader(
                title = (zone?.name ?: zoneName).ifBlank { stringResource(R.string.nav_zones) },
                onSky = onSky,
                isLoading = false,
                onRefresh = {},
                onBack = onBack,
                titleSize = 24,
                backDescription = stringResource(R.string.common_back),
            )
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp)
                    .padding(bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                zone?.let { HeroCard(it) }

                ToolRow(Icons.Outlined.Dns, stringResource(R.string.zone_tool_dns), onOpenDns)
                // zone 级 DNS 策略（DNSSEC / CNAME 展平 / NS 类型），与逐条记录分开
                ToolRow(Icons.Outlined.Tune, stringResource(R.string.dnss_title), { onOpenZoneTool(ZoneTool.DNS_SETTINGS) })
                ToolRow(Icons.Outlined.SwapHoriz, stringResource(R.string.mh_title), { onOpenZoneTool(ZoneTool.MANAGED_HEADERS) })
                ToolRow(Icons.AutoMirrored.Outlined.ShowChart, stringResource(R.string.zone_tool_analytics), onOpenAnalytics)
                ToolRow(Icons.Outlined.Shield, stringResource(R.string.zone_tool_waf), onOpenWaf)
                // 安全洞察（Security Center，全套餐）：扫描出的配置风险，归在安全类工具旁
                ToolRow(Icons.Outlined.GppMaybe, stringResource(R.string.si_title), { onOpenZoneTool(ZoneTool.SECURITY_INSIGHTS) })
                ToolRow(Icons.Outlined.Bolt, stringResource(R.string.zone_tool_cache), { onOpenZoneTool(ZoneTool.CACHE) })
                ToolRow(Icons.Outlined.Timer, stringResource(R.string.zone_tool_rate_limit), { onOpenZoneTool(ZoneTool.RATE_LIMIT) })
                ToolRow(Icons.Outlined.MailOutline, stringResource(R.string.zone_tool_email_routing), { onOpenZoneTool(ZoneTool.EMAIL_ROUTING) })
                ToolRow(Icons.Outlined.Hub, stringResource(R.string.zone_tool_load_balancer), { onOpenZoneTool(ZoneTool.LOAD_BALANCER) })
                // 与负载均衡的监控器不同源：这里监控单个源站，单源站也能用
                ToolRow(Icons.Outlined.MonitorHeart, stringResource(R.string.hc_title), { onOpenZoneTool(ZoneTool.HEALTH_CHECK) })
                ToolRow(Icons.Outlined.Lock, stringResource(R.string.zone_tool_ssl), onOpenSsl)
                ToolRow(Icons.Outlined.VerifiedUser, stringResource(R.string.zone_tool_ssl_certs), onOpenSslCerts)
                ToolRow(Icons.Outlined.SwapHoriz, stringResource(R.string.zone_tool_transform), onOpenTransform)
                ToolRow(Icons.Outlined.Block, stringResource(R.string.zone_tool_ip_rules), onOpenAccessRules)
                ToolRow(Icons.Outlined.Speed, stringResource(R.string.zone_tool_performance), onOpenPerformance)
                ToolRow(Icons.Outlined.Code, stringResource(R.string.zone_tool_snippets), onOpenSnippets)
                ToolRow(Icons.Outlined.Tune, stringResource(R.string.zone_tool_settings), onOpenSettings)

                zone?.nameServers?.takeIf { it.isNotEmpty() }?.let { NameServersCard(it) }

                Spacer(Modifier.size(4.dp))
                Text(
                    "${stringResource(R.string.zone_id_label)} · $zoneId",
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace,
                    color = onSky.copy(alpha = 0.55f),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@Composable
private fun HeroCard(zone: Zone) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(20.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            Modifier.fillMaxWidth().padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            ZoneAvatar(zone.name, size = 52.dp)
            Text(
                zone.name,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatusDot(zoneStatusColor(zone.displayStatus), size = 7.dp)
                Text(
                    stringResource(zoneStatusLabel(zone.displayStatus)),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = if (zone.isActive) OcSuccess else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                zone.plan?.name?.substringBefore(" ")?.takeIf { it.isNotBlank() }?.let { PlanBadge(it) }
            }
        }
    }
}

@Composable
private fun NameServersCard(servers: List<String>) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            stringResource(R.string.zone_name_servers),
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
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                servers.forEach { server ->
                    Text(
                        server,
                        fontSize = 13.sp,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                }
            }
        }
    }
}

@Composable
private fun ToolRow(icon: ImageVector, label: String, onClick: () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    ) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null, tint = OcOrange, modifier = Modifier.size(24.dp))
            Spacer(Modifier.width(14.dp))
            Text(
                label,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.weight(1f),
            )
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun zoneStatusColor(status: String): Color = when (status) {
    "active" -> OcSuccess
    "pending", "initializing", "moved" -> Color(0xFFC77C00)
    "paused", "deactivated" -> MaterialTheme.colorScheme.error
    else -> MaterialTheme.colorScheme.outline
}

private fun zoneStatusLabel(status: String): Int = when (status) {
    "active" -> R.string.zone_status_active
    "pending", "initializing" -> R.string.zone_status_pending
    else -> R.string.zone_status_paused
}
