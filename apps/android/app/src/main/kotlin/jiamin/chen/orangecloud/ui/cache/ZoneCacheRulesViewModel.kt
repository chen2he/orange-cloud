package jiamin.chen.orangecloud.ui.cache

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.core.design.RuleValidation
import jiamin.chen.orangecloud.core.network.cfDocumentationUrl
import jiamin.chen.orangecloud.data.model.CacheActionParameters
import jiamin.chen.orangecloud.data.model.CacheRule
import jiamin.chen.orangecloud.data.model.CacheRuleCreate
import jiamin.chen.orangecloud.data.model.CacheResponseRule
import jiamin.chen.orangecloud.data.model.CacheResponseRuleset
import jiamin.chen.orangecloud.data.model.CacheRuleset
import jiamin.chen.orangecloud.data.repository.CacheRuleRepository
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

sealed interface CacheEvent {
    data object Saved : CacheEvent
    data object Deleted : CacheEvent
    data class Error(val message: String?, val documentationUrl: String? = null) : CacheEvent
}

data class ZoneCacheUiState(
    val zoneName: String = "",
    val ruleset: CacheRuleset? = null,
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val loaded: Boolean = false,
    val missingScope: Boolean = false,
    val canWrite: Boolean = false,
    val togglingRuleId: String? = null,
    /** 编辑器里「校验」（dry_run）的结果；打开 / 关闭编辑器时清空。 */
    val validation: RuleValidation? = null,
    // —— 缓存响应规则（http_response_cache_settings）：只读列表 + 启停 + 删除 ——
    val responseRuleset: CacheResponseRuleset? = null,
    /** 读取失败（如该阶段尚未对此域名开放）时整段隐藏，而不是报错。 */
    val responseAvailable: Boolean = false,
    val togglingResponseRuleId: String? = null,
) {
    val rules: List<CacheRule> get() = ruleset?.rules.orEmpty()
    val responseRules: List<CacheResponseRule> get() = responseRuleset?.rules.orEmpty()
}

