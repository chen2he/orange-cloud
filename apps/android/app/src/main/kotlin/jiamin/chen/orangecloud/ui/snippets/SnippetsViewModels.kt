package jiamin.chen.orangecloud.ui.snippets

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.data.model.Snippet
import jiamin.chen.orangecloud.data.model.SnippetRule
import jiamin.chen.orangecloud.data.model.SnippetRuleInput
import jiamin.chen.orangecloud.data.model.toInput
import jiamin.chen.orangecloud.data.repository.SnippetRepository
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import javax.inject.Inject
import kotlinx.coroutines.CancellationException

// MARK: - 列表

data class SnippetsUiState(
    val zoneName: String = "",
    val snippets: List<Snippet> = emptyList(),
    val isLoading: Boolean = false,
    val hasError: Boolean = false,
    val missingScope: Boolean = false,
    val canWrite: Boolean = false,
)

@HiltViewModel
class SnippetsViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val snippetRepository: SnippetRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    private val zoneId: String = checkNotNull(savedStateHandle["zoneId"])
    private val hasRead = authRepository.hasScope(Scopes.SNIPPETS_READ)
    private val canWrite = authRepository.hasScope(Scopes.SNIPPETS_WRITE)

    private val _uiState = MutableStateFlow(
        SnippetsUiState(
            zoneName = savedStateHandle.get<String>("zoneName").orEmpty(),
            isLoading = hasRead,
            missingScope = !hasRead,
            canWrite = canWrite,
        ),
    )
    val uiState: StateFlow<SnippetsUiState> = _uiState.asStateFlow()

    init {
        if (hasRead) load()
    }

    fun load() {
        if (!hasRead) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, hasError = false) }
            try {
                _uiState.update { it.copy(snippets = snippetRepository.list(zoneId)) }
            } catch (e: Exception) {
                _uiState.update { it.copy(hasError = true) }
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
        }
    }
}

// MARK: - 编辑器

sealed interface SnippetEditEvent {
    /** 远端正文没拉到，拒绝保存（否则会把空正文写上去） */
    data object ContentUnavailable : SnippetEditEvent
    data object Saved : SnippetEditEvent
    data object Deleted : SnippetEditEvent
    /** 触发规则写入成功：只提示，不关页 */
    data object RuleSaved : SnippetEditEvent
    /** 规则在别处已被删除，本次改动未提交 */
    data object RuleGone : SnippetEditEvent
    data class Error(val message: String?) : SnippetEditEvent
}

data class SnippetEditUiState(
    val name: String = "",
    val code: String = "",
    val isNew: Boolean = false,
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val canWrite: Boolean = false,
    /** 远端正文拉取失败：编辑器里是空的，绝不能拿这个空正文去覆盖线上 snippet */
    val loadFailed: Boolean = false,
)

