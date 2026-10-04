package jiamin.chen.orangecloud.ui.workers

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.core.system.AppPrefs
import jiamin.chen.orangecloud.core.system.ResourceSort
import jiamin.chen.orangecloud.data.model.WorkerScript
import jiamin.chen.orangecloud.data.repository.AccountStore
import jiamin.chen.orangecloud.data.model.WorkerIssuesSummary
import jiamin.chen.orangecloud.data.repository.WorkerRepository
import jiamin.chen.orangecloud.data.repository.WorkersIssuesRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

data class WorkerListUiState(
    val workers: List<WorkerScript> = emptyList(),
    val isLoading: Boolean = false,
    val hasError: Boolean = false,
    /** 未授予 workers-scripts.read：前置拦截，不打 API，提示去授权。 */
    val missingScope: Boolean = false,
    /** workers-scripts.write：有则展示「新建 Worker」入口。 */
    val canWrite: Boolean = false,
)

@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel
class WorkerListViewModel @Inject constructor(
    private val accountStore: AccountStore,
    private val workerRepository: WorkerRepository,
    private val issuesRepository: WorkersIssuesRepository,
    private val appPrefs: AppPrefs,
    authRepository: AuthRepository,
) : ViewModel() {

    /** 列表排序偏好（持久化，与 iOS @AppStorage 对应）。 */
    val sort: StateFlow<ResourceSort> = appPrefs.listSort("workers")
        .stateIn(viewModelScope, SharingStarted.Eagerly, ResourceSort.NAME)

    fun setSort(sort: ResourceSort) {
        viewModelScope.launch { appPrefs.setListSort("workers", sort) }
    }

    private val hasReadScope = authRepository.hasScope(Scopes.WORKERS_READ)
    private val canWriteScope = authRepository.hasScope(Scopes.WORKERS_WRITE)
    private val loading = MutableStateFlow(false)
    private val error = MutableStateFlow(false)

    /** Workers Issues 全账户汇总（入口行的副标题），best-effort；缺 workers-observability.read 不请求。 */
    private val canViewIssues = authRepository.hasScope(Scopes.WORKERS_OBSERVABILITY_READ)
    private val _issuesSummary = MutableStateFlow<WorkerIssuesSummary?>(null)
    val issuesSummary: StateFlow<WorkerIssuesSummary?> = _issuesSummary.asStateFlow()

    private val workers: Flow<List<WorkerScript>> = accountStore.selectedAccountId.flatMapLatest { id ->
        if (id == null) flowOf(emptyList()) else workerRepository.observeWorkers(id)
    }

    val uiState: StateFlow<WorkerListUiState> =
        combine(workers, loading, error) { list, isLoading, hasError ->
            WorkerListUiState(
                workers = list,
                isLoading = isLoading,
                hasError = hasError,
                missingScope = !hasReadScope,
                canWrite = canWriteScope,
            )
        }.stateIn(
            viewModelScope,
            SharingStarted.WhileSubscribed(5_000),
            WorkerListUiState(isLoading = hasReadScope, missingScope = !hasReadScope, canWrite = canWriteScope),
        )

    init {
        refresh()
    }

    fun refresh() {
        if (!hasReadScope) return
        viewModelScope.launch {
            loading.value = true
            error.value = false
            try {
                accountStore.ensureLoaded()
                val id = accountStore.selectedAccountId.value
                if (id == null) error.value = true else workerRepository.refreshWorkers(id)
            } catch (e: Exception) {
                error.value = true
            } finally {
                loading.value = false
            }
        }
        if (canViewIssues) {
            viewModelScope.launch {
                val id = accountStore.run { ensureLoaded(); selectedAccountId.value } ?: return@launch
                _issuesSummary.value = runCatching { issuesRepository.summary(id) }
                    .getOrElse { if (it is CancellationException) throw it; null }
            }
        }
    }
}
