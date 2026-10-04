package jiamin.chen.orangecloud.ui.network

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.data.model.CreateDnsRecord
import jiamin.chen.orangecloud.data.model.IngressRule
import jiamin.chen.orangecloud.data.model.Tunnel
import jiamin.chen.orangecloud.data.model.TunnelConfig
import jiamin.chen.orangecloud.data.model.TunnelConnection
import jiamin.chen.orangecloud.data.model.Zone
import jiamin.chen.orangecloud.data.repository.AccountStore
import jiamin.chen.orangecloud.data.repository.DnsRepository
import jiamin.chen.orangecloud.data.repository.SecurityRepository
import jiamin.chen.orangecloud.data.repository.ZoneRepository
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class TunnelDetailUiState(
    val tunnel: Tunnel? = null,
    val isLoading: Boolean = false,
    val hasError: Boolean = false,
    val missingScope: Boolean = false,
    // 连接令牌
    val token: String? = null,
    val isLoadingToken: Boolean = false,
    // 配置（公共主机名 / ingress）
    val config: TunnelConfig? = null,
    val isLoadingConfig: Boolean = false,
    val configLoaded: Boolean = false,
    val isSaving: Boolean = false,
    val canWrite: Boolean = false,
    val error: String? = null,
    // 活跃连接：首帧用内嵌数组占位，随后由专用端点覆盖
    // （内嵌字段 CF 将于 2026-10-05 移除，届时占位恒为空、完全依赖端点）
    val connections: List<TunnelConnection> = emptyList(),
    val isLoadingConnections: Boolean = false,
) {
    /** 非 catch-all 的公共主机名规则（供 UI 列表）。 */
    val publicHostnames: List<IngressRule>
        get() = (config?.ingress ?: emptyList()).filter { !it.isCatchAll }
}

sealed interface TunnelDetailEvent {
    data object Deleted : TunnelDetailEvent
    data class Notice(val message: String) : TunnelDetailEvent
    data class Error(val message: String?) : TunnelDetailEvent
}

