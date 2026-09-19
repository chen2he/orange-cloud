package jiamin.chen.orangecloud.ui.storage

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.data.model.D1Database
import jiamin.chen.orangecloud.data.model.D1QueryResult
import jiamin.chen.orangecloud.data.model.KVKey
import jiamin.chen.orangecloud.data.model.KVNamespace
import jiamin.chen.orangecloud.data.model.R2Bucket
import jiamin.chen.orangecloud.data.model.R2Folder
import jiamin.chen.orangecloud.data.model.R2Object
import jiamin.chen.orangecloud.data.model.D1Column
import jiamin.chen.orangecloud.data.repository.AccountStore
import jiamin.chen.orangecloud.data.repository.StorageRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

// MARK: - 简单列表（存储桶 / 数据库 / 命名空间）

/** 创建/删除资源的进行态（存储各列表共用）。 */
data class StorageOpState(
    val isCreating: Boolean = false,
    val isDeleting: Boolean = false,
)

/** 创建/删除资源的一次性事件（存储各列表共用）。 */
sealed interface StorageOpEvent {
    data object Created : StorageOpEvent
    data object Deleted : StorageOpEvent
    data class Error(val message: String?) : StorageOpEvent
}

@HiltViewModel
class R2BucketListViewModel @Inject constructor(
    private val accountStore: AccountStore,
    private val storageRepository: StorageRepository,
    authRepository: AuthRepository,
) : StorageListViewModel<R2Bucket>(accountStore, authRepository.hasScope(Scopes.R2_READ)) {

    /** 创建 / 删除桶都需要 workers-r2-storage.write。 */
    val canWrite: Boolean = authRepository.hasScope(Scopes.R2_WRITE)

    private val _opState = MutableStateFlow(StorageOpState())
    val opState: StateFlow<StorageOpState> = _opState.asStateFlow()

    private val eventChannel = Channel<StorageOpEvent>(Channel.BUFFERED)
    val events: Flow<StorageOpEvent> = eventChannel.receiveAsFlow()

    override suspend fun fetch(accountId: String) = storageRepository.listBuckets(accountId)
    init { load() }

    /** 创建桶：成功后插到列表顶端。 */
    fun create(name: String) {
        if (!canWrite || _opState.value.isCreating) return
        viewModelScope.launch {
            _opState.update { it.copy(isCreating = true) }
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                val created = storageRepository.createBucket(accountId, name)
                state.update { it.copy(items = listOf(created) + it.items) }
                eventChannel.send(StorageOpEvent.Created)
            } catch (e: Exception) {
                eventChannel.send(StorageOpEvent.Error(e.message))
            } finally {
                _opState.update { it.copy(isCreating = false) }
            }
        }
    }

    /** 删除桶：成功后从列表移除。须桶为空，且经二次确认。不可恢复。 */
    fun delete(bucket: R2Bucket) {
        if (!canWrite || _opState.value.isDeleting) return
        viewModelScope.launch {
            _opState.update { it.copy(isDeleting = true) }
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                storageRepository.deleteBucket(accountId, bucket.name)
                state.update { it.copy(items = it.items.filterNot { b -> b.name == bucket.name }) }
                eventChannel.send(StorageOpEvent.Deleted)
            } catch (e: Exception) {
                eventChannel.send(StorageOpEvent.Error(e.message))
            } finally {
                _opState.update { it.copy(isDeleting = false) }
            }
        }
    }
}

sealed interface D1DbEvent {
    data object Created : D1DbEvent
    data object Deleted : D1DbEvent
    data class Error(val message: String?) : D1DbEvent
}

/** 创建/删除数据库的进行态（列表读取态仍走基类 uiState）。 */
data class D1DbOpState(
    val isCreating: Boolean = false,
    val isDeleting: Boolean = false,
)

