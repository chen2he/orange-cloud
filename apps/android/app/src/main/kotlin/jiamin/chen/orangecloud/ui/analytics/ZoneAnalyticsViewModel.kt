package jiamin.chen.orangecloud.ui.analytics

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.data.model.AdaptiveDatasetSetting
import jiamin.chen.orangecloud.data.model.AdaptiveZoneSettings
import jiamin.chen.orangecloud.data.model.AnalyticsTimeRange
import jiamin.chen.orangecloud.data.model.SecurityEvents
import jiamin.chen.orangecloud.data.model.TrafficDetails
import jiamin.chen.orangecloud.data.model.adaptiveWindow
import kotlinx.coroutines.async
import java.time.Instant
import jiamin.chen.orangecloud.data.model.TrafficDataPoint
import jiamin.chen.orangecloud.data.repository.AnalyticsRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive

/** 流量汇总（图表下方的概览卡）。 */
data class TrafficSummary(
    val requests: Long,
    val bytes: Long,
    val uniques: Long,
    val cachedRequests: Long,
    val threats: Long,
) {
    /** 缓存命中率 0..1。 */
    val cacheHitRate: Double get() = if (requests > 0) cachedRequests.toDouble() / requests else 0.0
}

/**
 * adaptive 明细段的状态：加载中 / 可用（clamped = 受数据集保留期或最长跨度限制，范围已缩短）/
 * 不可用（数据集未开放、无权限或查询失败 → 整段换成一句说明）。
 */
sealed interface AdaptiveSection<out T> {
    data object Loading : AdaptiveSection<Nothing>
    data object Unavailable : AdaptiveSection<Nothing>
    data class Ready<T>(val data: T, val clamped: Boolean) : AdaptiveSection<T>
}

data class ZoneAnalyticsUiState(
    val zoneName: String = "",
    val range: AnalyticsTimeRange = AnalyticsTimeRange.LAST_24H,
    val points: List<TrafficDataPoint> = emptyList(),
    val summary: TrafficSummary? = null,
    val countries: List<jiamin.chen.orangecloud.data.model.CountryTraffic> = emptyList(),
    val isLoading: Boolean = false,
    val hasError: Boolean = false,
    val missingScope: Boolean = false,
    /** 7d/30d 为 Pro 功能；非 Pro 时这两档置锁。 */
    val isPro: Boolean = false,
    /** 访问明细（httpRequestsAdaptiveGroups 各维度前 10），与上面的图表互不影响。 */
    val details: AdaptiveSection<TrafficDetails> = AdaptiveSection.Loading,
    /** 安全事件（firewallEventsAdaptive*）。 */
    val security: AdaptiveSection<SecurityEvents> = AdaptiveSection.Loading,
)

