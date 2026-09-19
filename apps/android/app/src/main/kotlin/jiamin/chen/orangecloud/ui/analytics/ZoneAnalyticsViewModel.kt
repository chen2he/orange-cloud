package jiamin.chen.orangecloud.ui.analytics

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.data.model.AnalyticsTimeRange
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
        load(force = true)
    }

    private fun load(force: Boolean = false) {
        if (!hasScope) return
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
