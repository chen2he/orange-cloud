package jiamin.chen.orangecloud.ui.registrar

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.core.network.cfDocumentationUrl
import jiamin.chen.orangecloud.data.model.DomainAvailability
import jiamin.chen.orangecloud.data.repository.AccountStore
import jiamin.chen.orangecloud.data.repository.RegistrarRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class RegistrarSearchUiState(
    val results: List<DomainAvailability> = emptyList(),
    val isSearching: Boolean = false,
    val searched: Boolean = false,
    /** 正在实时确认的域名（点开某一行后）；确认结果放在 [checked]。 */
    val checking: String? = null,
    val checked: DomainAvailability? = null,
    val missingScope: Boolean = false,
)

sealed interface RegistrarSearchEvent {
    data class Error(val message: String?, val documentationUrl: String? = null) : RegistrarSearchEvent
}

/**
 * 搜索新域名（registrar-domains.read）。只查询不购买：可注册时引导去 Cloudflare 控制台注册。
 * 搜索结果可能滞后，点开某个域名时再用 domain-check 实时确认。
 */
@HiltViewModel
class RegistrarSearchViewModel @Inject constructor(
    private val repository: RegistrarRepository,
    private val accountStore: AccountStore,
    authRepository: AuthRepository,
) : ViewModel() {

    private val hasRead = authRepository.hasScope(Scopes.REGISTRAR_READ)

    private val _uiState = MutableStateFlow(RegistrarSearchUiState(missingScope = !hasRead))
    val uiState: StateFlow<RegistrarSearchUiState> = _uiState.asStateFlow()

    private val eventChannel = Channel<RegistrarSearchEvent>(Channel.BUFFERED)
    val events: Flow<RegistrarSearchEvent> = eventChannel.receiveAsFlow()

    private var searchJob: Job? = null

    fun search(query: String) {
        val q = query.trim()
        if (!hasRead || q.isEmpty()) return
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            _uiState.update { it.copy(isSearching = true) }
            try {
                accountStore.ensureLoaded()
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                val results = repository.searchDomains(accountId, q)
                _uiState.update { it.copy(results = results, searched = true) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                eventChannel.send(RegistrarSearchEvent.Error(e.message, e.cfDocumentationUrl))
            } finally {
                _uiState.update { it.copy(isSearching = false) }
            }
        }
    }

    /** 点开某个结果：实时确认可注册性与价格。 */
    fun check(name: String) {
        if (!hasRead) return
        _uiState.update { it.copy(checking = name, checked = null) }
        viewModelScope.launch {
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                val list = repository.checkDomains(accountId, listOf(name))
                val result = list.firstOrNull { it.name.equals(name, ignoreCase = true) } ?: list.firstOrNull()
                if (_uiState.value.checking == name) {
                    // 实时结果为空时退回列表里的（可能滞后的）结果，总比空白强
                    _uiState.update { s -> s.copy(checked = result ?: s.results.firstOrNull { it.name == name }) }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.update { it.copy(checking = null) }
                eventChannel.send(RegistrarSearchEvent.Error(e.message, e.cfDocumentationUrl))
            }
        }
    }

    fun dismissCheck() = _uiState.update { it.copy(checking = null, checked = null) }
}
