package jiamin.chen.orangecloud.ui.workers

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.core.system.TailNotifier
import jiamin.chen.orangecloud.data.model.TailTraceItem
import jiamin.chen.orangecloud.data.model.tailDisplayText
import jiamin.chen.orangecloud.data.repository.AccountStore
import jiamin.chen.orangecloud.data.repository.WorkerTailRepository
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject
import jiamin.chen.orangecloud.core.di.ApplicationScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope

sealed interface TailConnState {
    data object Idle : TailConnState
    data object Connecting : TailConnState
    data object Connected : TailConnState
    data class Disconnected(val reason: String?) : TailConnState
}

data class TailLogLine(
    val id: Long,
    val timestampMs: Long,
    val level: String,   // event | log | info | warn | error | debug | exception
    val text: String,
)

/**
 * 日志级别过滤档位。ERROR 档同时收 exception（异常与错误在控制台同色同义）。
 * 过滤只作用于展示，原始 buffer 永不裁剪。
 */
enum class TailLevelFilter(val id: String) {
    ALL("all"),
    EVENT("event"),
    LOG("log"),
    DEBUG("debug"),
    INFO("info"),
    WARN("warn"),
    ERROR("error"),
    ;

    fun matches(level: String): Boolean = when (this) {
        ALL -> true
        ERROR -> level.equals("error", ignoreCase = true) || level.equals("exception", ignoreCase = true)
        else -> level.equals(id, ignoreCase = true)
    }
}

/**
 * Workers 实时日志编排（对应 iOS WorkerTailViewModel）：
 * 创建 tail session → 连 WebSocket → 消费事件流；断线自动重建一次，退出销毁 tail。
 * Live Updates 通知（Android 16 实况通知）留作后续增量。
 */
