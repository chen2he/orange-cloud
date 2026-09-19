package jiamin.chen.orangecloud.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.AuthSessionMeta
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.core.network.ApiError
import jiamin.chen.orangecloud.core.system.AppPrefs
import jiamin.chen.orangecloud.core.system.UsagePlanPrefs
import jiamin.chen.orangecloud.data.model.Account
import jiamin.chen.orangecloud.data.model.AccountUsage
import jiamin.chen.orangecloud.data.model.AnalyticsTimeRange
import jiamin.chen.orangecloud.data.model.BillingCycle
import jiamin.chen.orangecloud.data.model.Tunnel
import jiamin.chen.orangecloud.data.model.Zone
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import jiamin.chen.orangecloud.data.repository.AccountStore
import jiamin.chen.orangecloud.data.repository.AnalyticsRepository
import jiamin.chen.orangecloud.data.repository.SecurityRepository
import jiamin.chen.orangecloud.data.repository.StorageRepository
import jiamin.chen.orangecloud.data.repository.WorkerRepository
import jiamin.chen.orangecloud.data.repository.ZoneRepository
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import androidx.glance.appwidget.updateAll
import jiamin.chen.orangecloud.core.widget.OrangeCloudWidget
import jiamin.chen.orangecloud.core.widget.WidgetSnapshot
import jiamin.chen.orangecloud.core.widget.WidgetSnapshotStore
import javax.inject.Inject
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

data class DashboardUiState(
    val accounts: List<Account> = emptyList(),
    val selectedAccountId: String? = null,
    val accountName: String = "",
    val accountEmail: String = "",
    val zoneCount: String = "—",
    val workerCount: String = "—",
    val bucketCount: String = "—",
    val requestsToday: String = "—",
    val recentZones: List<Zone> = emptyList(),
    val isLoading: Boolean = false,
    val authSessions: List<AuthSessionMeta> = emptyList(),
    val currentAuthSessionId: String? = null,
    // 用量模块
    val usage: AccountUsage? = null,
    val usagePlan: UsagePlanPrefs = UsagePlanPrefs(),
    val usageLoading: Boolean = false,
    val usageLoadFailed: Boolean = false,
    val accountAnalyticsUnavailable: Boolean = false,
    /** 账户级数据只有部分时间窗被 authz 挡（今日有数、本周期没有）：用量照常显示，只加一条温和提示 */
    val accountAnalyticsPartial: Boolean = false,
    val hasAccountAnalytics: Boolean = false,
    // 三合一 hub：跨类型资源目录 / 置顶 / 告警
    val resources: List<DashboardResource> = emptyList(),
    val pinned: List<DashboardResource> = emptyList(),
    val catalogLoading: Boolean = false,
    val alerts: List<DashboardAlert> = emptyList(),
)

