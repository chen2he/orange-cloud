package jiamin.chen.orangecloud.ui.workers

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.core.network.cfDocumentationUrl
import jiamin.chen.orangecloud.data.model.WorkerIssue
import jiamin.chen.orangecloud.data.model.WorkerIssueOccurrence
import jiamin.chen.orangecloud.data.model.WorkerIssueStatus
import jiamin.chen.orangecloud.data.model.WorkerIssuesSummary
import jiamin.chen.orangecloud.data.repository.AccountStore
import jiamin.chen.orangecloud.data.repository.WorkersIssuesRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

// MARK: - 问题列表（全账户，或经 service 参数限定到单个 Worker）

data class WorkerIssuesUiState(
    /** 非空 = 只看这个 Worker 的问题（从 Worker 详情进入）。 */
    val service: String? = null,
    val status: String = WorkerIssueStatus.ACTIVE,
    val issues: List<WorkerIssue> = emptyList(),
    val summary: WorkerIssuesSummary? = null,
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val loaded: Boolean = false,
    val hasError: Boolean = false,
    val hasMore: Boolean = false,
    val missingScope: Boolean = false,
)

sealed interface WorkerIssuesEvent {
    data class Error(val message: String?, val documentationUrl: String? = null) : WorkerIssuesEvent
}