@HiltViewModel
class D1DatabaseListViewModel @Inject constructor(
    private val accountStore: AccountStore,
    private val storageRepository: StorageRepository,
    authRepository: AuthRepository,
) : StorageListViewModel<D1Database>(accountStore, authRepository.hasScope(Scopes.D1_READ)) {

    /** 创建 / 删除数据库都需要 d1.write（读权限已是进入 D1 段的前置条件）。 */
    val canWrite: Boolean = authRepository.hasScope(Scopes.D1_WRITE)

    private val _opState = MutableStateFlow(D1DbOpState())
    val opState: StateFlow<D1DbOpState> = _opState.asStateFlow()

    private val eventChannel = Channel<D1DbEvent>(Channel.BUFFERED)
    val events: Flow<D1DbEvent> = eventChannel.receiveAsFlow()

    // 列表端点的 num_tables / file_size 常年为 0，并发拉详情回填真实值（对齐 iOS）。
    // 某个库详情失败时回退到列表条目本身，不阻塞其余库。
    override suspend fun fetch(accountId: String): List<D1Database> = coroutineScope {
        storageRepository.listDatabases(accountId)
            .map { db -> async { runCatching { storageRepository.getDatabase(accountId, db.uuid) }.getOrDefault(db) } }
            .awaitAll()
    }
    init { load() }

    /** 创建数据库：成功后把新库插到列表顶端。 */
    fun create(name: String, locationHint: String?) {
        if (!canWrite || _opState.value.isCreating) return
        viewModelScope.launch {
            _opState.update { it.copy(isCreating = true) }
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                val created = storageRepository.createDatabase(accountId, name, locationHint)
                state.update { it.copy(items = listOf(created) + it.items) }
                eventChannel.send(D1DbEvent.Created)
            } catch (e: Exception) {
                eventChannel.send(D1DbEvent.Error(e.message))
            } finally {
                _opState.update { it.copy(isCreating = false) }
            }
        }
    }

    /** 删除数据库：成功后从列表移除。不可恢复，调用前须经二次确认。 */
    fun delete(database: D1Database) {
        if (!canWrite || _opState.value.isDeleting) return
        viewModelScope.launch {
            _opState.update { it.copy(isDeleting = true) }
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                storageRepository.deleteDatabase(accountId, database.uuid)
                state.update { it.copy(items = it.items.filterNot { db -> db.uuid == database.uuid }) }
                eventChannel.send(D1DbEvent.Deleted)
            } catch (e: Exception) {
                eventChannel.send(D1DbEvent.Error(e.message))
            } finally {
                _opState.update { it.copy(isDeleting = false) }
            }
        }
    }
}

@HiltViewModel
class KVNamespaceListViewModel @Inject constructor(
    private val accountStore: AccountStore,
    private val storageRepository: StorageRepository,
    authRepository: AuthRepository,
) : StorageListViewModel<KVNamespace>(accountStore, authRepository.hasScope(Scopes.KV_READ)) {

    /** 创建 / 删除命名空间都需要 workers-kv-storage.write。 */
    val canWrite: Boolean = authRepository.hasScope(Scopes.KV_WRITE)

    private val _opState = MutableStateFlow(StorageOpState())
    val opState: StateFlow<StorageOpState> = _opState.asStateFlow()

    private val eventChannel = Channel<StorageOpEvent>(Channel.BUFFERED)
    val events: Flow<StorageOpEvent> = eventChannel.receiveAsFlow()

    override suspend fun fetch(accountId: String) = storageRepository.listNamespaces(accountId)
    init { load() }

    /** 创建命名空间：成功后插到列表顶端。 */
    fun create(title: String) {
        if (!canWrite || _opState.value.isCreating) return
        viewModelScope.launch {
            _opState.update { it.copy(isCreating = true) }
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                val created = storageRepository.createNamespace(accountId, title)
                state.update { it.copy(items = listOf(created) + it.items) }
                eventChannel.send(StorageOpEvent.Created)
            } catch (e: Exception) {
                eventChannel.send(StorageOpEvent.Error(e.message))
            } finally {
                _opState.update { it.copy(isCreating = false) }
            }
        }
    }

    /** 删除命名空间：成功后从列表移除。连同全部键值，经二次确认。不可恢复。 */
    fun delete(namespace: KVNamespace) {
        if (!canWrite || _opState.value.isDeleting) return
        viewModelScope.launch {
            _opState.update { it.copy(isDeleting = true) }
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                storageRepository.deleteNamespace(accountId, namespace.id)
                state.update { it.copy(items = it.items.filterNot { ns -> ns.id == namespace.id }) }
                eventChannel.send(StorageOpEvent.Deleted)
            } catch (e: Exception) {
                eventChannel.send(StorageOpEvent.Error(e.message))
            } finally {
                _opState.update { it.copy(isDeleting = false) }
            }
        }
    }
}