@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel
class DashboardViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val accountStore: AccountStore,
    private val authRepository: AuthRepository,
    private val zoneRepository: ZoneRepository,
    private val workerRepository: WorkerRepository,
    private val storageRepository: StorageRepository,
    private val analyticsRepository: AnalyticsRepository,
    private val securityRepository: SecurityRepository,
    private val appPrefs: AppPrefs,
) : ViewModel() {

    private val _uiState = MutableStateFlow(DashboardUiState(isLoading = true))
    val uiState: StateFlow<DashboardUiState> = _uiState.asStateFlow()

    // 跨类型资源目录：按类型分桶，各来源独立回填后统一 publish（缺 scope 的类型直接缺席）
    private val catalog = mutableMapOf<DashboardResourceType, List<DashboardResource>>()
    private var pinnedKeys: List<String> = emptyList()
    private var catalogJob: Job? = null
    private var catalogLoadedFor: String? = null
    // 告警输入：null = 未加载（不产生告警），避免冷启动空缓存误报
    private var alertZones: List<Zone> = emptyList()
    private var alertTunnels: List<Tunnel>? = null
    private var alertWorkerCount: Int? = null

    // 用量：账号级会话缓存（切回同账号即时回显）+ 加载/不可用惰性标记
    private val usageCache = mutableMapOf<String, AccountUsage>()
    private var usageLoadedForAccount: String? = null
    private var analyticsUnavailableForAccount: String? = null
    private var usageJob: Job? = null

    init {
        viewModelScope.launch {
            accountStore.accounts.collect { list -> _uiState.update { it.copy(accounts = list) } }
        }
        viewModelScope.launch {
            accountStore.selectedAccountId.collect { id ->
                // 切账号时清掉上一个账号的用量快照与网络补拉来的资源，避免旧数据在新账号加载期间残留。
                // 域名 / Worker 两桶不在这里清——它们由各自的 flatMapLatest 随账号切流覆写，
                // 这里清会和那两个协程抢先后（清晚了反而把新账号刚落的数据抹掉）。
                catalogLoadedFor = null
                alertTunnels = null
                alertWorkerCount = null
                catalog.remove(DashboardResourceType.R2_BUCKET)
                catalog.remove(DashboardResourceType.D1_DATABASE)
                catalog.remove(DashboardResourceType.KV_NAMESPACE)
                catalog.remove(DashboardResourceType.TUNNEL)
                publishCatalog()
                _uiState.update {
                    it.copy(
                        selectedAccountId = id,
                        usage = null,
                        usageLoadFailed = false,
                        accountAnalyticsUnavailable = false,
                    )
                }
            }
        }
        // 登录身份列表 / 当前身份：头像菜单「登录身份」段的数据源
        viewModelScope.launch {
            authRepository.state.collect { auth ->
                _uiState.update {
                    it.copy(authSessions = auth.sessions, currentAuthSessionId = auth.currentSessionId)
                }
            }
        }
        // 身份切换后整页重刷（AccountStore 已重置账号作用域）；只认 id 变化，label 重命名等不触发
        viewModelScope.launch {
            authRepository.state
                .filter { it.isReady }
                .map { it.currentSessionId }
                .distinctUntilChanged()
                .drop(1)
                .collect { if (it != null) refresh() }
        }
        // 域名计数 / 最近访问：持续观察 Room 缓存（切账号自动切流）。
        // refreshZones 写入缓存后这里会自动更新——修复冷启动一次性读空缓存恒显 0 的问题。
        viewModelScope.launch {
            accountStore.selectedAccountId
                .flatMapLatest { id -> if (id == null) flowOf(emptyList()) else zoneRepository.observeZones(id) }
                .collect { zones ->
                    _uiState.update { it.copy(zoneCount = zones.size.toString(), recentZones = zones.take(4)) }
                    alertZones = zones
                    catalog[DashboardResourceType.ZONE] = zones.map { zone ->
                        DashboardResource(DashboardResourceType.ZONE, zone.id, zone.name, zone.plan?.name ?: zone.status)
                    }
                    publishCatalog()
                }
        }
        // Worker 目录：同样观察 Room 缓存（refresh 里的 refreshWorkers 写入后自动反映）。
        viewModelScope.launch {
            accountStore.selectedAccountId
                .flatMapLatest { id -> if (id == null) flowOf(emptyList()) else workerRepository.observeWorkers(id) }
                .collect { workers ->
                    catalog[DashboardResourceType.WORKER] = workers.map { w ->
                        DashboardResource(DashboardResourceType.WORKER, w.id, w.id, w.usageModel)
                    }
                    // 冷启动空缓存不能算「没有 Worker」，只有网络刷新过一次才让它参与告警
                    if (alertWorkerCount != null || workers.isNotEmpty()) alertWorkerCount = workers.size
                    publishCatalog()
                }
        }
        // 置顶键集合：随账号切流（多账号隔离），只存 type|id，标题在 publishCatalog 里现查
        viewModelScope.launch {
            accountStore.selectedAccountId
                .flatMapLatest { id -> if (id == null) flowOf(emptySet()) else appPrefs.pinnedResources(id) }
                .collect { keys ->
                    pinnedKeys = keys.toList()
                    publishCatalog()
                }
        }
        // 用量套餐设置：随账号切流，仅驱动菜单显示（改动由 setter 主动触发重载，避免切账号双刷）。
        viewModelScope.launch {
            accountStore.selectedAccountId
                .flatMapLatest { id -> if (id == null) flowOf(UsagePlanPrefs()) else appPrefs.usagePlan(id) }
                .collect { plan -> _uiState.update { it.copy(usagePlan = plan) } }
        }
        // 桌面小组件快照：账号总览（账号名 / 今日请求 / 域名数）变化即写入并刷新 Glance。
        viewModelScope.launch {
            uiState
                .map { Triple(it.accountName, it.requestsToday, it.zoneCount) }
                .distinctUntilChanged()
                .collect { (name, requests, zones) ->
                    WidgetSnapshotStore.write(context, WidgetSnapshot(name, requests, zones))
                    runCatching { OrangeCloudWidget().updateAll(context) }
                }
        }
        refresh()
    }

    fun selectAccount(accountId: String) {
        accountStore.select(accountId)
        refresh()
    }

    /** 切换登录身份（头像菜单「登录身份」段）；账号作用域重置与重刷由观察者链完成 */
    fun switchAuthSession(sessionId: String) {
        authRepository.switchSession(sessionId)
    }

    fun refresh() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            try {
                accountStore.ensureLoaded()
                val accountId = accountStore.selectedAccountId.value
                val account = accountStore.selectedAccount
                val email = authRepository.state.value.currentSession?.label.orEmpty()
                _uiState.update {
                    it.copy(accountName = account?.name.orEmpty(), accountEmail = email)
                }
                if (accountId == null) {
                    _uiState.update { it.copy(isLoading = false) }
                    return@launch
                }

                // 先网络刷新域名缓存（zoneCount / recentZones 由 init 的持续观察自动反映）。
                // 放在读取派生数据之前，确保今日请求量基于最新域名集计算，而非冷启动的空缓存。
                runCatching { zoneRepository.refreshZones(accountId) }
                val zones = zoneRepository.observeZones(accountId).first()

                // 各项计数独立 best-effort（缺 scope / 出错不互相拖累）
                val workers = async { runCatching { workerRepository.refreshWorkers(accountId) }.getOrNull() }
                val buckets = async {
                    if (authRepository.hasScope(Scopes.R2_READ)) {
                        runCatching { storageRepository.listBuckets(accountId).size }.getOrNull()
                    } else null
                }
                val requests = async { sumRequests(zones) }

                workers.await()
                val workerList = workerRepository.observeWorkers(accountId).first()
                alertWorkerCount = workerList.size   // 网络刷新过一次才让「无 Worker」参与告警
                _uiState.update { it.copy(workerCount = workerList.size.toString()) }
                publishCatalog()
                buckets.await()?.let { count -> _uiState.update { st -> st.copy(bucketCount = count.toString()) } }
                requests.await()?.let { req -> _uiState.update { st -> st.copy(requestsToday = req) } }
            } catch (e: Exception) {
                // 顶层失败不致命，保留已有数据
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
        }
        loadUsage()
        ensureCatalog(force = true)
    }

    // MARK: - 跨类型资源目录（置顶 / 命令搜索 / 告警共用）

    /**
     * 补拉 R2 / D1 / KV / 隧道四类资源。
     *
     * 时机：**不参与首屏关键路径**。域名与 Worker 走 Room 缓存观察（零额外网络，首屏即有），
     * 这四类需要各自一次 REST 往返，因此放进独立协程、先让出 300ms 给首屏的域名刷新与分析请求，
     * 回来后合并进目录。搜索表打开时也会调一次（若首次补拉失败/尚未跑，这里兜底重试）。
     * 缺 scope 的类型直接跳过（不报错、目录里缺席），单类失败也不拖累其它类。
     */
    fun ensureCatalog(force: Boolean = false) {
        val loadedFor = catalogLoadedFor
        if (!force && loadedFor != null && loadedFor == accountStore.selectedAccountId.value) return
        catalogJob?.cancel()
        catalogJob = viewModelScope.launch {
            accountStore.ensureLoaded()
            val accountId = accountStore.selectedAccountId.value ?: return@launch
            delay(CATALOG_DEFER_MS)
            _uiState.update { it.copy(catalogLoading = true) }
            try {
                val buckets = async {
                    if (authRepository.hasScope(Scopes.R2_READ)) {
                        runCatching { storageRepository.listBuckets(accountId) }.getOrNull()
                    } else null
                }
                val databases = async {
                    if (authRepository.hasScope(Scopes.D1_READ)) {
                        runCatching { storageRepository.listDatabases(accountId) }.getOrNull()
                    } else null
                }
                val namespaces = async {
                    if (authRepository.hasScope(Scopes.KV_READ)) {
                        runCatching { storageRepository.listNamespaces(accountId) }.getOrNull()
                    } else null
                }
                val tunnels = async {
                    if (authRepository.hasScope(Scopes.TUNNEL_READ)) {
                        runCatching { securityRepository.listTunnels(accountId) }.getOrNull()
                    } else null
                }

                buckets.await()?.let { list ->
                    catalog[DashboardResourceType.R2_BUCKET] = list.map {
                        DashboardResource(DashboardResourceType.R2_BUCKET, it.name, it.name, it.location)
                    }
                }
                databases.await()?.let { list ->
                    catalog[DashboardResourceType.D1_DATABASE] = list.map {
                        DashboardResource(DashboardResourceType.D1_DATABASE, it.uuid, it.name, it.version)
                    }
                }
                namespaces.await()?.let { list ->
                    catalog[DashboardResourceType.KV_NAMESPACE] = list.map {
                        DashboardResource(DashboardResourceType.KV_NAMESPACE, it.id, it.title, null)
                    }
                }
                tunnels.await()?.let { list ->
                    alertTunnels = list
                    catalog[DashboardResourceType.TUNNEL] = list.map {
                        DashboardResource(DashboardResourceType.TUNNEL, it.id, it.name, it.status)
                    }
                }
                catalogLoadedFor = accountId
                publishCatalog()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // 目录是增强能力，整体失败也不打扰用户
            } finally {
                _uiState.update { it.copy(catalogLoading = false) }
            }
        }
    }

    /** 置顶 / 取消置顶（按当前账号存，只写 type|id）。 */
    fun togglePin(resource: DashboardResource) {
        val accountId = accountStore.selectedAccountId.value ?: return
        viewModelScope.launch { appPrefs.togglePinnedResource(accountId, resource.pinKey) }
    }

    /** 合并各类型资源 → 排序目录 → 解析置顶条目 → 重算告警，一次性推给 UI。 */
    private fun publishCatalog() {
        val all = DashboardResourceType.entries.flatMap { type ->
            catalog[type].orEmpty().sortedBy { it.title.lowercase() }
        }
        val byKey = all.associateBy { it.pinKey }
        val pinned = pinnedKeys
            .mapNotNull { key -> byKey[key] ?: decodePinKey(key) }   // 查不到就用 id 兜底占位，仍可取消置顶
            .sortedWith(compareBy<DashboardResource> { it.type.ordinal }.thenBy { it.title.lowercase() })
        val alerts = buildAlerts(AlertInput(zones = alertZones, tunnels = alertTunnels, workerCount = alertWorkerCount))
        _uiState.update { it.copy(resources = all, pinned = pinned, alerts = alerts) }
    }

    // MARK: - 用量模块

    /**
     * 加载账号用量：Workers 主查询（authz = 整账号无账户级数据权限即降级停发其余），
     * R2 / CPU / D1 / KV 独立合并，能显示多少显示多少（对齐 iOS performLoadUsage）。
     */
    fun loadUsage(force: Boolean = false) {
        usageJob?.cancel()
        usageJob = viewModelScope.launch {
            // 冷启动竞态修复：refresh() 同步调进来时账号索引可能还没从磁盘加载完，
            // selectedAccountId 为 null 曾直接 return → hasAccountAnalytics 停在默认 false，
            // 锁卡「需要流量分析权限」常驻（真机实证：scope 授权齐全仍被误挡）。
            // 先 ensureLoaded 再取账号，门控判定与加载全部进协程。
            accountStore.ensureLoaded()
            val accountId = accountStore.selectedAccountId.value ?: return@launch
            val hasScope = authRepository.hasScope(Scopes.ACCOUNT_ANALYTICS_READ)
            _uiState.update { it.copy(hasAccountAnalytics = hasScope) }
            if (!hasScope) return@launch

            usageCache[accountId]?.let { cached ->
                if (_uiState.value.usage == null) _uiState.update { it.copy(usage = cached) }
            }
            if (!force && usageLoadedForAccount == accountId) return@launch
            if (!force && analyticsUnavailableForAccount == accountId) {
                _uiState.update { it.copy(accountAnalyticsUnavailable = true, accountAnalyticsPartial = false, usageLoading = false) }
                return@launch
            }

            _uiState.update { it.copy(usageLoading = true, usageLoadFailed = false, accountAnalyticsUnavailable = false) }
            // 内存无缓存时先从磁盘回显上次快照，网络回来再覆盖（对齐 iOS UsageCache 落盘）
            if (usageCache[accountId] == null) {
                appPrefs.loadUsageCache(accountId)?.let { disk ->
                    usageCache[accountId] = disk
                    if (_uiState.value.usage == null) _uiState.update { it.copy(usage = disk) }
                }
            }
            val plan = appPrefs.usagePlan(accountId).first()
            val periodStart = if (plan.workersPaid || plan.billingDay != 1) BillingCycle.periodStart(plan.billingDay) else null

            // authz 且信封里连数据都没有 = 整账号无账户级数据权限 → 降级并停发其余账户级查询；
            // 只挡住部分时间窗时 CF 照常回已授权字段，客户端把它连同 partialAuthz 一起给回来，
            // 那种情况不降级，照常显示并在用量上方加一条提示。
            val workersResult = try {
                analyticsRepository.accountWorkersUsage(accountId, periodStart)
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiError.Cloudflare) {
                if (isAuthz(e)) {
                    analyticsUnavailableForAccount = accountId
                    _uiState.update {
                        it.copy(
                            accountAnalyticsUnavailable = true, accountAnalyticsPartial = false,
                            usage = null, usageLoading = false, usageLoadFailed = false,
                        )
                    }
                    return@launch
                }
                null
            } catch (e: Exception) {
                null
            }
            analyticsUnavailableForAccount = null
            val workers = workersResult?.usage
            val partialAuthz = workersResult?.partialAuthz == true

            var usage = workers ?: AccountUsage()
            var anyData = workers != null

            runCatching { analyticsRepository.accountR2Usage(accountId, periodStart) }.getOrNull()?.let { r2 ->
                usage = usage.copy(
                    r2ClassAMonth = r2.classA, r2ClassBMonth = r2.classB,
                    r2StorageBytes = r2.storageBytes, r2ObjectCount = r2.objectCount,
                )
                anyData = true
            }
            runCatching { analyticsRepository.workersCpuTotals(accountId, periodStart) }.getOrNull()?.let { (month, today) ->
                usage = usage.copy(cpuTimeMonthUs = month, cpuTimeTodayUs = today)
            }
            runCatching { analyticsRepository.d1Usage(accountId, periodStart) }.getOrNull()?.let { d1 ->
                usage = usage.copy(d1Usage = d1); anyData = true
            }
            if (authRepository.hasScope(Scopes.D1_READ)) {
                runCatching { storageRepository.listDatabases(accountId) }.getOrNull()?.let { dbs ->
                    usage = usage.copy(d1StorageBytes = dbs.sumOf { it.fileSize ?: 0L }); anyData = true
                }
            }
            runCatching { analyticsRepository.kvUsage(accountId, periodStart) }.getOrNull()?.let { kv ->
                usage = usage.copy(kvUsage = kv); anyData = true
            }
            runCatching { analyticsRepository.kvStorageBytes(accountId) }.getOrNull()?.let { bytes ->
                usage = usage.copy(kvStorageBytes = bytes); anyData = true
            }

            if (anyData) {
                usageCache[accountId] = usage
                usageLoadedForAccount = accountId
                appPrefs.saveUsageCache(accountId, usage)   // 落盘供下次冷启动/切回即时回显
                _uiState.update {
                    it.copy(
                        usage = usage, usageLoading = false, usageLoadFailed = false,
                        accountAnalyticsUnavailable = false, accountAnalyticsPartial = partialAuthz,
                    )
                }
            } else {
                _uiState.update { it.copy(usageLoading = false, usageLoadFailed = true) }
            }
        }
    }

    fun setUsageWorkersPaid(paid: Boolean) {
        val id = accountStore.selectedAccountId.value ?: return
        viewModelScope.launch { appPrefs.setUsageWorkersPaid(id, paid); loadUsage(force = true) }
    }

    fun setUsageR2Paid(paid: Boolean) {
        val id = accountStore.selectedAccountId.value ?: return
        viewModelScope.launch { appPrefs.setUsageR2Paid(id, paid); loadUsage(force = true) }
    }

    fun setUsageBillingDay(day: Int) {
        val id = accountStore.selectedAccountId.value ?: return
        viewModelScope.launch { appPrefs.setUsageBillingDay(id, day); loadUsage(force = true) }
    }

    /** GraphQL 账户级 authz 错误识别（免费账号账户级数据集常被 authz 挡）。 */
    private fun isAuthz(e: ApiError.Cloudflare): Boolean {
        val msg = e.errors.joinToString(" ") { it.message }.lowercase()
        return "authz" in msg || "not authorized" in msg || "unauthorized" in msg ||
            "permission" in msg || "authentication" in msg
    }

    /** 今日请求总数 = 各域名 24h 请求之和（best-effort，缺 analytics scope 返回 null）。 */
    private suspend fun sumRequests(zones: List<Zone>): String? {
        if (!authRepository.hasScope(Scopes.ANALYTICS_READ) || zones.isEmpty()) return null
        return try {
            // 以前 12 个域名串行各查一次 GraphQL，每次几百毫秒，「今日请求」要等好几秒才出现；并发发出
            val total = coroutineScope {
                zones.take(12).map { zone ->
                    async {
                        runCatching { analyticsRepository.zoneTraffic(zone.id, AnalyticsTimeRange.LAST_24H) }
                            .getOrElse { if (it is CancellationException) throw it; null }
                            ?.sumOf { it.requests.toLong() } ?: 0L
                    }
                }.awaitAll().sum()
            }
            formatCount(total)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            null
        }
    }

    private fun formatCount(n: Long): String = when {
        n >= 1_000_000 -> "%.2fM".format(n / 1_000_000.0)
        n >= 1_000 -> "%.1fK".format(n / 1_000.0)
        else -> n.toString()
    }

    private companion object {
        /** 目录补拉让出首屏的时间：够首屏的域名刷新/分析请求先抢占连接。 */
        const val CATALOG_DEFER_MS = 300L
    }
}
