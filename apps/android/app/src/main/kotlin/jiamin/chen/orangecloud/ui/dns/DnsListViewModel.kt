package jiamin.chen.orangecloud.ui.dns

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.core.network.ApiError
import jiamin.chen.orangecloud.data.model.CreateDnsRecord
import jiamin.chen.orangecloud.data.model.DnsRecord
import jiamin.chen.orangecloud.data.model.DnsShadowInfo
import jiamin.chen.orangecloud.data.repository.DnsRepository
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

data class DnsListUiState(
    val zoneName: String = "",
    val records: List<DnsRecord> = emptyList(),
    /** 记录 id → 遮蔽信息（只含被遮蔽 / 遮蔽了别人的记录）。 */
    val shadow: Map<String, DnsShadowInfo> = emptyMap(),
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    /** 是否授予 dns.write：决定是否展示新建 / 编辑 / 删除入口。 */
    val canEdit: Boolean = false,
    /** 列表加载失败（展示通用错误态）。 */
    val loadFailed: Boolean = false,
)

/** 一次性事件：驱动表单关闭、Snackbar 反馈（cfMessage 非空时直接展示 Cloudflare 报错）。 */
sealed interface DnsEvent {
    data object Saved : DnsEvent
    data object Deleted : DnsEvent
    data class Error(val cfMessage: String?) : DnsEvent
}

/**
 * 某个域名下 DNS 记录的拉取与增删改，全部同步进 Room 缓存（对应 iOS DNSListViewModel）。
 * zoneId / zoneName 由导航参数经 SavedStateHandle 注入。
 */
@HiltViewModel
class DnsListViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val dnsRepository: DnsRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    private val zoneId: String = checkNotNull(savedStateHandle["zoneId"])
    private val zoneName: String = savedStateHandle.get<String>("zoneName").orEmpty()
    private val canEdit: Boolean = authRepository.hasScope(Scopes.DNS_WRITE)

    private val loading = MutableStateFlow(false)
    private val saving = MutableStateFlow(false)
    private val loadFailed = MutableStateFlow(false)

    private val eventChannel = Channel<DnsEvent>(Channel.BUFFERED)
    val events: Flow<DnsEvent> = eventChannel.receiveAsFlow()

    val uiState: StateFlow<DnsListUiState> =
        combine(
            dnsRepository.observeRecords(zoneId),
            dnsRepository.observeShadow(zoneId),
            loading,
            saving,
            loadFailed,
        ) { records, shadow, isLoading, isSaving, failed ->
            DnsListUiState(
                zoneName = zoneName,
                records = records,
                shadow = shadow,
                isLoading = isLoading,
                isSaving = isSaving,
                canEdit = canEdit,
                loadFailed = failed,
            )
        }.stateIn(
            viewModelScope,
            SharingStarted.WhileSubscribed(5_000),
            DnsListUiState(zoneName = zoneName, isLoading = true, canEdit = canEdit),
        )

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            loading.value = true
            loadFailed.value = false
            try {
                dnsRepository.refreshRecords(zoneId)
            } catch (e: Exception) {
                loadFailed.value = true
            } finally {
                loading.value = false
            }
        }
    }

    /** 新建（recordId == null）或更新记录。成功 / 失败通过 events 反馈，UI 据此关闭表单。 */
    fun save(recordId: String?, record: CreateDnsRecord) {
        if (!canEdit) return
        viewModelScope.launch {
            saving.value = true
            try {
                if (recordId == null) {
                    dnsRepository.createRecord(zoneId, record)
                } else {
                    dnsRepository.updateRecord(zoneId, recordId, record)
                }
                eventChannel.send(DnsEvent.Saved)
            } catch (e: Exception) {
                eventChannel.send(DnsEvent.Error(cfMessageOf(e)))
            } finally {
                saving.value = false
            }
        }
    }

    fun delete(recordId: String) {
        if (!canEdit) return
        viewModelScope.launch {
            saving.value = true
            try {
                dnsRepository.deleteRecord(zoneId, recordId)
                eventChannel.send(DnsEvent.Deleted)
            } catch (e: Exception) {
                eventChannel.send(DnsEvent.Error(cfMessageOf(e)))
            } finally {
                saving.value = false
            }
        }
    }

    /** 取 Cloudflare 业务报错文案（已是可读句子）；非业务错误返回 null，由 UI 用通用本地化文案兜底。 */
    private fun cfMessageOf(e: Throwable): String? = when (e) {
        is ApiError.Cloudflare -> e.errors.firstOrNull()?.message
        is ApiError.Http -> e.cfErrors.firstOrNull()?.message
        else -> null
    }
}