@HiltViewModel
class SnippetEditorViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val snippetRepository: SnippetRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    private val zoneId: String = checkNotNull(savedStateHandle["zoneId"])
    private val initialName: String = savedStateHandle.get<String>("name").orEmpty()
    private val canWrite = authRepository.hasScope(Scopes.SNIPPETS_WRITE)

    private val _uiState = MutableStateFlow(
        SnippetEditUiState(
            name = initialName,
            isNew = initialName.isEmpty(),
            isLoading = initialName.isNotEmpty(),
            canWrite = canWrite,
        ),
    )
    val uiState: StateFlow<SnippetEditUiState> = _uiState.asStateFlow()

    private val eventChannel = Channel<SnippetEditEvent>(Channel.BUFFERED)
    val events: Flow<SnippetEditEvent> = eventChannel.receiveAsFlow()

    /** zone 下「全部」规则：整组回写要靠它，别只留本 snippet 的（漏传即删） */
    private var allRules: List<SnippetRule> = emptyList()

    private val _rules = MutableStateFlow<List<SnippetRule>>(emptyList())
    val rules: StateFlow<List<SnippetRule>> = _rules.asStateFlow()

    private val ruleWriteMutex = Mutex()

    /** 正在回写的规则 key（行内转圈用），null = 空闲 */
    private val _ruleBusyKey = MutableStateFlow<String?>(null)
    val ruleBusyKey: StateFlow<String?> = _ruleBusyKey.asStateFlow()

    init {
        if (initialName.isNotEmpty()) {
            loadContent()
            viewModelScope.launch { reloadRules() }
        }
    }

    /** 拉正文。失败置 loadFailed（保存被拒），用户可重试。 */
    fun loadContent() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, loadFailed = false) }
            val result = runCatching { snippetRepository.content(zoneId, initialName) }
            result.exceptionOrNull()?.let { if (it is CancellationException) throw it }
            _uiState.update {
                it.copy(code = result.getOrNull() ?: it.code, isLoading = false, loadFailed = result.isFailure)
            }
        }
    }

    private suspend fun reloadRules() {
        val all = runCatching { snippetRepository.rules(zoneId) }.getOrNull() ?: return
        allRules = all
        _rules.value = all.filter { it.snippetName == _uiState.value.name }
    }

    /** 规则身份：服务端有 id 用 id，否则用 snippet_name + 表达式兜底（对齐 iOS） */
    private fun key(rule: SnippetRule): String = rule.id ?: "${rule.snippetName}|${rule.expression}"

    fun ruleKey(rule: SnippetRule): String = key(rule)

    /**
     * 整组回写：先取一次服务端最新全量，避免把表单停留期间别处的改动抹掉；
     * 取不到就退回本地缓存——宁可用旧的整组，也不能写出「半份」规则。
     */
    private suspend fun latestRules(): List<SnippetRule> =
        runCatching { snippetRepository.rules(zoneId) }.getOrNull()?.also { allRules = it } ?: allRules

    /**
     * 整组回写串行化：并发的两次「读全量→改一条→PUT 全量」会互相覆盖，
     * 所以排队而不是丢弃——丢弃等于用户的改动无声消失。
     */
    private fun writeRules(busyKey: String?, build: (List<SnippetRule>) -> List<SnippetRuleInput>?) {
        if (!canWrite) return
        viewModelScope.launch {
            ruleWriteMutex.withLock {
                _ruleBusyKey.value = busyKey ?: RULE_BUSY_FORM
                try {
                    val inputs = build(latestRules())
                    if (inputs == null) {
                        // 规则在别处已被删掉：整组回写会把它「复活」，这里直接刷新让用户重来
                        reloadRules()
                        eventChannel.send(SnippetEditEvent.RuleGone)
                        return@withLock
                    }
                    snippetRepository.putRules(zoneId, inputs)
                    reloadRules()
                    eventChannel.send(SnippetEditEvent.RuleSaved)
                } catch (e: Exception) {
                    eventChannel.send(SnippetEditEvent.Error(e.message))
                } finally {
                    _ruleBusyKey.value = null
                }
            }
        }
    }

    fun addRule(expression: String, description: String?, enabled: Boolean) {
        val name = _uiState.value.name.trim()
        if (name.isEmpty() || expression.isBlank()) return
        writeRules(null) { latest ->
            latest.map { it.toInput() } + SnippetRuleInput(name, expression.trim(), description, enabled)
        }
    }

    fun updateRule(rule: SnippetRule, expression: String, description: String?, enabled: Boolean) {
        if (expression.isBlank()) return
        val target = key(rule)
        writeRules(null) { latest ->
            if (latest.none { key(it) == target }) return@writeRules null
            latest.map { current ->
                if (key(current) == target) {
                    SnippetRuleInput(current.snippetName, expression.trim(), description, enabled)
                } else {
                    current.toInput()
                }
            }
        }
    }

    fun setRuleEnabled(rule: SnippetRule, enabled: Boolean) {
        val target = key(rule)
        writeRules(target) { latest ->
            if (latest.none { key(it) == target }) return@writeRules null
            latest.map { if (key(it) == target) it.toInput(enabled) else it.toInput() }
        }
    }

    fun deleteRule(rule: SnippetRule) {
        val target = key(rule)
        writeRules(target) { latest -> latest.filter { key(it) != target }.map { it.toInput() } }
    }

    fun updateName(name: String) = _uiState.update { it.copy(name = name) }
    fun updateCode(code: String) = _uiState.update { it.copy(code = code) }

    fun save() {
        val s = _uiState.value
        if (!canWrite || s.name.isBlank()) return
        if (s.loadFailed || s.isLoading) {
            // 弱网下正文没拉到、编辑器一片空白：这时保存等于把线上的边缘 JS 换成空文件
            viewModelScope.launch { eventChannel.send(SnippetEditEvent.ContentUnavailable) }
            return
        }
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true) }
            try {
                snippetRepository.put(zoneId, s.name.trim(), s.code)
                eventChannel.send(SnippetEditEvent.Saved)
            } catch (e: Exception) {
                eventChannel.send(SnippetEditEvent.Error(e.message))
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    fun delete() {
        val s = _uiState.value
        if (!canWrite || s.isNew) return
        viewModelScope.launch {
            try {
                snippetRepository.delete(zoneId, s.name)
                // 同步移除指向它的触发规则（整组回写剩余规则），对齐 iOS
                val latest = latestRules()
                val remaining = latest.filter { it.snippetName != s.name }
                if (remaining.size != latest.size) {
                    runCatching { snippetRepository.putRules(zoneId, remaining.map { it.toInput() }) }
                }
                eventChannel.send(SnippetEditEvent.Deleted)
            } catch (e: Exception) {
                eventChannel.send(SnippetEditEvent.Error(e.message))
            }
        }
    }

    private companion object {
        /** 表单（新增/编辑）写入中的占位 key，与行内 toggle/删除区分 */
        const val RULE_BUSY_FORM = "__form__"
    }
}