// MARK: - R2 对象（游标分页）

sealed interface R2Event {
    data object Uploaded : R2Event
    data object Deleted : R2Event
    data object Copied : R2Event
    data object Moved : R2Event
    data object MoveVerifyFailed : R2Event
    /** 预览失败/类型不支持：不静默，弹 snackbar 提示改用下载。 */
    data object PreviewUnsupported : R2Event
    data class Error(val message: String?) : R2Event
}

data class R2ObjectUiState(
    val objects: List<R2Object> = emptyList(),
    /** 当前所在「文件夹」前缀（空 = 根）。 */
    val prefix: String = "",
    /** 当前层折叠出的子文件夹。 */
    val folders: List<R2Folder> = emptyList(),
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val isUploading: Boolean = false,
    val isDownloading: Boolean = false,
    val isCopying: Boolean = false,
    val copyProgress: Float = 0f,
    val hasError: Boolean = false,
    val missingScope: Boolean = false,
    val hasMore: Boolean = false,
    val canWrite: Boolean = false,
)

@HiltViewModel
class R2ObjectListViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val accountStore: AccountStore,
    private val storageRepository: StorageRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    val bucket: String = checkNotNull(savedStateHandle["bucket"])
    private val hasScope = authRepository.hasScope(Scopes.R2_READ)
    private val canWrite = authRepository.hasScope(Scopes.R2_WRITE)
    private var cursor: String? = null
    /** 当前所在文件夹前缀（空 = 根）。 */
    private var prefix: String = ""

    private val _uiState = MutableStateFlow(
        R2ObjectUiState(isLoading = hasScope, missingScope = !hasScope, canWrite = canWrite),
    )
    val uiState: StateFlow<R2ObjectUiState> = _uiState.asStateFlow()

    private val eventChannel = Channel<R2Event>(Channel.BUFFERED)
    val events: Flow<R2Event> = eventChannel.receiveAsFlow()

    /** 详情页内联预览（图片 / JSON / 文本），与下载并打开互不干扰。 */
    private val _previewState = MutableStateFlow(R2PreviewState())
    val previewState: StateFlow<R2PreviewState> = _previewState.asStateFlow()

    init {
        if (hasScope) loadFirst()
    }

    /**
     * 内联预览：先按 contentType（扩展名兜底）判类型，再按大小上限决定要不要下载——
     * 超限直接给提示，绝不把大对象整个读进内存。图片走降采样解码，文本按 UTF-8 解码后可选 JSON 美化。
     */
    fun preview(obj: R2Object) {
        val current = _previewState.value
        if (current.key == obj.key && (current.isLoading || current.content != null)) return

        val contentType = obj.httpMetadata?.contentType
        val isImage = isImageKey(obj.key, contentType)
        val isText = !isImage && isTextKey(obj.key, contentType)
        if (!isImage && !isText) {
            _previewState.value = R2PreviewState(key = obj.key, content = R2Preview.Unsupported)
            viewModelScope.launch { eventChannel.send(R2Event.PreviewUnsupported) }
            return
        }

        val limit = if (isImage) R2_IMAGE_PREVIEW_MAX_BYTES else R2_TEXT_PREVIEW_MAX_BYTES
        val size = obj.size
        if (size != null && size > limit) {
            _previewState.value = R2PreviewState(key = obj.key, content = R2Preview.TooLarge(size))
            return
        }

        _previewState.value = R2PreviewState(key = obj.key, isLoading = true)
        viewModelScope.launch {
            accountStore.ensureLoaded()
            val accountId = accountStore.selectedAccountId.value
            val bytes = if (accountId == null) {
                null
            } else {
                runCatching { storageRepository.getObjectBytes(accountId, bucket, obj.key) }.getOrNull()
            }
            val content: R2Preview = when {
                bytes == null -> R2Preview.Failed
                // size 缺失时的兜底：实际字节仍超限就不做解码
                bytes.size > limit -> R2Preview.TooLarge(bytes.size.toLong())
                else -> {
                    val data: ByteArray = bytes
                    withContext(Dispatchers.Default) {
                        if (isImage) {
                            decodeSampledBitmap(data)?.let { R2Preview.ImageContent(it) } ?: R2Preview.Unsupported
                        } else {
                            decodeTextPreview(data, preferJson = isJsonKey(obj.key, contentType))
                        }
                    }
                }
            }
            // 期间用户可能换了对象，只写回仍属当前 key 的结果
            if (_previewState.value.key == obj.key) {
                _previewState.value = R2PreviewState(key = obj.key, content = content)
            }
            if (content is R2Preview.Unsupported || content is R2Preview.Failed) {
                eventChannel.send(R2Event.PreviewUnsupported)
            }
        }
    }

    /** 关闭详情时清空预览（释放位图引用）。 */
    fun clearPreview() {
        _previewState.value = R2PreviewState()
    }

    /** 当前列表请求；换目录 / 刷新时取消它，慢到的旧目录响应不能覆盖新目录的内容与游标 */
    private var listJob: Job? = null

    fun loadFirst() {
        if (!hasScope) return
        cursor = null
        listJob?.cancel()
        listJob = viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, hasError = false, objects = emptyList(), folders = emptyList(), prefix = prefix) }
            fetchPage(reset = true)
            _uiState.update { it.copy(isLoading = false) }
        }
    }

    /** 进入子文件夹。 */
    fun navigateInto(folder: R2Folder) {
        prefix = folder.prefix
        loadFirst()
    }

    /** 返回上一层文件夹。已在根则忽略。 */
    fun navigateUp() {
        if (prefix.isEmpty()) return
        prefix = R2Folder.parentOf(prefix)
        loadFirst()
    }

    fun loadMore() {
        if (!hasScope || cursor == null || _uiState.value.isLoadingMore) return
        listJob?.cancel()
        listJob = viewModelScope.launch {
            _uiState.update { it.copy(isLoadingMore = true) }
            fetchPage(reset = false)
            _uiState.update { it.copy(isLoadingMore = false) }
        }
    }

    private suspend fun fetchPage(reset: Boolean) {
        try {
            accountStore.ensureLoaded()
            val accountId = accountStore.selectedAccountId.value ?: run {
                _uiState.update { it.copy(hasError = true) }
                return
            }
            val page = storageRepository.listObjects(accountId, bucket, prefix, cursor)
            currentCoroutineContext().ensureActive()
            cursor = page.nextCursor
            val folders = R2Folder.makeList(page.folderPrefixes, prefix)
            _uiState.update {
                it.copy(
                    objects = if (reset) page.objects else it.objects + page.objects,
                    folders = if (reset) folders else it.folders,
                    hasMore = page.nextCursor != null,
                )
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _uiState.update { it.copy(hasError = true) }
        }
    }

    /** 下载对象原始字节（详情页预览/打开用）。失败返回 null。 */
    suspend fun objectBytes(key: String): ByteArray? {
        accountStore.ensureLoaded()
        val accountId = accountStore.selectedAccountId.value ?: return null
        _uiState.update { it.copy(isDownloading = true) }
        return try {
            storageRepository.getObjectBytes(accountId, bucket, key)
        } catch (e: Exception) {
            eventChannel.send(R2Event.Error(e.message))
            null
        } finally {
            _uiState.update { it.copy(isDownloading = false) }
        }
    }

    fun upload(filename: String, contentType: String, bytes: ByteArray) {
        if (!canWrite) return
        viewModelScope.launch {
            _uiState.update { it.copy(isUploading = true) }
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                // 上传进当前文件夹（前缀 + 文件名）
                storageRepository.putObject(accountId, bucket, prefix + filename, bytes, contentType)
                eventChannel.send(R2Event.Uploaded)
                loadFirst()
            } catch (e: Exception) {
                eventChannel.send(R2Event.Error(e.message))
            } finally {
                _uiState.update { it.copy(isUploading = false) }
            }
        }
    }

    fun delete(key: String) {
        if (!canWrite) return
        viewModelScope.launch {
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                storageRepository.deleteObject(accountId, bucket, key)
                _uiState.update { it.copy(objects = it.objects.filterNot { obj -> obj.key == key }) }
                eventChannel.send(R2Event.Deleted)
            } catch (e: Exception) {
                eventChannel.send(R2Event.Error(e.message))
            }
        }
    }

    /**
     * 复制（isMove=false）/ 移动（isMove=true）对象到新 key（同桶，流式过临时文件）。
     * 移动 = 复制 → 校验目标已写入 → 删源；校验不过绝不删源，避免半路失败丢数据。
     */
    fun copyOrMove(sourceKey: String, destKey: String, contentType: String, isMove: Boolean) {
        if (!canWrite || destKey.isBlank() || destKey == sourceKey || _uiState.value.isCopying) return
        viewModelScope.launch {
            val accountId = accountStore.selectedAccountId.value ?: return@launch
            _uiState.update { it.copy(isCopying = true, copyProgress = 0f) }
            try {
                storageRepository.copyObject(accountId, bucket, sourceKey, destKey, contentType) { p ->
                    _uiState.update { it.copy(copyProgress = p) }
                }
                if (isMove) {
                    if (!storageRepository.objectExists(accountId, bucket, destKey)) {
                        eventChannel.send(R2Event.MoveVerifyFailed)
                        return@launch
                    }
                    storageRepository.deleteObject(accountId, bucket, sourceKey)
                    eventChannel.send(R2Event.Moved)
                } else {
                    eventChannel.send(R2Event.Copied)
                }
                loadFirst()
            } catch (e: Exception) {
                eventChannel.send(R2Event.Error(e.message))
            } finally {
                _uiState.update { it.copy(isCopying = false) }
            }
        }
    }
}