@HiltViewModel
class WorkerTailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    accountStore: AccountStore,
    private val tailRepository: WorkerTailRepository,
    private val tailNotifier: TailNotifier,
    authRepository: AuthRepository,
    @ApplicationScope private val externalScope: CoroutineScope,
) : ViewModel() {

    val scriptName: String = checkNotNull(savedStateHandle["scriptName"])
    private val accountId: String? = accountStore.selectedAccountId.value
    val missingScope: Boolean = !authRepository.hasScope(Scopes.WORKERS_TAIL_READ)

    private val _state = MutableStateFlow<TailConnState>(TailConnState.Idle)
    val state: StateFlow<TailConnState> = _state.asStateFlow()

    /** 全量接收 buffer（只受 MAX_LINES 环形封顶影响，过滤条件变化不丢历史）。 */
    private val _lines = MutableStateFlow<List<TailLogLine>>(emptyList())
    val lines: StateFlow<List<TailLogLine>> = _lines.asStateFlow()

    private val _query = MutableStateFlow("")
    val query: StateFlow<String> = _query.asStateFlow()

    private val _levelFilter = MutableStateFlow(TailLevelFilter.ALL)
    val levelFilter: StateFlow<TailLevelFilter> = _levelFilter.asStateFlow()

    /** 展示用派生结果：关键词（不区分大小写，匹配正文）+ 级别。 */
    val visibleLines: StateFlow<List<TailLogLine>> =
        combine(_lines, _query, _levelFilter) { all, rawQuery, level ->
            val keyword = rawQuery.trim()
            if (keyword.isEmpty() && level == TailLevelFilter.ALL) {
                all
            } else {
                all.filter { line ->
                    level.matches(line.level) &&
                        (keyword.isEmpty() || line.text.contains(keyword, ignoreCase = true))
                }
            }
        }.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    // 暂停 = 冻结视图（停止自动滚到底），事件照常入 buffer，恢复后能看到这段日志
    private val _paused = MutableStateFlow(false)
    val paused: StateFlow<Boolean> = _paused.asStateFlow()

    /** 暂停期间累积的新行数，用于提示「暂停期间新增 N 条」。 */
    private val _pausedNewCount = MutableStateFlow(0)
    val pausedNewCount: StateFlow<Int> = _pausedNewCount.asStateFlow()

    private var collectJob: Job? = null
    private var tailId: String? = null
    private var userStopped = false
    private var didReconnect = false
    private var lineId = 0L
    private var eventCount = 0
    private var lastNotifyMs = 0L

    init {
        if (!missingScope && accountId != null) start()
    }

    fun start() {
        viewModelScope.launch {
            teardown()
            userStopped = false
            didReconnect = false
            connect()
        }
    }

    fun stop() {
        viewModelScope.launch {
            userStopped = true
            teardown()
            tailNotifier.cancel()
            _state.value = TailConnState.Idle
        }
    }

    fun clear() {
        _lines.value = emptyList()
        _pausedNewCount.value = 0
    }

    /** 切换暂停；恢复时清零计数（视图会随之自动滚到底）。 */
    fun togglePause() {
        val nowPaused = !_paused.value
        _paused.value = nowPaused
        if (!nowPaused) _pausedNewCount.value = 0
    }

    fun updateQuery(text: String) {
        _query.value = text
    }

    fun setLevelFilter(filter: TailLevelFilter) {
        _levelFilter.value = filter
    }

    private suspend fun connect() {
        if (accountId == null) {
            _state.value = TailConnState.Disconnected(null)
            return
        }
        _state.value = TailConnState.Connecting
        try {
            val session = tailRepository.createTail(accountId, scriptName)
            tailId = session.id
            val socket = tailRepository.makeSocket(session)
            _state.value = TailConnState.Connected
            tailNotifier.update(scriptName, eventCount, "", connected = true)
            collectJob = viewModelScope.launch {
                try {
                    socket.events().collect { handle(it) }
                    streamEnded(null)
                } catch (e: CancellationException) {
                    throw e   // 离开页面 / 主动停止：不是流故障，别走重连
                } catch (e: Exception) {
                    streamEnded(e)
                }
            }
        } catch (e: Exception) {
            _state.value = TailConnState.Disconnected(e.message)
        }
    }

    /** 流结束：用户主动停止则忽略；否则自动重建一次，再失败转断开态。 */
    private fun streamEnded(error: Throwable?) {
        if (userStopped) return
        if (!didReconnect) {
            didReconnect = true
            viewModelScope.launch {
                teardown()
                connect()
            }
        } else {
            _state.value = TailConnState.Disconnected(error?.message)
            tailNotifier.update(scriptName, eventCount, "", connected = false)
        }
    }

    private suspend fun teardown() {
        collectJob?.cancel()
        collectJob = null
        val id = tailId
        val acct = accountId
        tailId = null
        if (id != null && acct != null) {
            runCatching { tailRepository.deleteTail(acct, scriptName, id) }
        }
    }

    private fun handle(item: TailTraceItem) {
        val eventMs = item.eventTimestamp ?: System.currentTimeMillis()
        val newLines = buildList {
            val request = item.event?.request
            val cron = item.event?.cron
            if (request != null) {
                add(line(eventMs, "event", "${request.method ?: "GET"} ${request.url.orEmpty()} → ${item.outcome ?: "?"}"))
            } else if (cron != null) {
                add(line(eventMs, "event", "cron $cron → ${item.outcome ?: "?"}"))
            }
            item.logs?.forEach { log ->
                val text = log.message?.joinToString(" ") { it.tailDisplayText() }.orEmpty()
                add(line(log.timestamp ?: eventMs, log.level, text))
            }
            item.exceptions?.forEach { ex ->
                add(line(ex.timestamp ?: eventMs, "exception", listOfNotNull(ex.name, ex.message).joinToString(": ")))
            }
        }
        if (newLines.isEmpty()) return
        _lines.update { current ->
            val all = current + newLines
            if (all.size > MAX_LINES) all.takeLast(MAX_LINES) else all
        }
        if (_paused.value) _pausedNewCount.update { it + newLines.size }
        eventCount += newLines.size
        val now = System.currentTimeMillis()
        if (now - lastNotifyMs > 1000) {   // 节流：最多每秒更新一次通知
            lastNotifyMs = now
            tailNotifier.update(scriptName, eventCount, newLines.last().text, connected = true)
        }
    }

    override fun onCleared() {
        super.onCleared()
        tailNotifier.cancel()
        // viewModelScope 已经没了，DELETE tail 只能交给应用级 scope：
        // 以前离开页面从不删服务端 tail 会话，反复进出会撞上 CF 每脚本并发 tail 上限、之后 createTail 一直失败。
        val id = tailId ?: return
        val acct = accountId ?: return
        tailId = null
        externalScope.launch { runCatching { tailRepository.deleteTail(acct, scriptName, id) } }
    }

    private fun line(timestampMs: Long, level: String, text: String) =
        TailLogLine(id = lineId++, timestampMs = timestampMs, level = level, text = text)

    companion object {
        private const val MAX_LINES = 1000
    }
}
