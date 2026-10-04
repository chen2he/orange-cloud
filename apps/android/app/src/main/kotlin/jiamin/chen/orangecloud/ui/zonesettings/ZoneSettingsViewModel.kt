package jiamin.chen.orangecloud.ui.zonesettings

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.data.model.BotManagementConfig
import jiamin.chen.orangecloud.data.model.BotManagementUpdate
import jiamin.chen.orangecloud.data.repository.AccountStore
import jiamin.chen.orangecloud.data.repository.ZoneRepository
import jiamin.chen.orangecloud.data.repository.ZoneSettingsRepository
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface ZoneSettingsEvent {
    data object Purged : ZoneSettingsEvent
    data class Error(val message: String?) : ZoneSettingsEvent
}

data class ZoneSettingsUiState(
    val zoneName: String = "",
    val developmentMode: Boolean = false,
    val underAttack: Boolean = false,
    /** 是否暂停 Cloudflare 代理。与上面两个开关不同源：读写的是域名本身。 */
    val paused: Boolean = false,
    /** AI 训练重定向（redirects_for_ai_training）。Pro/Business 起。 */
    val aiTrainingRedirect: Boolean = false,
    /** 面向 Agent 的 Markdown（content_converter）。Pro/Business 起。 */
    val markdownForAgents: Boolean = false,
    /** 上面两项各自读到且可改才显示，否则隐藏对应开关。 */
    val aiTrainingRedirectAvailable: Boolean = false,
    val markdownForAgentsAvailable: Boolean = false,
    // 机器人管控（全套餐可用，但需 bot-management.read）
    val aiBotsProtection: String = "disabled",
    val crawlerProtection: Boolean = false,
    val contentBotsProtection: Boolean = false,
    val robotsLicense: Boolean = false,
    val managedRobotsTxt: Boolean = false,
    val botConfigLoaded: Boolean = false,
    val canWriteBots: Boolean = false,
    val isLoading: Boolean = false,
    val isPurging: Boolean = false,
    val isTogglingPause: Boolean = false,
    val missingScope: Boolean = false,
    val canWrite: Boolean = false,
    val canPurge: Boolean = false,
    val canPause: Boolean = false,
) {
    /** 把接口返回的机器人配置摊到界面状态上。未知取值按最保守的「放行 / 关闭」显示。 */
    fun applyBotConfig(cfg: BotManagementConfig) = copy(
        aiBotsProtection = cfg.aiBotsProtection ?: "disabled",
        crawlerProtection = cfg.crawlerProtection == "enabled",
        contentBotsProtection = cfg.contentBotsProtection == "block",
        robotsLicense = cfg.cfRobotsVariant == "policy_only",
        managedRobotsTxt = cfg.isRobotsTxtManaged == true,
        botConfigLoaded = true,
    )
}