// MARK: - D1 查询控制台

sealed interface D1QueryEvent {
    data object TableDropped : D1QueryEvent
    /** SQL 超长，未加入收藏。 */
    data object FavoriteTooLong : D1QueryEvent
    /** 收藏已满。 */
    data object FavoriteFull : D1QueryEvent
    data class Error(val message: String?) : D1QueryEvent
}

data class D1QueryUiState(
    val results: List<D1QueryResult> = emptyList(),
    val columns: List<String> = emptyList(),
    val isRunning: Boolean = false,
    val error: String? = null,
    val missingScope: Boolean = false,
    val tables: List<String> = emptyList(),
    val tablesLoaded: Boolean = false,
    val canWrite: Boolean = false,
    val droppingTable: String? = null,
    /** 最近成功执行过的 SQL（落盘，按库分键），新的在前。 */
    val history: List<String> = emptyList(),
    /** 收藏的 SQL（落盘，按库分键）。 */
    val favorites: List<String> = emptyList(),
)

@HiltViewModel
class D1QueryViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val accountStore: AccountStore,
    private val storageRepository: StorageRepository,
    private val queryPrefs: D1QueryPrefs,
    authRepository: AuthRepository,
) : ViewModel() {

    val databaseId: String = checkNotNull(savedStateHandle["dbId"])
    val databaseName: String = savedStateHandle.get<String>("dbName").orEmpty()
    private val hasScope = authRepository.hasScope(Scopes.D1_READ)
    /** 删表需要 d1.write（读权限已是进入 D1 段的前置条件）。 */
    private val canWrite = authRepository.hasScope(Scopes.D1_WRITE)

    private val _uiState = MutableStateFlow(D1QueryUiState(missingScope = !hasScope, canWrite = canWrite))
    val uiState: StateFlow<D1QueryUiState> = _uiState.asStateFlow()

    private val eventChannel = Channel<D1QueryEvent>(Channel.BUFFERED)
    val events: Flow<D1QueryEvent> = eventChannel.receiveAsFlow()

    init {
        if (hasScope) loadTables()
        viewModelScope.launch {
            queryPrefs.history(databaseId).collect { list -> _uiState.update { it.copy(history = list) } }
        }
        viewModelScope.launch {
            queryPrefs.favorites(databaseId).collect { list -> _uiState.update { it.copy(favorites = list) } }
        }
    }

    /** 收藏 / 取消收藏当前 SQL（落盘）。超长或已满时提示原因。 */
    fun toggleFavorite(sql: String) {
        val entry = sql.trim()
        if (entry.isEmpty()) return
        viewModelScope.launch {
            when (queryPrefs.toggleFavorite(databaseId, entry)) {
                D1FavoriteResult.TOO_LONG -> eventChannel.send(D1QueryEvent.FavoriteTooLong)
                D1FavoriteResult.FULL -> eventChannel.send(D1QueryEvent.FavoriteFull)
                D1FavoriteResult.ADDED, D1FavoriteResult.REMOVED -> Unit
            }
        }
    }

    /** 用户表清单（排除 sqlite_* 与 D1 内部 _cf_* 表），对齐 iOS D1QueryViewModel.loadTables。 */
    fun loadTables() {
        if (!hasScope || _uiState.value.tablesLoaded) return
        viewModelScope.launch {
            val sql = "SELECT name FROM sqlite_master WHERE type='table' " +
                "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY name"
            val tables = runCatching {
                accountStore.ensureLoaded()
                val accountId = accountStore.selectedAccountId.value ?: return@runCatching emptyList<String>()
                storageRepository.query(accountId, databaseId, sql)
                    .firstOrNull()?.results.orEmpty()
                    .mapNotNull { (it["name"] as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }
            }.getOrDefault(emptyList())
            _uiState.update { it.copy(tables = tables, tablesLoaded = true) }
        }
    }

    fun run(sql: String) {
        if (!hasScope || sql.isBlank()) return
        viewModelScope.launch {
            _uiState.update { it.copy(isRunning = true, error = null) }
            try {
                accountStore.ensureLoaded()
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                val results = storageRepository.query(accountId, databaseId, sql.trim())
                val columns = results.firstOrNull()?.results?.firstOrNull()?.keys?.toList().orEmpty()
                _uiState.update { it.copy(results = results, columns = columns) }
                // 仅成功执行才进历史
                queryPrefs.addHistory(databaseId, sql)
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message ?: "error", results = emptyList(), columns = emptyList()) }
            } finally {
                _uiState.update { it.copy(isRunning = false) }
            }
        }
    }

    /** 标识符加引号并转义内部双引号，防 SQL 注入（对齐 D1TableViewModel.quoted）。 */
    private fun quoted(identifier: String): String =
        "\"" + identifier.replace("\"", "\"\"") + "\""

    /** DROP TABLE：删除整张表及其全部数据（d1.write 门控，标识符加引号防注入）。 */
    fun dropTable(name: String) {
        if (!canWrite || _uiState.value.droppingTable != null) return
        viewModelScope.launch {
            _uiState.update { it.copy(droppingTable = name) }
            try {
                accountStore.ensureLoaded()
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                storageRepository.query(accountId, databaseId, "DROP TABLE IF EXISTS ${quoted(name)}")
                _uiState.update { it.copy(tables = it.tables - name) }
                eventChannel.send(D1QueryEvent.TableDropped)
            } catch (e: Exception) {
                eventChannel.send(D1QueryEvent.Error(e.message))
            } finally {
                _uiState.update { it.copy(droppingTable = null) }
            }
        }
    }
}