@HiltViewModel
class ZoneAnalyticsViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val analyticsRepository: AnalyticsRepository,
    authRepository: AuthRepository,
    private val entitlementStore: jiamin.chen.orangecloud.core.purchase.EntitlementStore,
) : ViewModel() {

    private val zoneId: String = checkNotNull(savedStateHandle["zoneId"])
    private val zoneName: String = savedStateHandle.get<String>("zoneName").orEmpty()
    private val hasScope = authRepository.hasScope(Scopes.ANALYTICS_READ)
    /** 每次判断时现读：Play 的 queryPurchases 在 connect 后异步回来，冷启动直奔分析页时快照会是 false */
    private val isPro: Boolean get() = entitlementStore.isPro.value
    private var loadJob: Job? = null

    private val cache = mutableMapOf<AnalyticsTimeRange, List<TrafficDataPoint>>()
    // adaptive 明细：按范围缓存；数据集设置每个页面实例只读一次
    private val detailsCache = mutableMapOf<AnalyticsTimeRange, AdaptiveSection<TrafficDetails>>()
    private val securityCache = mutableMapOf<AnalyticsTimeRange, AdaptiveSection<SecurityEvents>>()
    private var adaptiveSettings: AdaptiveZoneSettings? = null
    private var adaptiveSettingsLoaded = false
    private var adaptiveJob: Job? = null
    private val countryCache = mutableMapOf<AnalyticsTimeRange, List<jiamin.chen.orangecloud.data.model.CountryTraffic>>()

    private val _uiState = MutableStateFlow(
        ZoneAnalyticsUiState(zoneName = zoneName, missingScope = !hasScope, isLoading = hasScope, isPro = isPro),
    )
    val uiState: StateFlow<ZoneAnalyticsUiState> = _uiState.asStateFlow()

    private val needsProChannel = kotlinx.coroutines.channels.Channel<Unit>(kotlinx.coroutines.channels.Channel.BUFFERED)
    val needsPro: kotlinx.coroutines.flow.Flow<Unit> = needsProChannel.receiveAsFlow()

    init {
        if (hasScope) load()
    }

    fun selectRange(range: AnalyticsTimeRange) {
        if (range == _uiState.value.range) return
        if (range != AnalyticsTimeRange.LAST_24H && !isPro) {
            needsProChannel.trySend(Unit)
            return
        }
        _uiState.update { it.copy(range = range) }
        load()
    }

    fun refresh() {
        cache.clear()
        countryCache.clear()
        detailsCache.clear()
        securityCache.clear()
        load(force = true)
    }

    private fun load(force: Boolean = false) {
        if (!hasScope) return
        // 明细段独立加载，失败只影响自己；放在缓存命中提前返回之前
        loadAdaptive(force)
        val range = _uiState.value.range
        if (!force) {
            cache[range]?.let { apply(it); return }
        }
        // 快速切 7d→30d 时前一个请求还在飞：取消它，晚到的 7d 数据不能顶在 30d 名下
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, hasError = false) }
            try {
                val points = analyticsRepository.zoneTraffic(zoneId, range)
                cache[range] = points
                apply(points)
                // 按国家/地区为附加视图，失败不影响主图表。
                val countries = runCatching { analyticsRepository.zoneCountryTraffic(zoneId, range) }
                    .getOrElse { if (it is CancellationException) throw it; emptyList() }
                countryCache[range] = countries
                _uiState.update { it.copy(countries = countries) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.update { it.copy(hasError = true) }
            } finally {
                // 被新一轮取消时 isLoading 归新一轮管
                if (isActive) _uiState.update { it.copy(isLoading = false) }
            }
        }
    }

    /**
     * 访问明细 + 安全事件。时间范围门槛与上面一致（selectRange 已拦 7d/30d 的非 Pro）。
     * 先读数据集设置：未开放 → 整段不可用；有保留期 / 最长跨度限制 → 收窄范围并标注。
     * 设置读不到时不收窄，直接查，查询失败再降级成不可用。
     */
    private fun loadAdaptive(force: Boolean) {
        val range = _uiState.value.range
        if (!force) {
            val details = detailsCache[range]
            val security = securityCache[range]
            if (details != null && security != null) {
                _uiState.update { it.copy(details = details, security = security) }
                return
            }
        }
        adaptiveJob?.cancel()
        adaptiveJob = viewModelScope.launch {
            _uiState.update { it.copy(details = AdaptiveSection.Loading, security = AdaptiveSection.Loading) }
            if (!adaptiveSettingsLoaded) {
                adaptiveSettings = runCatching { analyticsRepository.adaptiveSettings(zoneId) }
                    .getOrElse { if (it is CancellationException) throw it; null }
                adaptiveSettingsLoaded = true
            }
            val (since, until) = range.adaptiveWindow()
            val details = async {
                adaptiveSection(adaptiveSettings?.httpRequestsAdaptiveGroups, since, until) { s, u ->
                    analyticsRepository.trafficDetails(zoneId, s, u)
                }
            }
            val security = async {
                adaptiveSection(adaptiveSettings?.firewallEventsAdaptive, since, until) { s, u ->
                    analyticsRepository.securityEvents(zoneId, s, u)
                }
            }
            val d = details.await()
            val s = security.await()
            detailsCache[range] = d
            securityCache[range] = s
            _uiState.update { it.copy(details = d, security = s) }
        }
    }

    private suspend fun <T> adaptiveSection(
        setting: AdaptiveDatasetSetting?,
        since: Instant,
        until: Instant,
        fetch: suspend (Instant, Instant) -> T,
    ): AdaptiveSection<T> {
        val (start, clamped) = if (setting != null) {
            setting.clamp(since, until) ?: return AdaptiveSection.Unavailable
        } else {
            since to false
        }
        return try {
            AdaptiveSection.Ready(fetch(start, until), clamped)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            AdaptiveSection.Unavailable
        }
    }

    private fun apply(points: List<TrafficDataPoint>) {
        _uiState.update { it.copy(points = points, summary = summarize(points), countries = countryCache[_uiState.value.range].orEmpty()) }
    }

    private fun summarize(points: List<TrafficDataPoint>): TrafficSummary = TrafficSummary(
        requests = points.sumOf { it.requests.toLong() },
        bytes = points.sumOf { it.bytes },
        uniques = points.sumOf { it.uniques.toLong() },
        cachedRequests = points.sumOf { it.cachedRequests.toLong() },
        threats = points.sumOf { it.threats.toLong() },
    )
}
