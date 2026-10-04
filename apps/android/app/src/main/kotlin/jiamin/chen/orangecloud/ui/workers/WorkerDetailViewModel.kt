package jiamin.chen.orangecloud.ui.workers

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.data.model.AnalyticsTimeRange
import jiamin.chen.orangecloud.data.model.WorkerMetrics
import jiamin.chen.orangecloud.data.model.WorkerPreview
import jiamin.chen.orangecloud.data.model.WorkerScript
import jiamin.chen.orangecloud.data.model.WorkerSeriesPoint
import jiamin.chen.orangecloud.data.repository.AccountStore
import jiamin.chen.orangecloud.data.repository.AnalyticsRepository
import jiamin.chen.orangecloud.data.repository.WorkerRepository
import jiamin.chen.orangecloud.data.repository.WorkersIssuesRepository
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job

sealed interface WorkerDeleteEvent {
    data object Deleted : WorkerDeleteEvent
    data class Error(val message: String?) : WorkerDeleteEvent
}

@HiltViewModel
class WorkerDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    accountStore: AccountStore,
    private val workerRepository: WorkerRepository,
    private val analyticsRepository: AnalyticsRepository,
    private val issuesRepository: WorkersIssuesRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    val scriptName: String = checkNotNull(savedStateHandle["scriptName"])
    private val accountId: String? = accountStore.selectedAccountId.value
    val canViewMetrics: Boolean = authRepository.hasScope(Scopes.ANALYTICS_READ)
    val canWrite: Boolean = authRepository.hasScope(Scopes.WORKERS_WRITE)
    /** Workers Issues 汇总（workers-observability.read）。缺权限时不显示入口计数。 */
    val canViewIssues: Boolean = authRepository.hasScope(Scopes.WORKERS_OBSERVABILITY_READ)

    /** 预览列表（beta）；失败或为空时整段隐藏。 */
    private val _previews = MutableStateFlow<List<WorkerPreview>>(emptyList())
    val previews: StateFlow<List<WorkerPreview>> = _previews.asStateFlow()

    /** 该 Worker 的活跃问题数；未加载 / 失败为 null（入口照常显示，只是不带数字）。 */
    private val _activeIssues = MutableStateFlow<Long?>(null)
    val activeIssues: StateFlow<Long?> = _activeIssues.asStateFlow()

    private val _isDeleting = MutableStateFlow(false)
    val isDeleting: StateFlow<Boolean> = _isDeleting.asStateFlow()

    private val deleteChannel = Channel<WorkerDeleteEvent>(Channel.BUFFERED)
    val deleteEvents: Flow<WorkerDeleteEvent> = deleteChannel.receiveAsFlow()

    /** 删除整个 Worker（连同部署 / 路由绑定）。须经二次确认，不可恢复。成功后触发返回。 */
    fun delete() {
        if (!canWrite || accountId == null || _isDeleting.value) return
        _isDeleting.update { true }
        viewModelScope.launch {
            try {
                workerRepository.deleteScript(accountId, scriptName)
                deleteChannel.send(WorkerDeleteEvent.Deleted)
            } catch (e: Exception) {
                deleteChannel.send(WorkerDeleteEvent.Error(e.message))
            } finally {
                _isDeleting.update { false }
            }
        }
    }

    val worker: StateFlow<WorkerScript?> =
        if (accountId == null) {
            MutableStateFlow(null)
        } else {
            workerRepository.observeWorkers(accountId)
                .map { list -> list.firstOrNull { it.id == scriptName } }
                .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)
        }

    private val _metrics = MutableStateFlow<WorkerMetrics?>(null)
    val metrics: StateFlow<WorkerMetrics?> = _metrics.asStateFlow()

    private val _series = MutableStateFlow<List<WorkerSeriesPoint>>(emptyList())
    val series: StateFlow<List<WorkerSeriesPoint>> = _series.asStateFlow()

    private val _metricsLoading = MutableStateFlow(false)
    val metricsLoading: StateFlow<Boolean> = _metricsLoading.asStateFlow()

    private val _range = MutableStateFlow(AnalyticsTimeRange.LAST_24H)
    val range: StateFlow<AnalyticsTimeRange> = _range.asStateFlow()

    init {
        if (accountId != null && canViewMetrics) loadMetrics()
        if (accountId != null) loadPreviews()
        if (accountId != null && canViewIssues) {
            loadIssueSummary()
            // 在问题详情里改了状态，返回时计数跟着更新
            viewModelScope.launch { issuesRepository.changes.collect { loadIssueSummary() } }
        }
    }

    /** 预览（beta）。失败按「没有预览」处理，不打扰用户。 */
    private fun loadPreviews() {
        if (accountId == null) return
        viewModelScope.launch {
            _previews.value = runCatching { workerRepository.previews(accountId, scriptName) }
                .getOrElse { if (it is CancellationException) throw it; emptyList() }
        }
    }

    /** 活跃问题数（summary?service=脚本名）。公开测试端点，失败静默。 */
    fun loadIssueSummary() {
        if (accountId == null || !canViewIssues) return
        viewModelScope.launch {
            val summary = runCatching { issuesRepository.summary(accountId, scriptName) }
                .getOrElse { if (it is CancellationException) throw it; null }
            _activeIssues.value = summary?.activeIssues
        }
    }

    fun selectRange(range: AnalyticsTimeRange) {
        if (range == _range.value) return
        _range.value = range
        loadMetrics()
    }

    private var metricsJob: Job? = null

    private fun loadMetrics() {
        if (accountId == null || !canViewMetrics) return
        // 切范围先取消上一轮：晚到的旧范围数据不能顶在新范围名下，旧轮也不能提前把加载态关掉
        metricsJob?.cancel()
        metricsJob = viewModelScope.launch {
            _metricsLoading.value = true
            val range = _range.value
            val metrics = runCatching {
                analyticsRepository.workerMetrics(accountId, scriptName, range)
            }.getOrElse { if (it is CancellationException) throw it; null }
            // 趋势序列单独 runCatching，新字段失败不拖累摘要卡
            val series = runCatching {
                analyticsRepository.workerSeries(accountId, scriptName, range)
            }.getOrElse { if (it is CancellationException) throw it; emptyList() }
            _metrics.value = metrics
            _series.value = series
            _metricsLoading.value = false
        }
    }
}