// MARK: - D1 表浏览器（列结构 + rowid 分页行 + 行编辑/删除）

sealed interface D1RowEvent {
    data object Saved : D1RowEvent
    data object Deleted : D1RowEvent
    data class Error(val message: String?) : D1RowEvent
}

data class D1TableUiState(
    val columns: List<D1Column> = emptyList(),
    /** PRAGMA index_list 读出的索引（失败/无索引即空列表，不阻塞行数据）。 */
    val indexes: List<D1IndexInfo> = emptyList(),
    val indexesLoaded: Boolean = false,
    val rows: List<Map<String, JsonElement>> = emptyList(),
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val hasMore: Boolean = false,
    val error: String? = null,
    val canWrite: Boolean = false,
    val missingScope: Boolean = false,
)

@HiltViewModel
class D1TableViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val accountStore: AccountStore,
    private val storageRepository: StorageRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    val databaseId: String = checkNotNull(savedStateHandle["dbId"])
    val tableName: String = checkNotNull(savedStateHandle["table"])
    private val hasRead = authRepository.hasScope(Scopes.D1_READ)
    private val canWrite = authRepository.hasScope(Scopes.D1_WRITE)

    private var offset = 0
    private val pageSize = 50

    private val _uiState = MutableStateFlow(
        D1TableUiState(isLoading = hasRead, canWrite = canWrite, missingScope = !hasRead),
    )
    val uiState: StateFlow<D1TableUiState> = _uiState.asStateFlow()

    private val eventChannel = Channel<D1RowEvent>(Channel.BUFFERED)
    val events: Flow<D1RowEvent> = eventChannel.receiveAsFlow()

    init {
        if (hasRead) load()
    }

    /** 标识符加引号并转义内部双引号，防 SQL 注入（对齐 iOS quoted）。 */
    private fun quoted(identifier: String): String =
        "\"" + identifier.replace("\"", "\"\"") + "\""

    private val quotedTable: String get() = quoted(tableName)

    fun load() {
        if (!hasRead) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                accountStore.ensureLoaded()
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                var columns = _uiState.value.columns
                if (columns.isEmpty()) {
                    val info = storageRepository.query(accountId, databaseId, "PRAGMA table_info($quotedTable)")
                    columns = info.firstOrNull()?.results.orEmpty().mapNotNull { row ->
                        val name = (row["name"] as? JsonPrimitive)?.content ?: return@mapNotNull null
                        val type = (row["type"] as? JsonPrimitive)?.content.orEmpty()
                        val pk = ((row["pk"] as? JsonPrimitive)?.content ?: "0") != "0"
                        D1Column(name, type, pk)
                    }
                }
                offset = 0
                val (rows, more) = fetchPage(accountId, 0)
                _uiState.update { it.copy(columns = columns, rows = rows, hasMore = more) }
                loadIndexes(accountId)
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message ?: "error") }
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
        }
    }

    fun loadMore() {
        if (!hasRead || _uiState.value.isLoading || !_uiState.value.hasMore) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                // 先取成功再推进 offset：瞬时失败时 hasMore 仍为 true，下次点击会跳过整整一页
                val next = offset + pageSize
                val (rows, more) = fetchPage(accountId, next)
                offset = next
                _uiState.update { it.copy(rows = it.rows + rows, hasMore = more) }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message ?: "error") }
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
        }
    }

    /**
     * 索引清单：PRAGMA index_list（表名走 quoted 转义防注入）。
     * 属于附加信息，失败只置 loaded 不报错，不影响行数据。
     */
    private suspend fun loadIndexes(accountId: String) {
        val indexes = runCatching {
            storageRepository.query(accountId, databaseId, "PRAGMA index_list($quotedTable)")
                .firstOrNull()?.results.orEmpty()
                .mapNotNull { row ->
                    val name = (row["name"] as? JsonPrimitive)?.content ?: return@mapNotNull null
                    D1IndexInfo(
                        name = name,
                        unique = ((row["unique"] as? JsonPrimitive)?.content ?: "0") != "0",
                        origin = (row["origin"] as? JsonPrimitive)?.content.orEmpty(),
                        partial = ((row["partial"] as? JsonPrimitive)?.content ?: "0") != "0",
                    )
                }
        }.getOrDefault(emptyList())
        _uiState.update { it.copy(indexes = indexes, indexesLoaded = true) }
    }

    /** 多取 1 行判断是否还有下一页（对齐 iOS fetchPage）。 */
    private suspend fun fetchPage(accountId: String, offset: Int): Pair<List<Map<String, JsonElement>>, Boolean> {
        val sql = "SELECT rowid AS $ROWID_KEY, * FROM $quotedTable LIMIT ${pageSize + 1} OFFSET $offset"
        val results = storageRepository.query(accountId, databaseId, sql)
        var page = results.firstOrNull()?.results.orEmpty()
        val more = page.size > pageSize
        if (more) page = page.dropLast(1)
        return page to more
    }

    /** 仅更新变更列（参数化，rowid 定位）。 */
    fun updateRow(rowid: String, changes: Map<String, String>) {
        if (!canWrite || changes.isEmpty()) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true) }
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                val assignments = changes.keys.joinToString(", ") { "${quoted(it)} = ?" }
                val sql = "UPDATE $quotedTable SET $assignments WHERE rowid = ?"
                val params = changes.keys.map { changes.getValue(it) } + rowid
                storageRepository.query(accountId, databaseId, sql, params)
                eventChannel.send(D1RowEvent.Saved)
                load()
            } catch (e: Exception) {
                eventChannel.send(D1RowEvent.Error(e.message))
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    fun deleteRow(rowid: String) {
        if (!canWrite) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true) }
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                storageRepository.query(
                    accountId, databaseId,
                    "DELETE FROM $quotedTable WHERE rowid = ?", listOf(rowid),
                )
                eventChannel.send(D1RowEvent.Deleted)
                load()
            } catch (e: Exception) {
                eventChannel.send(D1RowEvent.Error(e.message))
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    companion object {
        /** 行编辑用的 rowid 别名（避免与同名列冲突），对齐 iOS rowidKey。 */
        const val ROWID_KEY = "_oc_rowid_"
    }
}