@HiltViewModel
class ZoneCacheRulesViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repository: CacheRuleRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    private val zoneId: String = checkNotNull(savedStateHandle["zoneId"])
    private val hasRead = authRepository.hasScope(Scopes.CACHE_RULES_READ)
    private val canWrite = authRepository.hasScope(Scopes.CACHE_RULES_WRITE)

    private val _uiState = MutableStateFlow(
        ZoneCacheUiState(
            zoneName = savedStateHandle.get<String>("zoneName").orEmpty(),
            isLoading = hasRead,
            missingScope = !hasRead,
            canWrite = canWrite,
        ),
    )
    val uiState: StateFlow<ZoneCacheUiState> = _uiState.asStateFlow()

    private val eventChannel = Channel<CacheEvent>(Channel.BUFFERED)
    val events: Flow<CacheEvent> = eventChannel.receiveAsFlow()

    init {
        if (hasRead) load()
    }

    fun load() {
        if (!hasRead) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            try {
                // 响应规则是附加段：并行读，失败只隐藏该段，不影响请求阶段规则
                val response = async { runCatching { repository.responseRuleset(zoneId) } }
                val ruleset = repository.ruleset(zoneId)
                _uiState.update { it.copy(ruleset = ruleset, loaded = true) }
                val responseResult = response.await()
                _uiState.update {
                    it.copy(
                        responseRuleset = responseResult.getOrNull(),
                        responseAvailable = responseResult.isSuccess,
                    )
                }
            } catch (e: Exception) {
                eventChannel.send(CacheEvent.Error(e.message, e.cfDocumentationUrl))
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
        }
    }

    /** 启停一条缓存响应规则。 */
    fun toggleResponse(rule: CacheResponseRule, enabled: Boolean) {
        val rulesetId = _uiState.value.responseRuleset?.id ?: return
        if (!canWrite || _uiState.value.togglingResponseRuleId != null) return
        _uiState.update { it.copy(togglingResponseRuleId = rule.id) }
        viewModelScope.launch {
            try {
                val updated = repository.setResponseRuleEnabled(zoneId, rulesetId, rule.id, enabled)
                _uiState.update { it.copy(responseRuleset = updated) }
            } catch (e: Exception) {
                eventChannel.send(CacheEvent.Error(e.message, e.cfDocumentationUrl))
                load()
            } finally {
                _uiState.update { it.copy(togglingResponseRuleId = null) }
            }
        }
    }

    /** 删除一条缓存响应规则，成功后回读该阶段。 */
    fun deleteResponse(rule: CacheResponseRule) {
        val rulesetId = _uiState.value.responseRuleset?.id ?: return
        if (!canWrite) return
        viewModelScope.launch {
            try {
                repository.deleteRule(zoneId, rulesetId, rule.id)
                val refreshed = repository.responseRuleset(zoneId)
                _uiState.update { it.copy(responseRuleset = refreshed) }
                eventChannel.send(CacheEvent.Deleted)
            } catch (e: Exception) {
                eventChannel.send(CacheEvent.Error(e.message, e.cfDocumentationUrl))
                load()
            }
        }
    }

    fun clearValidation() = _uiState.update { it.copy(validation = null) }

    /**
     * 校验（dry_run）：发与保存完全相同的请求，只校验不落盘。保存流程不受影响。
     */
    fun validate(
        ruleId: String?,
        expression: String,
        description: String?,
        enabled: Boolean,
        params: CacheActionParameters,
    ) {
        if (!canWrite || _uiState.value.validation == RuleValidation.Running) return
        _uiState.update { it.copy(validation = RuleValidation.Running) }
        viewModelScope.launch {
            val result = runCatching {
                repository.validateRule(
                    zoneId,
                    _uiState.value.ruleset?.id,
                    ruleId,
                    draft(expression, description, enabled, params),
                )
            }
            _uiState.update {
                it.copy(
                    validation = result.fold(
                        onSuccess = { RuleValidation.Passed },
                        onFailure = { e -> RuleValidation.Failed(e.message) },
                    ),
                )
            }
        }
    }

    private fun draft(expression: String, description: String?, enabled: Boolean, params: CacheActionParameters) =
        CacheRuleCreate(
            action = "set_cache_settings",
            expression = expression,
            description = description?.takeIf { it.isNotBlank() },
            enabled = enabled,
            actionParameters = params,
        )

    fun toggle(rule: CacheRule, enabled: Boolean) {
        val rulesetId = _uiState.value.ruleset?.id ?: return
        if (!canWrite || _uiState.value.togglingRuleId != null) return
        _uiState.update { it.copy(togglingRuleId = rule.id) }
        viewModelScope.launch {
            try {
                val updated = repository.setRuleEnabled(zoneId, rulesetId, rule.id, enabled)
                _uiState.update { it.copy(ruleset = updated) }
            } catch (e: Exception) {
                eventChannel.send(CacheEvent.Error(e.message, e.cfDocumentationUrl))
                load()
            } finally {
                _uiState.update { it.copy(togglingRuleId = null) }
            }
        }
    }

    /** 新建（ruleId == null）或更新单条规则。 */
    fun save(
        ruleId: String?,
        expression: String,
        description: String?,
        enabled: Boolean,
        params: CacheActionParameters,
    ) {
        if (!canWrite || _uiState.value.isSaving) return
        _uiState.update { it.copy(isSaving = true) }
        viewModelScope.launch {
            try {
                val draft = draft(expression, description, enabled, params)
                val rulesetId = _uiState.value.ruleset?.id
                val updated = when {
                    ruleId != null && rulesetId != null -> repository.updateRule(zoneId, rulesetId, ruleId, draft)
                    rulesetId != null -> repository.addRule(zoneId, rulesetId, draft)
                    else -> repository.createEntrypoint(zoneId, draft)
                }
                _uiState.update { it.copy(ruleset = updated) }
                eventChannel.send(CacheEvent.Saved)
            } catch (e: Exception) {
                eventChannel.send(CacheEvent.Error(e.message, e.cfDocumentationUrl))
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    fun delete(rule: CacheRule) {
        val rulesetId = _uiState.value.ruleset?.id ?: return
        if (!canWrite) return
        viewModelScope.launch {
            try {
                repository.deleteRule(zoneId, rulesetId, rule.id)
                val refreshed = repository.ruleset(zoneId)
                _uiState.update { it.copy(ruleset = refreshed) }
                eventChannel.send(CacheEvent.Deleted)
            } catch (e: Exception) {
                eventChannel.send(CacheEvent.Error(e.message, e.cfDocumentationUrl))
                load()
            }
        }
    }
}
