package jiamin.chen.orangecloud.ui.root

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Apps
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.ExperimentalMaterial3AdaptiveNavigationSuiteApi
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import jiamin.chen.orangecloud.core.util.launchCustomTab
import jiamin.chen.orangecloud.ui.dnssettings.DnsSettingsScreen
import jiamin.chen.orangecloud.ui.managedheaders.ManagedHeadersScreen
import jiamin.chen.orangecloud.ui.registrar.RegistrarScreen
import jiamin.chen.orangecloud.ui.builds.WorkerBuildsScreen
import jiamin.chen.orangecloud.ui.tracer.RequestTracerScreen
import jiamin.chen.orangecloud.ui.urlscanner.URLScannerScreen
import jiamin.chen.orangecloud.ui.healthcheck.HealthCheckScreen
import jiamin.chen.orangecloud.ui.login.LoginViewModel
import jiamin.chen.orangecloud.ui.paywall.PaywallScreen
import jiamin.chen.orangecloud.ui.paywall.ProGateViewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import androidx.navigation.navDeepLink
import jiamin.chen.orangecloud.R
import jiamin.chen.orangecloud.core.design.SkyBackground
import jiamin.chen.orangecloud.core.design.SkyPhase
import jiamin.chen.orangecloud.ui.analytics.ZoneAnalyticsScreen
import jiamin.chen.orangecloud.ui.dashboard.DashboardResourceType
import jiamin.chen.orangecloud.ui.dashboard.DashboardScreen
import jiamin.chen.orangecloud.ui.dns.DnsListScreen
import jiamin.chen.orangecloud.ui.network.TunnelDetailScreen
import jiamin.chen.orangecloud.ui.turnstile.TurnstileDetailScreen
import jiamin.chen.orangecloud.ui.turnstile.TurnstileListScreen
import jiamin.chen.orangecloud.ui.network.TunnelListScreen
import jiamin.chen.orangecloud.ui.paywall.ProGate
import jiamin.chen.orangecloud.ui.waf.WafRulesScreen
import jiamin.chen.orangecloud.ui.cache.ZoneCacheRulesScreen
import jiamin.chen.orangecloud.ui.ratelimit.ZoneRateLimitScreen
import jiamin.chen.orangecloud.ui.email.EmailRoutingScreen
import jiamin.chen.orangecloud.ui.loadbalancer.ZoneLoadBalancerScreen
import jiamin.chen.orangecloud.ui.loadbalancer.PoolListScreen
import jiamin.chen.orangecloud.ui.loadbalancer.MonitorListScreen
import jiamin.chen.orangecloud.ui.zerotrust.ZeroTrustHubScreen
import jiamin.chen.orangecloud.ui.zerotrust.AccessAppsScreen
import jiamin.chen.orangecloud.ui.zerotrust.GatewayRulesScreen
import jiamin.chen.orangecloud.ui.pages.PagesListScreen
import jiamin.chen.orangecloud.ui.pages.PagesProjectDetailScreen
import jiamin.chen.orangecloud.ui.devplatform.DeveloperHubScreen
import jiamin.chen.orangecloud.ui.devplatform.QueuesScreen
import jiamin.chen.orangecloud.ui.devplatform.AIGatewayScreen
import jiamin.chen.orangecloud.ui.devplatform.DurableObjectsScreen
import jiamin.chen.orangecloud.ui.devplatform.HyperdriveScreen
import jiamin.chen.orangecloud.ui.devplatform.WorkersAIScreen
import jiamin.chen.orangecloud.ui.devplatform.AIRunScreen
import jiamin.chen.orangecloud.ui.assistant.AssistantScreen
import jiamin.chen.orangecloud.ui.zones.ZoneTool
import jiamin.chen.orangecloud.ui.update.UpdateDialog
import jiamin.chen.orangecloud.ui.update.UpdateViewModel
import jiamin.chen.orangecloud.ui.whatsnew.WhatsNewDialog
import jiamin.chen.orangecloud.ui.whatsnew.WhatsNewViewModel
import jiamin.chen.orangecloud.ui.login.LoginScreen
import jiamin.chen.orangecloud.ui.toolbox.ToolboxNavHost
import jiamin.chen.orangecloud.ui.settings.IdentityDetailScreen
import jiamin.chen.orangecloud.ui.settings.SettingsScreen
import jiamin.chen.orangecloud.ui.status.StatusScreen
import jiamin.chen.orangecloud.ui.audit.AuditLogScreen
import jiamin.chen.orangecloud.ui.alerting.CFAlertingScreen
import jiamin.chen.orangecloud.ui.redirects.RedirectListsScreen
import jiamin.chen.orangecloud.ui.redirects.RedirectItemsScreen
import jiamin.chen.orangecloud.ui.firewall.ZoneAccessRulesScreen
import jiamin.chen.orangecloud.ui.securityinsights.SecurityInsightsScreen
import jiamin.chen.orangecloud.ui.transform.ZoneTransformScreen
import jiamin.chen.orangecloud.ui.zonesettings.ZonePerformanceScreen
import jiamin.chen.orangecloud.ui.zonesettings.ZoneSettingsScreen
import jiamin.chen.orangecloud.ui.zonesettings.ZoneSslCertsScreen
import jiamin.chen.orangecloud.ui.zonesettings.ZoneSslSettingsScreen
import jiamin.chen.orangecloud.ui.snippets.SnippetEditorScreen
import jiamin.chen.orangecloud.ui.snippets.SnippetsListScreen
import jiamin.chen.orangecloud.ui.storage.D1DatabaseListScreen
import jiamin.chen.orangecloud.ui.storage.D1QueryScreen
import jiamin.chen.orangecloud.ui.storage.D1TableScreen
import jiamin.chen.orangecloud.ui.storage.KVKeyListScreen
import jiamin.chen.orangecloud.ui.storage.KVNamespaceListScreen
import jiamin.chen.orangecloud.ui.storage.R2BucketListScreen
import jiamin.chen.orangecloud.ui.storage.R2BucketSettingsScreen
import jiamin.chen.orangecloud.ui.storage.R2SqlQueryScreen
import jiamin.chen.orangecloud.ui.storage.R2ObjectListScreen
import jiamin.chen.orangecloud.ui.storage.StorageHubScreen
import jiamin.chen.orangecloud.ui.workers.WorkerCreateScreen
import jiamin.chen.orangecloud.ui.workers.WorkerDeploymentsScreen
import jiamin.chen.orangecloud.ui.workers.WorkerDetailScreen
import jiamin.chen.orangecloud.ui.workers.WorkerIssueDetailScreen
import jiamin.chen.orangecloud.ui.workers.WorkerIssuesScreen
import jiamin.chen.orangecloud.ui.workers.WorkerListScreen
import jiamin.chen.orangecloud.ui.workers.WorkerRoutesScreen
import jiamin.chen.orangecloud.ui.workers.WorkerSecretsScreen
import jiamin.chen.orangecloud.ui.workers.WorkerTailScreen
import jiamin.chen.orangecloud.ui.workers.WorkerTriggersScreen
import jiamin.chen.orangecloud.ui.zones.ZoneDetailScreen
import jiamin.chen.orangecloud.ui.zones.ZonesPaneScreen
import java.time.LocalTime