// MARK: - KV 键列表（游标分页）+ 值读写删

sealed interface KVEvent {
    data object Saved : KVEvent
    data object Deleted : KVEvent
    data class Error(val cfMessage: String?) : KVEvent
}

data class KVKeyUiState(
    val keys: List<KVKey> = emptyList(),
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val hasError: Boolean = false,
    val missingScope: Boolean = false,
    val hasMore: Boolean = false,
    val canWrite: Boolean = false,
)

@HiltViewModel
class KVKeyListViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val accountStore: AccountStore,
    private val storageRepository: StorageRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    val namespaceId: String = checkNotNull(savedStateHandle["nsId"])
    val namespaceTitle: String = savedStateHandle.get<String>("nsTitle").orEmpty()
    private val hasRead = authRepository.hasScope(Scopes.KV_READ)
    private val canWrite = authRepository.hasScope(Scopes.KV_WRITE)
    private var cursor: String? = null

    private val _uiState = MutableStateFlow(
        KVKeyUiState(isLoading = hasRead, missingScope = !hasRead, canWrite = canWrite),
    )
    val uiState: StateFlow<KVKeyUiState> = _uiState.asStateFlow()

    private val eventChannel = Channel<KVEvent>(Channel.BUFFERED)
    val events: Flow<KVEvent> = eventChannel.receiveAsFlow()

    init {
        if (hasRead) loadFirst()
    }

    /** 当前列表请求；刷新时取消它，飞行中的「加载更多」不能把旧页追加到刷新后的列表上 */
    private var listJob: Job? = null

    fun loadFirst() {
        if (!hasRead) return
        cursor = null
        listJob?.cancel()
        listJob = viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, hasError = false, keys = emptyList()) }
            fetchPage(reset = true)
            _uiState.update { it.copy(isLoading = false) }
        }
    }

    fun loadMore() {
        if (!hasRead || cursor == null || _uiState.value.isLoadingMore) return
        listJob?.cancel()
        listJob = viewModelScope.launch {
            _uiState.update { it.copy(isLoadingMore = true) }
            fetchPage(reset = false)
            _uiState.update { it.copy(isLoadingMore = false) }
        }
    }

    private suspend fun fetchPage(reset: Boolean) {
        try {
            accountStore.ensureLoaded()
            val accountId = accountStore.selectedAccountId.value ?: run {
                _uiState.update { it.copy(hasError = true) }
                return
            }
            val (keys, next) = storageRepository.listKeys(accountId, namespaceId, cursor)
            currentCoroutineContext().ensureActive()
            cursor = next
            _uiState.update {
                it.copy(keys = if (reset) keys else it.keys + keys, hasMore = next != null)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _uiState.update { it.copy(hasError = true) }
        }
    }

    /** 读取键值（UTF-8 文本）。 */
    suspend fun loadValue(key: String): String? {
        val accountId = accountStore.selectedAccountId.value ?: return null
        return runCatching {
            storageRepository.getValue(accountId, namespaceId, key).decodeToString()
        }.getOrNull()
    }

    fun saveValue(key: String, value: String) {
        if (!canWrite) return
        viewModelScope.launch {
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                storageRepository.putValue(accountId, namespaceId, key, value)
                eventChannel.send(KVEvent.Saved)
                loadFirst()
            } catch (e: Exception) {
                eventChannel.send(KVEvent.Error(e.message))
            }
        }
    }

    fun deleteKey(key: String) {
        if (!canWrite) return
        viewModelScope.launch {
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                storageRepository.deleteKey(accountId, namespaceId, key)
                eventChannel.send(KVEvent.Deleted)
                loadFirst()
            } catch (e: Exception) {
                eventChannel.send(KVEvent.Error(e.message))
            }
        }
    }
}
