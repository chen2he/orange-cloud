package jiamin.chen.orangecloud.ui.securityinsights

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.core.network.cfDocumentationUrl
import jiamin.chen.orangecloud.data.model.SecurityInsight
import jiamin.chen.orangecloud.data.repository.SecurityInsightsRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SecurityInsightsUiState(
    val zoneName: String = "",
    val insights: List<SecurityInsight> = emptyList(),
    val isLoading: Boolean = false,
    val loaded: Boolean = false,
    val hasError: Boolean = false,
    val isScanning: Boolean = false,
    /** 正在忽略的洞察 id（逐条禁用按钮，防连点）。 */
    val dismissing: Set<String> = emptySet(),
    val missingScope: Boolean = false,
    val canWrite: Boolean = false,
)

sealed interface SecurityInsightsEvent {
    data object ScanStarted : SecurityInsightsEvent
    data object Dismissed : SecurityInsightsEvent
    data class Error(val message: String?, val documentationUrl: String? = null) : SecurityInsightsEvent
}

/**
 * 域名级安全洞察（Security Center Insights）。全套餐可用，不设 Pro 闸门。
 * 读走 zone-settings.read；发起扫描 / 忽略走 zone-settings.write。
 */
@HiltViewModel
class SecurityInsightsViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repository: SecurityInsightsRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    private val zoneId: String = checkNotNull(savedStateHandle["zoneId"])
    private val hasRead = authRepository.hasScope(Scopes.ZONE_SETTINGS_READ)
    private val canWrite = authRepository.hasScope(Scopes.ZONE_SETTINGS_WRITE)

    private val _uiState = MutableStateFlow(
        SecurityInsightsUiState(
            zoneName = savedStateHandle.get<String>("zoneName").orEmpty(),
            isLoading = hasRead,
            missingScope = !hasRead,
            canWrite = canWrite,
        ),
    )
    val uiState: StateFlow<SecurityInsightsUiState> = _uiState.asStateFlow()

    private val eventChannel = Channel<SecurityInsightsEvent>(Channel.BUFFERED)
    val events: Flow<SecurityInsightsEvent> = eventChannel.receiveAsFlow()

    init {
        if (hasRead) load()
    }

    fun load() {
        if (!hasRead) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, hasError = false) }
            try {
                val list = repository.insights(zoneId)
                _uiState.update { it.copy(insights = list, loaded = true) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.update { it.copy(hasError = true, loaded = true) }
                eventChannel.send(SecurityInsightsEvent.Error(e.message, e.cfDocumentationUrl))
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
        }
    }

    /** 立即扫描。限额（每账户每 24 小时 5 次）由服务端判定，超限把 CF 的报错原文透给用户。 */
    fun scan() {
        if (!canWrite || _uiState.value.isScanning) return
        viewModelScope.launch {
            _uiState.update { it.copy(isScanning = true) }
            try {
                repository.scan(zoneId)
                eventChannel.send(SecurityInsightsEvent.ScanStarted)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                eventChannel.send(SecurityInsightsEvent.Error(e.message, e.cfDocumentationUrl))
            } finally {
                _uiState.update { it.copy(isScanning = false) }
            }
        }
    }

    /** 忽略一条洞察；成功后从列表移除（列表只取 dismissed=false）。 */
    fun dismiss(insight: SecurityInsight) {
        if (!canWrite || insight.id in _uiState.value.dismissing) return
        viewModelScope.launch {
            _uiState.update { it.copy(dismissing = it.dismissing + insight.id) }
            try {
                repository.dismiss(zoneId, insight.id)
                _uiState.update { s -> s.copy(insights = s.insights.filterNot { it.id == insight.id }) }
                eventChannel.send(SecurityInsightsEvent.Dismissed)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                eventChannel.send(SecurityInsightsEvent.Error(e.message, e.cfDocumentationUrl))
            } finally {
                _uiState.update { it.copy(dismissing = it.dismissing - insight.id) }
            }
        }
    }
}