@HiltViewModel
class WorkerIssuesViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val accountStore: AccountStore,
    private val repository: WorkersIssuesRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    private val hasRead = authRepository.hasScope(Scopes.WORKERS_OBSERVABILITY_READ)
    private val service: String? = savedStateHandle.get<String>("service")?.takeIf { it.isNotBlank() }
    private var page = 1

    private val _uiState = MutableStateFlow(
        WorkerIssuesUiState(service = service, isLoading = hasRead, missingScope = !hasRead),
    )
    val uiState: StateFlow<WorkerIssuesUiState> = _uiState.asStateFlow()

    private val eventChannel = Channel<WorkerIssuesEvent>(Channel.BUFFERED)
    val events: Flow<WorkerIssuesEvent> = eventChannel.receiveAsFlow()

    /** 当前列表请求；切状态 / 刷新时取消，晚到的旧筛选结果不能覆盖新筛选。 */
    private var listJob: Job? = null

    init {
        if (hasRead) load()
        // 详情页改了状态（仓库发 changes）→ 回到列表时已是最新，不必等用户手动刷新
        viewModelScope.launch { repository.changes.collect { load() } }
    }

    fun selectStatus(status: String) {
        if (status == _uiState.value.status) return
        _uiState.update { it.copy(status = status, issues = emptyList(), hasMore = false, loaded = false) }
        load()
    }

    fun load() {
        if (!hasRead) return
        page = 1
        listJob?.cancel()
        listJob = viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, hasError = false) }
            try {
                accountStore.ensureLoaded()
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                val status = _uiState.value.status
                // 汇总是附加信息，失败不影响列表
                val summary = async { runCatching { repository.summary(accountId, service) }.getOrNull() }
                val paged = repository.issues(accountId, status, service, page = 1)
                _uiState.update {
                    it.copy(
                        issues = paged.items,
                        hasMore = hasMorePages(paged.info?.page, paged.info?.totalPages, paged.items.size),
                        summary = summary.await() ?: it.summary,
                        loaded = true,
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.update { it.copy(hasError = true, loaded = true) }
                eventChannel.send(WorkerIssuesEvent.Error(e.message, e.cfDocumentationUrl))
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
        }
    }

    fun loadMore() {
        val s = _uiState.value
        if (!hasRead || !s.hasMore || s.isLoading || s.isLoadingMore) return
        listJob = viewModelScope.launch {
            _uiState.update { it.copy(isLoadingMore = true) }
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                val next = page + 1
                val paged = repository.issues(accountId, s.status, service, page = next)
                page = next
                _uiState.update { cur ->
                    cur.copy(
                        issues = (cur.issues + paged.items).distinctBy { it.id },
                        hasMore = hasMorePages(paged.info?.page, paged.info?.totalPages, paged.items.size),
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                eventChannel.send(WorkerIssuesEvent.Error(e.message, e.cfDocumentationUrl))
            } finally {
                _uiState.update { it.copy(isLoadingMore = false) }
            }
        }
    }

    /** total_pages 缺失时，退化为「本页满额就可能还有」。 */
    private fun hasMorePages(current: Int?, total: Int?, received: Int): Boolean =
        if (current != null && total != null) current < total
        else received >= WorkersIssuesRepository.PAGE_SIZE
}

// MARK: - 问题详情 + 最近发生

data class WorkerIssueDetailUiState(
    val issue: WorkerIssue? = null,
    val occurrences: List<WorkerIssueOccurrence> = emptyList(),
    val isLoading: Boolean = false,
    val isLoadingOccurrences: Boolean = false,
    val occurrencesLoaded: Boolean = false,
    val hasMoreOccurrences: Boolean = false,
    val hasError: Boolean = false,
    val isUpdating: Boolean = false,
    val missingScope: Boolean = false,
    /** workers-observability.write（新 scope）；没有就隐藏改状态按钮。 */
    val canWrite: Boolean = false,
)

sealed interface WorkerIssueDetailEvent {
    /** 状态已改（界面提示；列表经仓库 changes 自行刷新）。 */
    data class StatusChanged(val status: String) : WorkerIssueDetailEvent
    data class Error(val message: String?, val documentationUrl: String? = null) : WorkerIssueDetailEvent
}

@HiltViewModel
class WorkerIssueDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val accountStore: AccountStore,
    private val repository: WorkersIssuesRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    val issueId: String = checkNotNull(savedStateHandle["issueId"])
    private val hasRead = authRepository.hasScope(Scopes.WORKERS_OBSERVABILITY_READ)
    private val canWrite = authRepository.hasScope(Scopes.WORKERS_OBSERVABILITY_WRITE)
    private var cursor: String? = null

    private val _uiState = MutableStateFlow(
        WorkerIssueDetailUiState(isLoading = hasRead, missingScope = !hasRead, canWrite = canWrite),
    )
    val uiState: StateFlow<WorkerIssueDetailUiState> = _uiState.asStateFlow()

    private val eventChannel = Channel<WorkerIssueDetailEvent>(Channel.BUFFERED)
    val events: Flow<WorkerIssueDetailEvent> = eventChannel.receiveAsFlow()

    init {
        if (hasRead) load()
    }

    fun load() {
        if (!hasRead) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, hasError = false) }
            try {
                accountStore.ensureLoaded()
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                val issue = repository.issue(accountId, issueId)
                _uiState.update { it.copy(issue = issue, hasError = issue == null) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.update { it.copy(hasError = true) }
                eventChannel.send(WorkerIssueDetailEvent.Error(e.message, e.cfDocumentationUrl))
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
            loadOccurrences(reset = true)
        }
    }

    fun loadMoreOccurrences() {
        val s = _uiState.value
        if (!s.hasMoreOccurrences || s.isLoadingOccurrences) return
        viewModelScope.launch { loadOccurrences(reset = false) }
    }

    /** 发生记录是附加信息：失败只停在已加载的部分，不连累详情。 */
    private suspend fun loadOccurrences(reset: Boolean) {
        if (reset) cursor = null
        _uiState.update { it.copy(isLoadingOccurrences = true) }
        try {
            val accountId = accountStore.selectedAccountId.value ?: return
            val page = repository.occurrences(accountId, issueId, cursor)
            cursor = page.nextCursor
            _uiState.update {
                it.copy(
                    occurrences = if (reset) page.items else it.occurrences + page.items,
                    hasMoreOccurrences = page.nextCursor != null,
                )
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            _uiState.update { it.copy(hasMoreOccurrences = false) }
        } finally {
            _uiState.update { it.copy(isLoadingOccurrences = false, occurrencesLoaded = true) }
        }
    }

    /** 标记为已解决 / 忽略 / 重新打开。 */
    fun updateStatus(status: String) {
        if (!canWrite || _uiState.value.isUpdating) return
        viewModelScope.launch {
            _uiState.update { it.copy(isUpdating = true) }
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                val updated = repository.updateStatus(accountId, issueId, status)
                _uiState.update { s -> s.copy(issue = updated ?: s.issue?.copy(status = status)) }
                eventChannel.send(WorkerIssueDetailEvent.StatusChanged(status))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                eventChannel.send(WorkerIssueDetailEvent.Error(e.message, e.cfDocumentationUrl))
            } finally {
                _uiState.update { it.copy(isUpdating = false) }
            }
        }
    }
}