@Composable
fun OrangeCloudRoot(viewModel: RootViewModel = hiltViewModel()) {
    val authState by viewModel.authState.collectAsStateWithLifecycle()
    // 免登录工具箱：呈现在鉴权分支之上的覆盖层，登录页（未登录）与设置页（已登录）共用同一入口。
    var showToolbox by rememberSaveable { mutableStateOf(false) }
    Box(Modifier.fillMaxSize()) {
        when {
            !authState.isReady -> SplashScreen()
            authState.isLoggedIn -> MainScaffold(onOpenToolbox = { showToolbox = true })
            else -> LoginScreen(onOpenToolbox = { showToolbox = true })
        }
        if (showToolbox) {
            // 工具子栈非起点时由内层 NavHost 消费返回；位于起点（hub）时落到此处关闭覆盖层。
            BackHandler { showToolbox = false }
            ToolboxNavHost(onExit = { showToolbox = false })
        }
    }

    // 自助更新提示：仅 sideload 的 direct 包实际触发，覆盖于任意鉴权态之上。
    val updateViewModel: UpdateViewModel = hiltViewModel()
    val update by updateViewModel.available.collectAsStateWithLifecycle()
    val installing by updateViewModel.installing.collectAsStateWithLifecycle()
    val updateContext = LocalContext.current
    update?.let { info ->
        UpdateDialog(
            info = info,
            installing = installing,
            onUpdate = {
                // 应用内安装失败（无权限 / 签名不符 / 下载失败）回退浏览器下载
                updateViewModel.install { url ->
                    runCatching { updateContext.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
                }
            },
            onSkip = updateViewModel::skip,
            onDismiss = updateViewModel::dismiss,
        )
    }
}

private enum class TopDestination(val labelRes: Int, val icon: ImageVector) {
    Dashboard(R.string.nav_dashboard, Icons.Outlined.GridView),
    Zones(R.string.nav_zones, Icons.Outlined.Language),
    Workers(R.string.nav_dev_platform, Icons.Outlined.Apps),
    Storage(R.string.nav_storage, Icons.Outlined.Storage),
    Settings(R.string.nav_settings, Icons.Outlined.Settings),
}

/** 路由表。下钻页（DNS / Worker 详情）也预留 App Shortcuts 深链（Phase E 收尾挂 manifest）。 */
private object Dest {
    const val DASHBOARD = "dashboard"
    const val ZONES = "zones"
    const val WORKERS = "workers"
    const val WORKER_CREATE = "workers/new"
    const val DEV_HUB = "devhub"
    const val DEV_WORKERS_AI = "dev/ai"
    const val DEV_AI_GATEWAY = "dev/gateway"
    const val DEV_QUEUES = "dev/queues"
    const val DEV_HYPERDRIVE = "dev/hyperdrive"
    const val DEV_DO = "dev/do"
    const val DEV_ASSISTANT = "dev/assistant"
    const val AI_RUN_ROUTE = "dev/ai/run/{model}?task={task}&desc={desc}"
    const val STORAGE = "storage"
    const val SETTINGS = "settings"
    const val IDENTITY_ROUTE = "identity/{sessionId}"
    const val TUNNELS = "tunnels"
    const val TURNSTILE = "turnstile"
    const val REGISTRAR = "registrar"
    const val TRACER = "tracer"
    const val URL_SCANNER = "urlscanner"
    const val TUNNEL_DETAIL_ROUTE = "tunnel/{tunnelId}?tunnelName={tunnelName}"
    const val TURNSTILE_DETAIL_ROUTE = "turnstile/{sitekey}"
    const val STATUS = "status"
    const val AUDIT = "audit"
    const val ALERTING = "alerting"
    const val REDIRECTS = "redirects"
    const val REDIRECT_ITEMS_ROUTE = "redirects/{listId}?listName={listName}"
    const val ZERO_TRUST = "zerotrust"
    const val ZT_ACCESS = "zerotrust/access"
    const val ZT_GATEWAY = "zerotrust/gateway"
    const val PAGES = "pages"
    const val PAGES_DETAIL_ROUTE = "pages/{project}"
    const val PAYWALL = "paywall"
    const val WAF_ROUTE = "waf/{zoneId}?zoneName={zoneName}"
    // 存储下钻
    const val R2_BUCKETS = "r2/buckets"
    // jurisdiction：区域限制桶（eu / us / fedramp…）的桶级调用都要带 cf-r2-jurisdiction 头，经路由透传；默认区域为空
    const val R2_OBJECTS_ROUTE = "r2/objects/{bucket}?jurisdiction={jurisdiction}"
    const val R2_BUCKET_SETTINGS_ROUTE = "r2/settings/{bucket}?jurisdiction={jurisdiction}"
    const val R2_SQL_ROUTE = "r2/sql/{bucket}"
    const val D1_DATABASES = "d1/databases"
    const val D1_QUERY_ROUTE = "d1/query/{dbId}?dbName={dbName}"
    const val D1_TABLE_ROUTE = "d1/table/{dbId}?table={table}"
    const val KV_NAMESPACES = "kv/namespaces"
    const val KV_KEYS_ROUTE = "kv/keys/{nsId}?nsTitle={nsTitle}"
    const val ZONE_DETAIL_ROUTE = "zone/{zoneId}?zoneName={zoneName}"
    const val DNS_ROUTE = "dns/{zoneId}?zoneName={zoneName}"
    const val ANALYTICS_ROUTE = "analytics/{zoneId}?zoneName={zoneName}"
    const val SNIPPETS_ROUTE = "snippets/{zoneId}?zoneName={zoneName}"
    const val SNIPPET_EDIT_ROUTE = "snippetEdit/{zoneId}?zoneName={zoneName}&name={name}"
    const val ZONE_SETTINGS_ROUTE = "zonesettings/{zoneId}?zoneName={zoneName}"
    const val SSL_ROUTE = "ssl/{zoneId}?zoneName={zoneName}"
    const val SSL_CERTS_ROUTE = "sslcerts/{zoneId}?zoneName={zoneName}"
    const val PERFORMANCE_ROUTE = "performance/{zoneId}?zoneName={zoneName}"
    const val TRANSFORM_ROUTE = "transform/{zoneId}?zoneName={zoneName}"
    const val ACCESS_RULES_ROUTE = "accessrules/{zoneId}?zoneName={zoneName}"
    const val CACHE_ROUTE = "cache/{zoneId}?zoneName={zoneName}"
    const val RATE_LIMIT_ROUTE = "ratelimit/{zoneId}?zoneName={zoneName}"
    const val EMAIL_ROUTE = "email/{zoneId}?zoneName={zoneName}"
    const val LOAD_BALANCER_ROUTE = "loadbalancer/{zoneId}?zoneName={zoneName}"
    const val HEALTHCHECK_ROUTE = "healthcheck/{zoneId}?zoneName={zoneName}"
    const val DNS_SETTINGS_ROUTE = "dnssettings/{zoneId}?zoneName={zoneName}"
    const val MANAGED_HEADERS_ROUTE = "managedheaders/{zoneId}?zoneName={zoneName}"
    const val SECURITY_INSIGHTS_ROUTE = "securityinsights/{zoneId}?zoneName={zoneName}"
    const val LB_POOLS = "lb/pools"
    const val LB_MONITORS = "lb/monitors"
    const val WORKER_ROUTE = "worker/{scriptName}"
    const val WORKER_EDIT_ROUTE = "worker_edit/{editScript}"
    const val WORKER_SECRETS_ROUTE = "worker/{scriptName}/secrets"
    const val WORKER_TRIGGERS_ROUTE = "worker/{scriptName}/triggers"
    const val WORKER_DOMAINS_ROUTE = "worker/{scriptName}/domains"
    const val WORKER_DEPLOYMENTS_ROUTE = "worker/{scriptName}/deployments"
    const val WORKER_BUILDS_ROUTE = "worker/{scriptName}/builds"
    const val TAIL_ROUTE = "tail/{scriptName}"
    // Workers Issues：全账户列表（service 为空）或限定单个 Worker；详情按 issueId
    const val WORKER_ISSUES_ROUTE = "workers/issues?service={service}"
    const val WORKER_ISSUE_ROUTE = "workers/issue/{issueId}"
    private fun zoneScoped(prefix: String, zoneId: String, zoneName: String) =
        "$prefix/$zoneId?zoneName=${Uri.encode(zoneName)}"
    fun zoneDetail(zoneId: String, zoneName: String) = zoneScoped("zone", zoneId, zoneName)
    fun dns(zoneId: String, zoneName: String) = zoneScoped("dns", zoneId, zoneName)
    fun analytics(zoneId: String, zoneName: String) = zoneScoped("analytics", zoneId, zoneName)
    fun waf(zoneId: String, zoneName: String) = zoneScoped("waf", zoneId, zoneName)
    fun snippets(zoneId: String, zoneName: String) = zoneScoped("snippets", zoneId, zoneName)
    fun zoneSettings(zoneId: String, zoneName: String) = zoneScoped("zonesettings", zoneId, zoneName)
    fun ssl(zoneId: String, zoneName: String) = zoneScoped("ssl", zoneId, zoneName)
    fun sslCerts(zoneId: String, zoneName: String) = zoneScoped("sslcerts", zoneId, zoneName)
    fun performance(zoneId: String, zoneName: String) = zoneScoped("performance", zoneId, zoneName)
    fun transform(zoneId: String, zoneName: String) = zoneScoped("transform", zoneId, zoneName)
    fun accessRules(zoneId: String, zoneName: String) = zoneScoped("accessrules", zoneId, zoneName)
    fun cache(zoneId: String, zoneName: String) = zoneScoped("cache", zoneId, zoneName)
    fun rateLimit(zoneId: String, zoneName: String) = zoneScoped("ratelimit", zoneId, zoneName)
    fun email(zoneId: String, zoneName: String) = zoneScoped("email", zoneId, zoneName)
    fun loadBalancer(zoneId: String, zoneName: String) = zoneScoped("loadbalancer", zoneId, zoneName)
    fun healthCheck(zoneId: String, zoneName: String) = zoneScoped("healthcheck", zoneId, zoneName)
    fun dnsSettings(zoneId: String, zoneName: String) = zoneScoped("dnssettings", zoneId, zoneName)
    fun managedHeaders(zoneId: String, zoneName: String) = zoneScoped("managedheaders", zoneId, zoneName)
    fun securityInsights(zoneId: String, zoneName: String) = zoneScoped("securityinsights", zoneId, zoneName)
    fun snippetEdit(zoneId: String, zoneName: String, name: String) =
        "snippetEdit/$zoneId?zoneName=${Uri.encode(zoneName)}&name=${Uri.encode(name)}"
    fun redirectItems(listId: String, listName: String): String = "redirects/$listId?listName=${Uri.encode(listName)}"
    fun pagesDetail(project: String): String = "pages/${Uri.encode(project)}"
    fun aiModel(model: String, task: String, desc: String): String =
        "dev/ai/run/${Uri.encode(model)}?task=${Uri.encode(task)}&desc=${Uri.encode(desc)}"
    fun identity(sessionId: String): String = "identity/${Uri.encode(sessionId)}"
    fun tunnelDetail(id: String, name: String): String = "tunnel/$id?tunnelName=${Uri.encode(name)}"
    fun turnstileDetail(sitekey: String): String = "turnstile/$sitekey"
    fun worker(scriptName: String): String = "worker/${Uri.encode(scriptName)}"
    fun workerEdit(scriptName: String): String = "worker_edit/${Uri.encode(scriptName)}"
    fun workerSecrets(scriptName: String): String = "worker/${Uri.encode(scriptName)}/secrets"
    fun workerTriggers(scriptName: String): String = "worker/${Uri.encode(scriptName)}/triggers"
    fun workerDomains(scriptName: String): String = "worker/${Uri.encode(scriptName)}/domains"
    fun workerDeployments(scriptName: String): String = "worker/${Uri.encode(scriptName)}/deployments"
    fun workerBuilds(scriptName: String): String = "worker/${Uri.encode(scriptName)}/builds"
    fun tail(scriptName: String): String = "tail/${Uri.encode(scriptName)}"
    fun workerIssues(service: String? = null): String =
        if (service.isNullOrBlank()) "workers/issues" else "workers/issues?service=${Uri.encode(service)}"
    fun workerIssue(issueId: String): String = "workers/issue/${Uri.encode(issueId)}"
    private fun jurisdictionQuery(jurisdiction: String?): String =
        jurisdiction?.takeIf { it.isNotBlank() }?.let { "?jurisdiction=${Uri.encode(it)}" }.orEmpty()
    fun r2Objects(bucket: String, jurisdiction: String? = null): String =
        "r2/objects/${Uri.encode(bucket)}${jurisdictionQuery(jurisdiction)}"
    fun r2Settings(bucket: String, jurisdiction: String? = null): String =
        "r2/settings/${Uri.encode(bucket)}${jurisdictionQuery(jurisdiction)}"
    fun r2Sql(bucket: String): String = "r2/sql/${Uri.encode(bucket)}"
    fun d1Query(dbId: String, dbName: String): String = "d1/query/$dbId?dbName=${Uri.encode(dbName)}"
    fun d1Table(dbId: String, table: String): String = "d1/table/$dbId?table=${Uri.encode(table)}"
    fun kvKeys(nsId: String, nsTitle: String): String = "kv/keys/$nsId?nsTitle=${Uri.encode(nsTitle)}"

    /** 路由 → 高亮的顶级标签（下钻页归属其父标签）。 */
    fun topOf(route: String?): TopDestination = when {
        route == DASHBOARD || route == TUNNELS || route?.startsWith("tunnel/") == true ||
        route == TURNSTILE || route?.startsWith("turnstile/") == true ||
            route == REDIRECTS || route?.startsWith("redirects/") == true ||
            route?.startsWith("zerotrust") == true -> TopDestination.Dashboard
        route == SETTINGS || route == STATUS || route == AUDIT || route == ALERTING || route?.startsWith("identity/") == true -> TopDestination.Settings
        route == WORKERS || route == DEV_HUB || route?.startsWith("worker/") == true || route?.startsWith("workers/") == true || route?.startsWith("tail/") == true ||
            route?.startsWith("dev/") == true || route == PAGES || route?.startsWith("pages/") == true ->
            TopDestination.Workers
        route == STORAGE || route?.startsWith("r2/") == true || route?.startsWith("d1/") == true || route?.startsWith("kv/") == true ->
            TopDestination.Storage
        else -> TopDestination.Zones
    }

    fun startRoute(dest: TopDestination): String = when (dest) {
        TopDestination.Dashboard -> DASHBOARD
        TopDestination.Zones -> ZONES
        TopDestination.Workers -> DEV_HUB
        TopDestination.Storage -> STORAGE
        TopDestination.Settings -> SETTINGS
    }
}

/** R2 桶级页面的导航参数：bucket 必填 + 可选 jurisdiction（默认区域为空串）。 */
private fun r2BucketArgs() = listOf(
    navArgument("bucket") { type = NavType.StringType },
    navArgument("jurisdiction") { type = NavType.StringType; defaultValue = "" },
)

/** zone 级页面的共享导航参数（zoneId 必填 + 可选 zoneName）。 */
private fun zoneArgs() = listOf(
    navArgument("zoneId") { type = NavType.StringType },
    navArgument("zoneName") { type = NavType.StringType; defaultValue = "" },
)

@OptIn(ExperimentalMaterial3AdaptiveNavigationSuiteApi::class)
@Composable
private fun MainScaffold(onOpenToolbox: () -> Unit) {
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route
    // 下钻页仍高亮其父标签；付费墙是覆盖在来源页上的覆盖层、不归任何标签，
    // 故按来源页（上一条回退栈）高亮，避免落到 topOf 的 else 分支误高亮「域名」。
    val selectedTop =
        if (currentRoute == Dest.PAYWALL) Dest.topOf(navController.previousBackStackEntry?.destination?.route)
        else Dest.topOf(currentRoute)

    val whatsNewViewModel: WhatsNewViewModel = hiltViewModel()
    val whatsNewRelease by whatsNewViewModel.release.collectAsStateWithLifecycle()

    // 添加账号 = 无痕重新登录（第二账号走 Pro 闸门）
    val context = LocalContext.current
    val loginViewModel: LoginViewModel = hiltViewModel()
    val gateViewModel: ProGateViewModel = hiltViewModel()
    val isPro by gateViewModel.isPro.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) {
        loginViewModel.launchAuthTab.collect { launch -> context.launchCustomTab(launch.uri, launch.ephemeral) }
    }
    val onAddAccount = {
        if (isPro) loginViewModel.login(freshLogin = true) else navController.navigate(Dest.PAYWALL)
    }

    // 域名级深入工具统一分发（ZoneTool 枚举 → 路由），新增工具只加 when 分支。
    val openZoneTool: (String, String, ZoneTool) -> Unit = { zoneId, zoneName, tool ->
        val route: String? = when (tool) {
            ZoneTool.CACHE -> Dest.cache(zoneId, zoneName)
            ZoneTool.RATE_LIMIT -> Dest.rateLimit(zoneId, zoneName)
            ZoneTool.EMAIL_ROUTING -> Dest.email(zoneId, zoneName)
            ZoneTool.LOAD_BALANCER -> Dest.loadBalancer(zoneId, zoneName)
            ZoneTool.HEALTH_CHECK -> Dest.healthCheck(zoneId, zoneName)
            ZoneTool.DNS_SETTINGS -> Dest.dnsSettings(zoneId, zoneName)
            ZoneTool.MANAGED_HEADERS -> Dest.managedHeaders(zoneId, zoneName)
            ZoneTool.SECURITY_INSIGHTS -> Dest.securityInsights(zoneId, zoneName)
        }
        route?.let { navController.navigate(it) }
    }

    // Dashboard 置顶 / 命令搜索 / 告警的统一跳转：六类资源 → 已有 Dest（不另造路由体系）。
    // title 用于 zone/D1/KV/隧道 这些「路由带展示名」的页面，取自当前目录的现查名称。
    val openResource: (DashboardResourceType, String, String) -> Unit = { type, id, title ->
        val route = when (type) {
            DashboardResourceType.ZONE -> Dest.zoneDetail(id, title)
            DashboardResourceType.WORKER -> Dest.worker(id)
            // 区域限制桶的 id 是 name@jurisdiction（见 DashboardViewModel），拆开透传
            DashboardResourceType.R2_BUCKET -> Dest.r2Objects(id.substringBefore('@'), id.substringAfter('@', "").ifEmpty { null })
            DashboardResourceType.D1_DATABASE -> Dest.d1Query(id, title)
            DashboardResourceType.KV_NAMESPACE -> Dest.kvKeys(id, title)
            DashboardResourceType.TUNNEL -> Dest.tunnelDetail(id, title)
        }
        // 存储三类的下钻页平时只能从「存储」Tab（整页 Pro 闸门）进入，
        // 这里直达会绕过闸门，故非 Pro 直接送付费墙；隧道详情路由自带 ProGate。
        val needsPro = type == DashboardResourceType.R2_BUCKET ||
            type == DashboardResourceType.D1_DATABASE ||
            type == DashboardResourceType.KV_NAMESPACE
        navController.navigate(if (needsPro && !isPro) Dest.PAYWALL else route)
    }

    NavigationSuiteScaffold(
        navigationSuiteItems = {
            TopDestination.entries.forEach { dest ->
                item(
                    selected = selectedTop == dest,
                    onClick = {
                        navController.navigate(Dest.startRoute(dest)) {
                            // 切顶级标签：弹回起点并保存/恢复各自子栈状态
                            popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                    icon = { Icon(dest.icon, contentDescription = null) },
                    label = { Text(stringResource(dest.labelRes)) },
                )
            }
        },
    ) {
        NavHost(navController = navController, startDestination = Dest.DASHBOARD) {
            composable(Dest.DASHBOARD) {
                DashboardScreen(
                    onOpenTunnels = { navController.navigate(Dest.TUNNELS) },
                    onOpenTurnstile = { navController.navigate(Dest.TURNSTILE) },
                    onOpenRegistrar = { navController.navigate(Dest.REGISTRAR) },
                    onOpenTracer = { navController.navigate(Dest.TRACER) },
                    onOpenUrlScanner = { navController.navigate(Dest.URL_SCANNER) },
                    onOpenZones = {
                        navController.navigate(Dest.ZONES) {
                            popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                    onOpenZone = { zone -> navController.navigate(Dest.zoneDetail(zone.id, zone.name)) },
                    onAddAccount = onAddAccount,
                    onOpenRedirects = { navController.navigate(Dest.REDIRECTS) },
                    onOpenZeroTrust = { navController.navigate(Dest.ZERO_TRUST) },
                    onOpenResource = openResource,
                )
            }
            composable(Dest.ZERO_TRUST) {
                ProGate {
                    ZeroTrustHubScreen(
                        onBack = { navController.popBackStack() },
                        onOpenAccess = { navController.navigate(Dest.ZT_ACCESS) },
                        onOpenGateway = { navController.navigate(Dest.ZT_GATEWAY) },
                    )
                }
            }
            composable(Dest.ZT_ACCESS) {
                AccessAppsScreen(onBack = { navController.popBackStack() })
            }
            composable(Dest.ZT_GATEWAY) {
                GatewayRulesScreen(onBack = { navController.popBackStack() })
            }
            composable(Dest.PAGES) {
                ProGate {
                    PagesListScreen(
                        onBack = { navController.popBackStack() },
                        onOpenProject = { project -> navController.navigate(Dest.pagesDetail(project)) },
                    )
                }
            }
            composable(
                route = Dest.PAGES_DETAIL_ROUTE,
                arguments = listOf(navArgument("project") { type = NavType.StringType }),
            ) {
                ProGate { PagesProjectDetailScreen(onBack = { navController.popBackStack() }) }
            }
            composable(Dest.REDIRECTS) {
                RedirectListsScreen(
                    onBack = { navController.popBackStack() },
                    onOpenList = { id, name -> navController.navigate(Dest.redirectItems(id, name)) },
                )
            }
            composable(
                route = Dest.REDIRECT_ITEMS_ROUTE,
                arguments = listOf(
                    navArgument("listId") { type = NavType.StringType },
                    navArgument("listName") { type = NavType.StringType; defaultValue = "" },
                ),
            ) {
                RedirectItemsScreen(onBack = { navController.popBackStack() })
            }
            composable(Dest.PAYWALL) {
                PaywallScreen()
            }
            composable(Dest.URL_SCANNER) {
                URLScannerScreen(onBack = { navController.popBackStack() })
            }
            composable(Dest.TRACER) {
                RequestTracerScreen(onBack = { navController.popBackStack() })
            }
            composable(Dest.REGISTRAR) {
                RegistrarScreen(onBack = { navController.popBackStack() })
            }
            composable(Dest.TUNNELS) {
                ProGate {
                    TunnelListScreen(
                        onBack = { navController.popBackStack() },
                        onOpenTunnel = { id, name -> navController.navigate(Dest.tunnelDetail(id, name)) },
                    )
                }
            }
            composable(
                route = Dest.TUNNEL_DETAIL_ROUTE,
                arguments = listOf(
                    navArgument("tunnelId") { type = NavType.StringType },
                    navArgument("tunnelName") { type = NavType.StringType; defaultValue = "" },
                ),
            ) {
                ProGate { TunnelDetailScreen(onBack = { navController.popBackStack() }) }
            }
            composable(Dest.TURNSTILE) {
                ProGate {
                    TurnstileListScreen(
                        onBack = { navController.popBackStack() },
                        onOpenWidget = { sitekey -> navController.navigate(Dest.turnstileDetail(sitekey)) },
                    )
                }
            }
            composable(
                route = Dest.TURNSTILE_DETAIL_ROUTE,
                arguments = listOf(navArgument("sitekey") { type = NavType.StringType }),
            ) {
                ProGate { TurnstileDetailScreen(onBack = { navController.popBackStack() }) }
            }
            composable(
                Dest.ZONES,
                deepLinks = listOf(navDeepLink { uriPattern = "orangecloud://open/zones" }),
            ) {
                ZonesPaneScreen(
                    onOpenDns = { id, name -> navController.navigate(Dest.dns(id, name)) },
                    onOpenAnalytics = { id, name -> navController.navigate(Dest.analytics(id, name)) },
                    onOpenWaf = { id, name -> navController.navigate(Dest.waf(id, name)) },
                    onOpenSnippets = { id, name -> navController.navigate(Dest.snippets(id, name)) },
                    onOpenSsl = { id, name -> navController.navigate(Dest.ssl(id, name)) },
                    onOpenSslCerts = { id, name -> navController.navigate(Dest.sslCerts(id, name)) },
                    onOpenTransform = { id, name -> navController.navigate(Dest.transform(id, name)) },
                    onOpenAccessRules = { id, name -> navController.navigate(Dest.accessRules(id, name)) },
                    onOpenPerformance = { id, name -> navController.navigate(Dest.performance(id, name)) },
                    onOpenSettings = { id, name -> navController.navigate(Dest.zoneSettings(id, name)) },
                    onOpenZoneTool = openZoneTool,
                )
            }
            composable(
                route = Dest.ZONE_DETAIL_ROUTE,
                arguments = zoneArgs(),
            ) { entry ->
                val zoneId = entry.arguments?.getString("zoneId").orEmpty()
                val zoneName = entry.arguments?.getString("zoneName").orEmpty()
                ZoneDetailScreen(
                    zoneId = zoneId,
                    zoneName = zoneName,
                    onBack = { navController.popBackStack() },
                    onOpenDns = { navController.navigate(Dest.dns(zoneId, zoneName)) },
                    onOpenAnalytics = { navController.navigate(Dest.analytics(zoneId, zoneName)) },
                    onOpenWaf = { navController.navigate(Dest.waf(zoneId, zoneName)) },
                    onOpenSnippets = { navController.navigate(Dest.snippets(zoneId, zoneName)) },
                    onOpenSsl = { navController.navigate(Dest.ssl(zoneId, zoneName)) },
                    onOpenSslCerts = { navController.navigate(Dest.sslCerts(zoneId, zoneName)) },
                    onOpenTransform = { navController.navigate(Dest.transform(zoneId, zoneName)) },
                    onOpenAccessRules = { navController.navigate(Dest.accessRules(zoneId, zoneName)) },
                    onOpenPerformance = { navController.navigate(Dest.performance(zoneId, zoneName)) },
                    onOpenSettings = { navController.navigate(Dest.zoneSettings(zoneId, zoneName)) },
                    onOpenZoneTool = { tool -> openZoneTool(zoneId, zoneName, tool) },
                )
            }
            composable(
                route = Dest.WAF_ROUTE,
                arguments = zoneArgs(),
            ) {
                ProGate { WafRulesScreen(onBack = { navController.popBackStack() }) }
            }
            composable(
                route = Dest.CACHE_ROUTE,
                arguments = zoneArgs(),
            ) {
                ProGate { ZoneCacheRulesScreen(onBack = { navController.popBackStack() }) }
            }
            composable(
                route = Dest.RATE_LIMIT_ROUTE,
                arguments = zoneArgs(),
            ) {
                ProGate { ZoneRateLimitScreen(onBack = { navController.popBackStack() }) }
            }
            composable(
                route = Dest.EMAIL_ROUTE,
                arguments = zoneArgs(),
            ) {
                EmailRoutingScreen(onBack = { navController.popBackStack() })
            }
            composable(
                route = Dest.HEALTHCHECK_ROUTE,
                arguments = zoneArgs(),
            ) {
                HealthCheckScreen(onBack = { navController.popBackStack() })
            }
            composable(
                route = Dest.DNS_SETTINGS_ROUTE,
                arguments = zoneArgs(),
            ) {
                DnsSettingsScreen(onBack = { navController.popBackStack() })
            }
            composable(
                route = Dest.MANAGED_HEADERS_ROUTE,
                arguments = zoneArgs(),
            ) {
                ManagedHeadersScreen(onBack = { navController.popBackStack() })
            }
            composable(
                route = Dest.SECURITY_INSIGHTS_ROUTE,
                arguments = zoneArgs(),
            ) {
                // 安全洞察全套餐可用、只读为主，不设 Pro 闸门
                SecurityInsightsScreen(onBack = { navController.popBackStack() })
            }
            composable(
                route = Dest.LOAD_BALANCER_ROUTE,
                arguments = zoneArgs(),
            ) {
                ProGate {
                    ZoneLoadBalancerScreen(
                        onBack = { navController.popBackStack() },
                        onOpenPools = { navController.navigate(Dest.LB_POOLS) },
                        onOpenMonitors = { navController.navigate(Dest.LB_MONITORS) },
                    )
                }
            }
            composable(Dest.LB_POOLS) {
                PoolListScreen(onBack = { navController.popBackStack() })
            }
            composable(Dest.LB_MONITORS) {
                MonitorListScreen(onBack = { navController.popBackStack() })
            }
            composable(
                route = Dest.SNIPPETS_ROUTE,
                arguments = zoneArgs(),
            ) { entry ->
                val zoneId = entry.arguments?.getString("zoneId").orEmpty()
                val zoneName = entry.arguments?.getString("zoneName").orEmpty()
                ProGate {
                    SnippetsListScreen(
                        onBack = { navController.popBackStack() },
                        onOpenSnippet = { name -> navController.navigate(Dest.snippetEdit(zoneId, zoneName, name)) },
                        onCreate = { navController.navigate(Dest.snippetEdit(zoneId, zoneName, "")) },
                    )
                }
            }
            composable(
                route = Dest.SNIPPET_EDIT_ROUTE,
                arguments = listOf(
                    navArgument("zoneId") { type = NavType.StringType },
                    navArgument("zoneName") { type = NavType.StringType; defaultValue = "" },
                    navArgument("name") { type = NavType.StringType; defaultValue = "" },
                ),
            ) {
                ProGate {
                    SnippetEditorScreen(
                        onBack = { navController.popBackStack() },
                        onClosed = { navController.popBackStack() },
                    )
                }
            }
            composable(
                route = Dest.ZONE_SETTINGS_ROUTE,
                arguments = zoneArgs(),
            ) {
                ZoneSettingsScreen(onBack = { navController.popBackStack() })
            }
            composable(
                route = Dest.SSL_ROUTE,
                arguments = zoneArgs(),
            ) {
                ZoneSslSettingsScreen(onBack = { navController.popBackStack() })
            }
            composable(
                route = Dest.SSL_CERTS_ROUTE,
                arguments = zoneArgs(),
            ) {
                ZoneSslCertsScreen(onBack = { navController.popBackStack() })
            }
            composable(
                route = Dest.PERFORMANCE_ROUTE,
                arguments = zoneArgs(),
            ) {
                ZonePerformanceScreen(onBack = { navController.popBackStack() })
            }
            composable(
                route = Dest.TRANSFORM_ROUTE,
                arguments = zoneArgs(),
            ) {
                ZoneTransformScreen(onBack = { navController.popBackStack() })
            }
            composable(
                route = Dest.ACCESS_RULES_ROUTE,
                arguments = zoneArgs(),
            ) {
                ZoneAccessRulesScreen(onBack = { navController.popBackStack() })
            }
            composable(
                route = Dest.DNS_ROUTE,
                arguments = zoneArgs(),
                deepLinks = listOf(
                    navDeepLink { uriPattern = "orangecloud://zone/{zoneId}/dns?zoneName={zoneName}" },
                ),
            ) {
                DnsListScreen(onBack = { navController.popBackStack() })
            }
            composable(
                route = Dest.ANALYTICS_ROUTE,
                arguments = zoneArgs(),
            ) {
                ZoneAnalyticsScreen(
                    onBack = { navController.popBackStack() },
                    onShowPaywall = { navController.navigate(Dest.PAYWALL) },
                )
            }
            composable(Dest.DEV_HUB) {
                DeveloperHubScreen(
                    onOpenWorkers = { navController.navigate(Dest.WORKERS) },
                    onOpenWorkersAI = { navController.navigate(Dest.DEV_WORKERS_AI) },
                    onOpenAIGateway = { navController.navigate(Dest.DEV_AI_GATEWAY) },
                    onOpenQueues = { navController.navigate(Dest.DEV_QUEUES) },
                    onOpenHyperdrive = { navController.navigate(Dest.DEV_HYPERDRIVE) },
                    onOpenDurableObjects = { navController.navigate(Dest.DEV_DO) },
                    onOpenPages = { navController.navigate(Dest.PAGES) },
                    onOpenAssistant = { navController.navigate(Dest.DEV_ASSISTANT) },
                )
            }
            composable(Dest.DEV_ASSISTANT) {
                AssistantScreen(onBack = { navController.popBackStack() })
            }
            composable(
                Dest.WORKERS,
                deepLinks = listOf(navDeepLink { uriPattern = "orangecloud://open/workers" }),
            ) {
                WorkerListScreen(
                    onWorkerClick = { name -> navController.navigate(Dest.worker(name)) },
                    onCreate = { navController.navigate(Dest.WORKER_CREATE) },
                    onOpenIssues = { navController.navigate(Dest.workerIssues()) },
                )
            }
            composable(Dest.WORKER_CREATE) {
                // 新建 Worker 进 Pro（查看免费）
                ProGate {
                    WorkerCreateScreen(
                        onBack = { navController.popBackStack() },
                        onCreated = { navController.popBackStack() },
                    )
                }
            }
            composable(
                route = Dest.WORKER_EDIT_ROUTE,
                arguments = listOf(navArgument("editScript") { type = NavType.StringType }),
            ) {
                // 编辑代码进 Pro（查看免费）
                ProGate {
                    WorkerCreateScreen(
                        onBack = { navController.popBackStack() },
                        onCreated = { navController.popBackStack() },
                    )
                }
            }
            composable(Dest.DEV_WORKERS_AI) {
                ProGate {
                    WorkersAIScreen(
                        onBack = { navController.popBackStack() },
                        onOpenModel = { m -> navController.navigate(Dest.aiModel(m.name ?: m.id, m.taskName, m.description.orEmpty())) },
                    )
                }
            }
            composable(
                route = Dest.AI_RUN_ROUTE,
                arguments = listOf(
                    navArgument("model") { type = NavType.StringType },
                    navArgument("task") { type = NavType.StringType; defaultValue = "" },
                    navArgument("desc") { type = NavType.StringType; defaultValue = "" },
                ),
            ) {
                ProGate { AIRunScreen(onBack = { navController.popBackStack() }) }
            }
            composable(Dest.DEV_AI_GATEWAY) {
                ProGate { AIGatewayScreen(onBack = { navController.popBackStack() }) }
            }
            composable(Dest.DEV_QUEUES) {
                ProGate { QueuesScreen(onBack = { navController.popBackStack() }) }
            }
            composable(Dest.DEV_HYPERDRIVE) {
                ProGate { HyperdriveScreen(onBack = { navController.popBackStack() }) }
            }
            composable(Dest.DEV_DO) {
                ProGate { DurableObjectsScreen(onBack = { navController.popBackStack() }) }
            }
            composable(
                route = Dest.WORKER_ROUTE,
                arguments = listOf(navArgument("scriptName") { type = NavType.StringType }),
                deepLinks = listOf(
                    navDeepLink { uriPattern = "orangecloud://worker/{scriptName}" },
                ),
            ) { entry ->
                val scriptName = entry.arguments?.getString("scriptName").orEmpty()
                WorkerDetailScreen(
                    onBack = { navController.popBackStack() },
                    onOpenTail = { navController.navigate(Dest.tail(scriptName)) },
                    onOpenSecrets = { navController.navigate(Dest.workerSecrets(scriptName)) },
                    onOpenTriggers = { navController.navigate(Dest.workerTriggers(scriptName)) },
                    onOpenDomains = { navController.navigate(Dest.workerDomains(scriptName)) },
                    onOpenDeployments = { navController.navigate(Dest.workerDeployments(scriptName)) },
                    onOpenBuilds = { navController.navigate(Dest.workerBuilds(scriptName)) },
                    onOpenIssues = { navController.navigate(Dest.workerIssues(scriptName)) },
                    onEditCode = { navController.navigate(Dest.workerEdit(scriptName)) },
                    // 查看详情免费；删除按 isPro 拦到付费墙（编辑/新建走各自路由的 ProGate）
                    isPro = isPro,
                    onShowPaywall = { navController.navigate(Dest.PAYWALL) },
                )
            }
            composable(
                route = Dest.WORKER_SECRETS_ROUTE,
                arguments = listOf(navArgument("scriptName") { type = NavType.StringType }),
            ) {
                ProGate { WorkerSecretsScreen(onBack = { navController.popBackStack() }) }
            }
            composable(
                route = Dest.WORKER_TRIGGERS_ROUTE,
                arguments = listOf(navArgument("scriptName") { type = NavType.StringType }),
            ) {
                ProGate { WorkerTriggersScreen(onBack = { navController.popBackStack() }) }
            }
            composable(
                route = Dest.WORKER_DOMAINS_ROUTE,
                arguments = listOf(navArgument("scriptName") { type = NavType.StringType }),
            ) {
                ProGate { WorkerRoutesScreen(onBack = { navController.popBackStack() }) }
            }
            composable(
                route = Dest.WORKER_DEPLOYMENTS_ROUTE,
                arguments = listOf(navArgument("scriptName") { type = NavType.StringType }),
            ) {
                ProGate { WorkerDeploymentsScreen(onBack = { navController.popBackStack() }) }
            }
            composable(
                route = Dest.WORKER_BUILDS_ROUTE,
                arguments = listOf(navArgument("scriptName") { type = NavType.StringType }),
            ) {
                WorkerBuildsScreen(onBack = { navController.popBackStack() })
            }
            composable(
                route = Dest.TAIL_ROUTE,
                arguments = listOf(navArgument("scriptName") { type = NavType.StringType }),
            ) {
                ProGate { WorkerTailScreen(onBack = { navController.popBackStack() }) }
            }
            // Workers Issues 与实时日志同属 Worker 可观测性，沿用同一个 Pro 闸门
            composable(
                route = Dest.WORKER_ISSUES_ROUTE,
                arguments = listOf(navArgument("service") { type = NavType.StringType; defaultValue = "" }),
            ) {
                ProGate {
                    WorkerIssuesScreen(
                        onBack = { navController.popBackStack() },
                        onOpenIssue = { id -> navController.navigate(Dest.workerIssue(id)) },
                    )
                }
            }
            composable(
                route = Dest.WORKER_ISSUE_ROUTE,
                arguments = listOf(navArgument("issueId") { type = NavType.StringType }),
            ) {
                ProGate { WorkerIssueDetailScreen(onBack = { navController.popBackStack() }) }
            }
            composable(
                Dest.STORAGE,
                deepLinks = listOf(navDeepLink { uriPattern = "orangecloud://open/storage" }),
            ) {
                ProGate {
                    StorageHubScreen(
                        onOpenR2 = { navController.navigate(Dest.R2_BUCKETS) },
                        onOpenD1 = { navController.navigate(Dest.D1_DATABASES) },
                        onOpenKV = { navController.navigate(Dest.KV_NAMESPACES) },
                    )
                }
            }
            composable(Dest.R2_BUCKETS) {
                R2BucketListScreen(
                    onBack = { navController.popBackStack() },
                    onOpenBucket = { name, jurisdiction -> navController.navigate(Dest.r2Objects(name, jurisdiction)) },
                )
            }
            composable(
                route = Dest.R2_OBJECTS_ROUTE,
                arguments = r2BucketArgs(),
            ) { entry ->
                val bucket = entry.arguments?.getString("bucket").orEmpty()
                val jurisdiction = entry.arguments?.getString("jurisdiction")
                R2ObjectListScreen(
                    onBack = { navController.popBackStack() },
                    onOpenSettings = { navController.navigate(Dest.r2Settings(bucket, jurisdiction)) },
                )
            }
            composable(
                route = Dest.R2_BUCKET_SETTINGS_ROUTE,
                arguments = r2BucketArgs(),
            ) {
                R2BucketSettingsScreen(
                    onBack = { navController.popBackStack() },
                    onOpenSql = { bucket -> navController.navigate(Dest.r2Sql(bucket)) },
                )
            }
            composable(
                route = Dest.R2_SQL_ROUTE,
                arguments = listOf(navArgument("bucket") { type = NavType.StringType }),
            ) {
                R2SqlQueryScreen(onBack = { navController.popBackStack() })
            }
            composable(Dest.D1_DATABASES) {
                D1DatabaseListScreen(
                    onBack = { navController.popBackStack() },
                    onOpenDatabase = { id, name -> navController.navigate(Dest.d1Query(id, name)) },
                )
            }
            composable(
                route = Dest.D1_QUERY_ROUTE,
                arguments = listOf(
                    navArgument("dbId") { type = NavType.StringType },
                    navArgument("dbName") { type = NavType.StringType; defaultValue = "" },
                ),
            ) { entry ->
                val dbId = entry.arguments?.getString("dbId").orEmpty()
                D1QueryScreen(
                    onBack = { navController.popBackStack() },
                    onOpenTable = { table -> navController.navigate(Dest.d1Table(dbId, table)) },
                )
            }
            composable(
                route = Dest.D1_TABLE_ROUTE,
                arguments = listOf(
                    navArgument("dbId") { type = NavType.StringType },
                    navArgument("table") { type = NavType.StringType; defaultValue = "" },
                ),
            ) {
                D1TableScreen(onBack = { navController.popBackStack() })
            }
            composable(Dest.KV_NAMESPACES) {
                KVNamespaceListScreen(
                    onBack = { navController.popBackStack() },
                    onOpenNamespace = { id, title -> navController.navigate(Dest.kvKeys(id, title)) },
                )
            }
            composable(
                route = Dest.KV_KEYS_ROUTE,
                arguments = listOf(
                    navArgument("nsId") { type = NavType.StringType },
                    navArgument("nsTitle") { type = NavType.StringType; defaultValue = "" },
                ),
            ) {
                KVKeyListScreen(onBack = { navController.popBackStack() })
            }
            composable(Dest.SETTINGS) {
                SettingsScreen(
                    onOpenStatus = { navController.navigate(Dest.STATUS) },
                    onOpenIdentity = { sessionId -> navController.navigate(Dest.identity(sessionId)) },
                    onAddAccount = onAddAccount,
                    onOpenPaywall = { navController.navigate(Dest.PAYWALL) },
                    onOpenAudit = { navController.navigate(Dest.AUDIT) },
                    onOpenToolbox = onOpenToolbox,
                    onOpenAlerting = { navController.navigate(Dest.ALERTING) },
                )
            }
            composable(
                route = Dest.IDENTITY_ROUTE,
                arguments = listOf(navArgument("sessionId") { type = NavType.StringType }),
            ) { entry ->
                val sessionId = entry.arguments?.getString("sessionId").orEmpty()
                IdentityDetailScreen(
                    sessionId = sessionId,
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Dest.STATUS) {
                StatusScreen(onBack = { navController.popBackStack() })
            }
            composable(Dest.AUDIT) {
                AuditLogScreen(onBack = { navController.popBackStack() })
            }
            composable(Dest.ALERTING) {
                CFAlertingScreen(onBack = { navController.popBackStack() })
            }
        }
    }

    whatsNewRelease?.let { WhatsNewDialog(it, whatsNewViewModel::dismiss) }
}

@Composable
private fun SplashScreen() {
    val isDark = jiamin.chen.orangecloud.core.design.theme.LocalIsDark.current
    val phase = remember(isDark) { SkyPhase.current(isDark, LocalTime.now().hour) }
    SkyBackground(phase = phase) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(
                color = if (phase.isDark) Color.White else MaterialTheme.colorScheme.primary,
            )
        }
    }
}
