package jiamin.chen.orangecloud.ui.waf

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.data.model.WafRule
import jiamin.chen.orangecloud.data.model.WafRuleCreate
import jiamin.chen.orangecloud.data.repository.SecurityRepository
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface WafEvent {
    data object Saved : WafEvent
    data object Deleted : WafEvent
    data class Error(val message: String?) : WafEvent
}

data class WafUiState(
    val zoneName: String = "",
    val rules: List<WafRule> = emptyList(),
    val rulesetId: String? = null,
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val hasError: Boolean = false,
    val missingScope: Boolean = false,
    val canWrite: Boolean = false,
    /** 启停请求在途的规则 id，期间禁用其开关防连点。 */
    val togglingIds: Set<String> = emptySet(),
)

@HiltViewModel
class WafRulesViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val securityRepository: SecurityRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    private val zoneId: String = checkNotNull(savedStateHandle["zoneId"])
    private val hasRead = authRepository.hasScope(Scopes.WAF_READ)
    private val canWrite = authRepository.hasScope(Scopes.WAF_WRITE)

    private val _uiState = MutableStateFlow(
        WafUiState(
            zoneName = savedStateHandle.get<String>("zoneName").orEmpty(),
            isLoading = hasRead,
            missingScope = !hasRead,
            canWrite = canWrite,
        ),
    )
    val uiState: StateFlow<WafUiState> = _uiState.asStateFlow()

    private val eventChannel = Channel<WafEvent>(Channel.BUFFERED)
    val events: Flow<WafEvent> = eventChannel.receiveAsFlow()

    init {
        if (hasRead) load()
    }

    fun load() {
        if (!hasRead) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, hasError = false) }
            try {
                val ruleset = securityRepository.customRuleset(zoneId)
                _uiState.update { it.copy(rules = ruleset?.rules.orEmpty(), rulesetId = ruleset?.id) }
            } catch (e: Exception) {
                _uiState.update { it.copy(hasError = true) }
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
        }
    }

    fun toggle(rule: WafRule, enabled: Boolean) {
        val rulesetId = _uiState.value.rulesetId ?: return
        if (!canWrite || rule.id in _uiState.value.togglingIds) return
        // 乐观更新：开关是受控组件，不先改状态就要等网络往返才动，失败又静默弹回，用户看来就是「点了没反应」
        _uiState.update { s ->
            s.copy(
                rules = s.rules.map { if (it.id == rule.id) it.copy(enabled = enabled) else it },
                togglingIds = s.togglingIds + rule.id,
            )
        }
        viewModelScope.launch {
            try {
                val updated = securityRepository.setRuleEnabled(zoneId, rulesetId, rule, enabled)
                _uiState.update { it.copy(rules = updated.rules.orEmpty(), rulesetId = updated.id) }
            } catch (e: Exception) {
                _uiState.update { s ->
                    s.copy(rules = s.rules.map { if (it.id == rule.id) it.copy(enabled = rule.enabled) else it })
                }
                eventChannel.send(WafEvent.Error(e.message))
            } finally {
                _uiState.update { it.copy(togglingIds = it.togglingIds - rule.id) }
            }
        }
    }

    /** 新建规则：Zone 没有规则集时先 PUT entrypoint 建集，否则 POST 追加。 */
    fun addRule(action: String, expression: String, description: String, enabled: Boolean) {
        if (!canWrite) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true) }
            try {
                val rule = WafRuleCreate(action, expression.trim(), description.trim().ifBlank { null }, enabled)
                val rulesetId = _uiState.value.rulesetId
                val updated = if (rulesetId == null) {
                    securityRepository.createRuleset(zoneId, rule)
                } else {
                    securityRepository.addRule(zoneId, rulesetId, rule)
                }
                _uiState.update { it.copy(rules = updated.rules.orEmpty(), rulesetId = updated.id) }
                eventChannel.send(WafEvent.Saved)
            } catch (e: Exception) {
                eventChannel.send(WafEvent.Error(e.message))
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    /** 编辑既有规则（整条 PATCH：动作 / 表达式 / 名称 / 启用）。 */
    fun updateRule(ruleId: String, action: String, expression: String, description: String, enabled: Boolean) {
        val rulesetId = _uiState.value.rulesetId ?: return
        if (!canWrite) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true) }
            try {
                val rule = WafRuleCreate(action, expression.trim(), description.trim().ifBlank { null }, enabled)
                val updated = securityRepository.updateRule(zoneId, rulesetId, ruleId, rule)
                _uiState.update { it.copy(rules = updated.rules.orEmpty(), rulesetId = updated.id) }
                eventChannel.send(WafEvent.Saved)
            } catch (e: Exception) {
                eventChannel.send(WafEvent.Error(e.message))
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    fun deleteRule(rule: WafRule) {
        val rulesetId = _uiState.value.rulesetId ?: return
        if (!canWrite) return
        viewModelScope.launch {
            try {
                securityRepository.deleteRule(zoneId, rulesetId, rule.id)
                _uiState.update { it.copy(rules = it.rules.filterNot { r -> r.id == rule.id }) }
                eventChannel.send(WafEvent.Deleted)
            } catch (e: Exception) {
                eventChannel.send(WafEvent.Error(e.message))
                load()
            }
        }
    }
}