/** 单条隧道详情：信息 + 连接令牌 + 公共主机名管理 + 危险操作（对齐 iOS TunnelDetailView）。 */
@HiltViewModel
class TunnelDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val accountStore: AccountStore,
    private val securityRepository: SecurityRepository,
    private val dnsRepository: DnsRepository,
    private val zoneRepository: ZoneRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    val tunnelId: String = checkNotNull(savedStateHandle["tunnelId"])
    val tunnelName: String = savedStateHandle.get<String>("tunnelName").orEmpty()
    private val hasScope = authRepository.hasScope(Scopes.TUNNEL_READ)
    private val canWrite = authRepository.hasScope(Scopes.TUNNEL_WRITE)
    private val canWriteDNS = authRepository.hasScope(Scopes.DNS_WRITE)
    private var zonesCache: List<Zone>? = null

    private val _uiState = MutableStateFlow(
        TunnelDetailUiState(isLoading = hasScope, missingScope = !hasScope, canWrite = canWrite),
    )
    val uiState: StateFlow<TunnelDetailUiState> = _uiState.asStateFlow()

    private val eventChannel = Channel<TunnelDetailEvent>(Channel.BUFFERED)
    val events: Flow<TunnelDetailEvent> = eventChannel.receiveAsFlow()

    /** CNAME 目标：<隧道ID>.cfargotunnel.com */
    val cnameTarget: String get() = "$tunnelId.cfargotunnel.com"

    init {
        if (hasScope) load()
    }

    fun load() {
        if (!hasScope) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, hasError = false) }
            try {
                accountStore.ensureLoaded()
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                val tunnel = securityRepository.getTunnel(accountId, tunnelId)
                _uiState.update {
                    it.copy(tunnel = tunnel, connections = tunnel.connections.orEmpty())
                }
                loadConnections(accountId)
                if (tunnel.isRemotelyManaged == true) loadConfiguration(accountId)
            } catch (e: Exception) {
                _uiState.update { it.copy(hasError = true) }
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
        }
    }

    /** 连接令牌（argotunnel.write 才可读）。按需加载一次。 */
    fun loadToken() {
        if (!canWrite || _uiState.value.token != null || _uiState.value.isLoadingToken) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingToken = true) }
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                val token = securityRepository.tunnelToken(accountId, tunnelId)
                _uiState.update { it.copy(token = token) }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            } finally {
                _uiState.update { it.copy(isLoadingToken = false) }
            }
        }
    }

    private suspend fun loadConfiguration(accountId: String) {
        _uiState.update { it.copy(isLoadingConfig = true) }
        try {
            val config = securityRepository.configuration(accountId, tunnelId)
            _uiState.update { it.copy(config = config, configLoaded = true) }
        } catch (e: Exception) {
            _uiState.update { it.copy(error = e.message) }
        } finally {
            _uiState.update { it.copy(isLoadingConfig = false) }
        }
    }

    /** 清理失活连接（活跃的 cloudflared 会自动重连）。 */
    /** 拉取活跃连接。失败不报错——详情页其余内容仍可用，保留占位数据即可。 */
    private suspend fun loadConnections(accountId: String) {
        _uiState.update { it.copy(isLoadingConnections = true) }
        try {
            val conns = securityRepository.tunnelConnections(accountId, tunnelId)
            _uiState.update { it.copy(connections = conns) }
        } catch (_: Exception) {
            // 保留内嵌占位，不打断详情页
        } finally {
            _uiState.update { it.copy(isLoadingConnections = false) }
        }
    }

    fun cleanupConnections() {
        if (!canWrite || _uiState.value.isSaving) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true) }
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                securityRepository.deleteConnections(accountId, tunnelId)
                load()
            } catch (e: Exception) {
                eventChannel.send(TunnelDetailEvent.Error(e.message))
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    /** 删除隧道：成功后发出 Deleted（界面退出）。 */
    fun deleteTunnel() {
        if (!canWrite || _uiState.value.isSaving) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true) }
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                securityRepository.deleteTunnel(accountId, tunnelId)
                eventChannel.send(TunnelDetailEvent.Deleted)
            } catch (e: Exception) {
                eventChannel.send(TunnelDetailEvent.Error(e.message))
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    /** 新增或更新一条公共主机名。index 为 null 时新增（并尝试自动建 CNAME）。 */
    fun saveHostname(rule: IngressRule, index: Int?) {
        if (!canWrite || _uiState.value.isSaving) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, error = null) }
            try {
                val rules = _uiState.value.publicHostnames.toMutableList()
                if (index != null && index in rules.indices) rules[index] = rule else rules.add(rule)
                if (saveIngress(rules)) {
                    if (index == null && !rule.hostname.isNullOrEmpty()) ensureCname(rule.hostname)
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    fun deleteHostname(index: Int) {
        if (!canWrite || _uiState.value.isSaving) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true) }
            try {
                val rules = _uiState.value.publicHostnames.toMutableList()
                if (index in rules.indices) {
                    rules.removeAt(index)
                    saveIngress(rules) // 不自动删 DNS，避免误删用户其它记录
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    /** 拼装整份 ingress（编辑后的规则 + 原 catch-all）并回写。 */
    private suspend fun saveIngress(rules: List<IngressRule>): Boolean {
        val accountId = accountStore.selectedAccountId.value ?: return false
        val current = _uiState.value.config
        val catchAll = current?.ingress?.firstOrNull { it.isCatchAll } ?: IngressRule.catchAll
        val newConfig = (current ?: TunnelConfig()).copy(ingress = rules + catchAll)
        return try {
            val saved = securityRepository.updateConfiguration(accountId, tunnelId, newConfig)
            _uiState.update { it.copy(config = saved) }
            true
        } catch (e: Exception) {
            _uiState.update { it.copy(error = e.message) }
            false
        }
    }

    /** 为公共主机名自动建代理 CNAME；无 dns.write 或找不到域名时给出手动提示。 */
    private suspend fun ensureCname(hostname: String) {
        if (!canWriteDNS) {
            eventChannel.send(TunnelDetailEvent.Notice(manualCnameMessage(hostname)))
            return
        }
        try {
            val zone = bestZone(hostname, zones()) ?: run {
                eventChannel.send(TunnelDetailEvent.Notice(manualCnameMessage(hostname)))
                return
            }
            dnsRepository.createRecord(
                zone.id,
                CreateDnsRecord(type = "CNAME", name = hostname, content = cnameTarget, proxied = true, ttl = 1, comment = "Cloudflare Tunnel"),
            )
            eventChannel.send(TunnelDetailEvent.Notice("$hostname → $cnameTarget"))
        } catch (e: Exception) {
            eventChannel.send(TunnelDetailEvent.Notice(manualCnameMessage(hostname)))
        }
    }

    private fun manualCnameMessage(hostname: String): String = "$hostname CNAME → $cnameTarget"

    private suspend fun zones(): List<Zone> {
        zonesCache?.let { return it }
        val accountId = accountStore.selectedAccountId.value ?: return emptyList()
        return zoneRepository.listZones(accountId).also { zonesCache = it }
    }

    /** hostname 所属 zone：取名字最长的后缀匹配项（处理多级子域名/多 zone）。 */
    private fun bestZone(hostname: String, zones: List<Zone>): Zone? =
        zones.filter { hostname == it.name || hostname.endsWith("." + it.name) }.maxByOrNull { it.name.length }
}
