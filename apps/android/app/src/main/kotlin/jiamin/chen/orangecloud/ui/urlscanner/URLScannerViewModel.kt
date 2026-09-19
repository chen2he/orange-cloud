package jiamin.chen.orangecloud.ui.urlscanner

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.core.network.ApiError
import jiamin.chen.orangecloud.data.model.URLScanResult
import jiamin.chen.orangecloud.data.repository.AccountStore
import jiamin.chen.orangecloud.data.repository.URLScannerRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class URLScannerUiState(
    val url: String = "",
    val result: URLScanResult? = null,
    val isScanning: Boolean = false,
    val missingScope: Boolean = false,
) {
    val canScan: Boolean get() = url.trim().isNotEmpty() && url.contains(".") && !isScanning
}

sealed interface URLScannerEvent {
    data class Error(val message: String?) : URLScannerEvent
    /** 409：同一主机名近期已扫过，Cloudflare 拒绝重复提交 */
    data object RecentlyScanned : URLScannerEvent
}

@HiltViewModel
class URLScannerViewModel @Inject constructor(
    private val repository: URLScannerRepository,
    private val accountStore: AccountStore,
    authRepository: AuthRepository,
) : ViewModel() {

    private val hasRead = authRepository.hasScope(Scopes.URL_SCANNER_READ)

    private val _uiState = MutableStateFlow(URLScannerUiState(missingScope = !hasRead))
    val uiState: StateFlow<URLScannerUiState> = _uiState.asStateFlow()

    private val eventChannel = Channel<URLScannerEvent>(Channel.BUFFERED)
    val events: Flow<URLScannerEvent> = eventChannel.receiveAsFlow()

    /** 轮询上限：2 秒一次、最多 30 次（约 1 分钟）。超时按「还没出结果」处理而非报错。 */
    private val maxPolls = 30
    private val pollIntervalMs = 2_000L

    fun setUrl(value: String) = _uiState.update { it.copy(url = value) }

    fun scan() {
        val state = _uiState.value
        if (!hasRead || !state.canScan) return
        viewModelScope.launch {
            _uiState.update { it.copy(isScanning = true, result = null) }
            runCatching {
                accountStore.ensureLoaded()
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                // 用户多半只输域名，补上协议再提交
                val target = state.url.trim().let { if (it.contains("://")) it else "https://$it" }
                val scanId = repository.submit(accountId, target) ?: error("no scan id")
                var report: URLScanResult? = null
                repeat(maxPolls) {
                    delay(pollIntervalMs)
                    report = runCatching { repository.result(accountId, scanId) }.getOrNull()
                    if (report != null) return@repeat
                }
                report
            }
                .onSuccess { report ->
                    if (report == null) {
                        eventChannel.send(URLScannerEvent.Error(null))
                    }
                    _uiState.update { it.copy(result = report) }
                }
                .onFailure {
                    if (it is CancellationException) throw it
                    if (it is ApiError.Http && it.status == 409) {
                        eventChannel.send(URLScannerEvent.RecentlyScanned)
                    } else {
                        eventChannel.send(URLScannerEvent.Error(it.message))
                    }
                }
            _uiState.update { it.copy(isScanning = false) }
        }
    }
}
