package jiamin.chen.orangecloud.ui.workers

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.data.model.AnalyticsTimeRange
import jiamin.chen.orangecloud.data.model.WorkerMetrics
import jiamin.chen.orangecloud.data.model.WorkerScript
import jiamin.chen.orangecloud.data.model.WorkerSeriesPoint
import jiamin.chen.orangecloud.data.repository.AccountStore
import jiamin.chen.orangecloud.data.repository.AnalyticsRepository
import jiamin.chen.orangecloud.data.repository.WorkerRepository
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
    authRepository: AuthRepository,
) : ViewModel() {

    val scriptName: String = checkNotNull(savedStateHandle["scriptName"])
    private val accountId: String? = accountStore.selectedAccountId.value
    val canViewMetrics: Boolean = authRepository.hasScope(Scopes.ANALYTICS_READ)
    val canWrite: Boolean = authRepository.hasScope(Scopes.WORKERS_WRITE)

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