@HiltViewModel
class ZoneSettingsViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repository: ZoneSettingsRepository,
    private val zoneRepository: ZoneRepository,
    private val accountStore: AccountStore,
    authRepository: AuthRepository,
) : ViewModel() {

    private val zoneId: String = checkNotNull(savedStateHandle["zoneId"])
    private val hasRead = authRepository.hasScope(Scopes.ZONE_SETTINGS_READ)
    private val canWrite = authRepository.hasScope(Scopes.ZONE_SETTINGS_WRITE)
    private val canPurge = authRepository.hasScope(Scopes.CACHE_PURGE)

    // 机器人管控是另一条权限链路（bot-management.*），与 zone-settings.* 无关：
    // 只有 zone-settings.read 时这组隐藏，只有 bot-management.read 时这组照常显示
    private val canReadBots = authRepository.hasScope(Scopes.BOT_MANAGEMENT_READ)
    private val canWriteBots = authRepository.hasScope(Scopes.BOT_MANAGEMENT_WRITE)

    // 暂停走域名本身（zone.read/.write），与 zone-settings.* 那条链路的权限无关：
    // 没有 zone-settings.read 时本页只剩这一个开关，也要照常可用
    private val canPause = authRepository.hasScope(Scopes.ZONE_WRITE)

    private val _uiState = MutableStateFlow(
        ZoneSettingsUiState(
            zoneName = savedStateHandle.get<String>("zoneName").orEmpty(),
            isLoading = hasRead,
            missingScope = !hasRead,
            canWrite = canWrite,
            canPurge = canPurge,
            canPause = canPause,
            canWriteBots = canWriteBots,
        ),
    )
    val uiState: StateFlow<ZoneSettingsUiState> = _uiState.asStateFlow()

    private val eventChannel = Channel<ZoneSettingsEvent>(Channel.BUFFERED)
    val events: Flow<ZoneSettingsEvent> = eventChannel.receiveAsFlow()

    init {
        if (hasRead) load()
        if (canReadBots) loadBotConfig()
        // 暂停态读缓存（Room 单一可信源），再拉一次网络校准
        viewModelScope.launch {
            zoneRepository.observeZone(zoneId).filterNotNull().collect { zone ->
                _uiState.update {
                    it.copy(
                        paused = zone.isPaused,
                        zoneName = it.zoneName.ifBlank { zone.name },
                    )
                }
            }
        }
        viewModelScope.launch {
            val accountId = accountStore.selectedAccountId.value ?: return@launch
            runCatching { zoneRepository.refreshZone(accountId, zoneId) }
        }
    }

    /**
     * 暂停 / 恢复 Cloudflare 代理。影响面大（WAF、缓存、源站 IP 隐藏一并失效），
     * 由界面先弹确认对话框，这里只负责下发。
     */
    fun setPaused(on: Boolean) {
        if (!canPause || _uiState.value.isTogglingPause) return
        viewModelScope.launch {
            _uiState.update { it.copy(isTogglingPause = true) }
            try {
                accountStore.ensureLoaded()
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                val zone = zoneRepository.setPaused(accountId, zoneId, on)
                _uiState.update { it.copy(paused = zone.isPaused) }
            } catch (e: Exception) {
                eventChannel.send(ZoneSettingsEvent.Error(e.message))
            } finally {
                _uiState.update { it.copy(isTogglingPause = false) }
            }
        }
    }

    fun load() {
        if (!hasRead) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            try {
                val dev = async { runCatching { repository.getSetting(zoneId, "development_mode") }.getOrNull() }
                val sec = async { runCatching { repository.getSetting(zoneId, "security_level") }.getOrNull() }
                // 这两项 Pro 起。免费套餐也读得到值，只是 editable=false、一写就 400——
                // 读不到或不可改都隐藏对应开关，而不是给用户一个永远打不开的开关。
                val aiRedirect = async {
                    runCatching { repository.getSettingIfEditable(zoneId, "redirects_for_ai_training") }.getOrNull()
                }
                val converter = async {
                    runCatching { repository.getSettingIfEditable(zoneId, "content_converter") }.getOrNull()
                }
                val aiRedirectValue = aiRedirect.await()
                val converterValue = converter.await()
                _uiState.update {
                    it.copy(
                        developmentMode = dev.await() == "on",
                        underAttack = sec.await() == "under_attack",
                        aiTrainingRedirect = aiRedirectValue == "on",
                        markdownForAgents = converterValue == "on",
                        aiTrainingRedirectAvailable = aiRedirectValue != null,
                        markdownForAgentsAvailable = converterValue != null,
                    )
                }
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
        }
    }

    fun setDevelopmentMode(on: Boolean) {
        if (!canWrite) return
        _uiState.update { it.copy(developmentMode = on) }
        viewModelScope.launch {
            runCatching { repository.setSetting(zoneId, "development_mode", if (on) "on" else "off") }
                .onFailure { eventChannel.send(ZoneSettingsEvent.Error(it.message)); load() }
        }
    }

    fun setUnderAttack(on: Boolean) {
        if (!canWrite) return
        _uiState.update { it.copy(underAttack = on) }
        viewModelScope.launch {
            runCatching { repository.setSetting(zoneId, "security_level", if (on) "under_attack" else "medium") }
                .onFailure { eventChannel.send(ZoneSettingsEvent.Error(it.message)); load() }
        }
    }

    /** 读机器人管控。四种套餐形态共用 base_config，任何套餐都能读到。 */
    fun loadBotConfig() {
        if (!canReadBots) return
        viewModelScope.launch {
            runCatching { repository.getBotManagement(zoneId) }
                .onSuccess { cfg -> _uiState.update { it.applyBotConfig(cfg) } }
        }
    }

    /**
     * 写单个字段。PUT 合并语义，只发改动那一项，不会动 sbfm_* 等套餐专属配置。
     * 失败后回读，纠正界面上的乐观值。
     */
    private fun updateBotConfig(optimistic: ZoneSettingsUiState.() -> ZoneSettingsUiState, update: BotManagementUpdate) {
        if (!canWriteBots) return
        _uiState.update(optimistic)
        viewModelScope.launch {
            runCatching { repository.setBotManagement(zoneId, update) }
                .onSuccess { cfg -> _uiState.update { it.applyBotConfig(cfg) } }
                .onFailure { eventChannel.send(ZoneSettingsEvent.Error(it.message)); loadBotConfig() }
        }
    }

    fun setAiBotsProtection(mode: String) =
        updateBotConfig({ copy(aiBotsProtection = mode) }, BotManagementUpdate(aiBotsProtection = mode))

    fun setCrawlerProtection(on: Boolean) =
        updateBotConfig(
            { copy(crawlerProtection = on) },
            BotManagementUpdate(crawlerProtection = if (on) "enabled" else "disabled"),
        )

    fun setContentBotsProtection(on: Boolean) =
        updateBotConfig(
            { copy(contentBotsProtection = on) },
            BotManagementUpdate(contentBotsProtection = if (on) "block" else "disabled"),
        )

    fun setRobotsLicense(on: Boolean) =
        updateBotConfig(
            { copy(robotsLicense = on) },
            BotManagementUpdate(cfRobotsVariant = if (on) "policy_only" else "off"),
        )

    fun setManagedRobotsTxt(on: Boolean) =
        updateBotConfig(
            { copy(managedRobotsTxt = on) },
            BotManagementUpdate(isRobotsTxtManaged = on),
        )

    fun setAiTrainingRedirect(on: Boolean) {
        if (!canWrite) return
        _uiState.update { it.copy(aiTrainingRedirect = on) }
        viewModelScope.launch {
            runCatching { repository.setSetting(zoneId, "redirects_for_ai_training", if (on) "on" else "off") }
                .onFailure { eventChannel.send(ZoneSettingsEvent.Error(it.message)); load() }
        }
    }

    fun setMarkdownForAgents(on: Boolean) {
        if (!canWrite) return
        _uiState.update { it.copy(markdownForAgents = on) }
        viewModelScope.launch {
            runCatching { repository.setSetting(zoneId, "content_converter", if (on) "on" else "off") }
                .onFailure { eventChannel.send(ZoneSettingsEvent.Error(it.message)); load() }
        }
    }

    fun purgeCache() {
        if (!canPurge) return
        viewModelScope.launch {
            _uiState.update { it.copy(isPurging = true) }
            try {
                repository.purgeAllCache(zoneId)
                eventChannel.send(ZoneSettingsEvent.Purged)
            } catch (e: Exception) {
                eventChannel.send(ZoneSettingsEvent.Error(e.message))
            } finally {
                _uiState.update { it.copy(isPurging = false) }
            }
        }
    }

    /** 按 URL 清理缓存。调用方负责拆行/校验，这里只下发（单次最多 30 个）。 */
    fun purgeFiles(urls: List<String>) {
        if (!canPurge || urls.isEmpty()) return
        viewModelScope.launch {
            _uiState.update { it.copy(isPurging = true) }
            try {
                repository.purgeFiles(zoneId, urls.take(MAX_PURGE_URLS))
                eventChannel.send(ZoneSettingsEvent.Purged)
            } catch (e: Exception) {
                eventChannel.send(ZoneSettingsEvent.Error(e.message))
            } finally {
                _uiState.update { it.copy(isPurging = false) }
            }
        }
    }

    companion object {
        const val MAX_PURGE_URLS = 30
    }
}
