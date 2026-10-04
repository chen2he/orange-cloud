package jiamin.chen.orangecloud.ui.workers

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.data.model.D1Database
import jiamin.chen.orangecloud.data.model.KVNamespace
import jiamin.chen.orangecloud.data.model.R2Bucket
import jiamin.chen.orangecloud.data.model.ScopedWorkerRoute
import jiamin.chen.orangecloud.data.model.WorkerBinding
import jiamin.chen.orangecloud.data.model.WorkerBindingInput
import jiamin.chen.orangecloud.data.model.WorkerCustomDomain
import jiamin.chen.orangecloud.data.model.WorkerSchedule
import jiamin.chen.orangecloud.data.model.WorkerSecret
import jiamin.chen.orangecloud.data.model.WorkerSettings
import jiamin.chen.orangecloud.data.model.WorkerSubdomain
import jiamin.chen.orangecloud.data.repository.AccountStore
import jiamin.chen.orangecloud.data.repository.StorageRepository
import jiamin.chen.orangecloud.data.repository.WorkerRepository
import jiamin.chen.orangecloud.data.repository.ZoneRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

// MARK: - 变量与密钥（密钥专用端点 + 变量 PATCH settings）

data class WorkerBindingsUiState(
    val secrets: List<WorkerSecret> = emptyList(),
    val variables: List<WorkerBinding> = emptyList(),
    val otherBindings: List<WorkerBinding> = emptyList(),
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val loaded: Boolean = false,
    val canWrite: Boolean = false,
    val canReadD1: Boolean = false,
    val canReadKV: Boolean = false,
    val canReadR2: Boolean = false,
    // 快速绑定用可选资源（打开绑定选择器时惰性加载）
    val d1Databases: List<D1Database> = emptyList(),
    val kvNamespaces: List<KVNamespace> = emptyList(),
    val r2Buckets: List<R2Bucket> = emptyList(),
    val loadingResources: Boolean = false,
    val boundNames: Set<String> = emptySet(),
    val error: String? = null,
) {
    /** 能读到至少一类资源、且可写脚本，才提供快速绑定入口。 */
    val canBind: Boolean get() = canWrite && (canReadD1 || canReadKV || canReadR2)
}

/**
 * Worker 密钥（secret_text，专用端点）+ 环境变量（plain_text，PATCH settings）+ 只读绑定清单。
 * 改变量一律 read-modify-write：变更项为实体、其余绑定 inherit，绝不丢失既有绑定/密钥。
 */
@HiltViewModel
class WorkerBindingsViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val accountStore: AccountStore,
    private val workerRepository: WorkerRepository,
    private val storageRepository: StorageRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    private val scriptName: String = checkNotNull(savedStateHandle["scriptName"])
    private val canWrite = authRepository.hasScope(Scopes.WORKERS_WRITE)
    private val canReadD1 = authRepository.hasScope(Scopes.D1_READ)
    private val canReadKV = authRepository.hasScope(Scopes.KV_READ)
    private val canReadR2 = authRepository.hasScope(Scopes.R2_READ)
    private var settings: WorkerSettings? = null
    private var resourcesLoaded = false

    private val _uiState = MutableStateFlow(
        WorkerBindingsUiState(canWrite = canWrite, canReadD1 = canReadD1, canReadKV = canReadKV, canReadR2 = canReadR2)
    )
    val uiState: StateFlow<WorkerBindingsUiState> = _uiState.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                val accountId = accountId()
                val secrets = workerRepository.listSecrets(accountId, scriptName)
                val s = workerRepository.settings(accountId, scriptName)
                settings = s
                _uiState.update {
                    it.copy(
                        secrets = secrets,
                        variables = s.validBindings.filter { b -> b.isPlainText }.sortedBy { b -> b.name },
                        otherBindings = s.validBindings.filter { b -> !b.isPlainText && !b.isSecret }.sortedBy { b -> b.name },
                        boundNames = s.validBindings.map { b -> b.name }.toSet(),
                        loaded = true,
                    )
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
        }
    }

    fun addSecret(name: String, text: String) {
        if (!canWrite || _uiState.value.isSaving) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, error = null) }
            try {
                val accountId = accountId()
                workerRepository.putSecret(accountId, scriptName, name, text)
                _uiState.update { it.copy(secrets = workerRepository.listSecrets(accountId, scriptName)) }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    fun deleteSecret(secret: WorkerSecret) {
        if (!canWrite) return
        viewModelScope.launch {
            try {
                val accountId = accountId()
                workerRepository.deleteSecret(accountId, scriptName, secret.name)
                _uiState.update { it.copy(secrets = it.secrets.filterNot { s -> s.name == secret.name }) }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            }
        }
    }

    fun setVariable(name: String, value: String) {
        val s = settings ?: return
        if (!canWrite || _uiState.value.isSaving) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, error = null) }
            try {
                val bindings = s.inheritedBindings(excludingName = name) + WorkerBindingInput("plain_text", name, value)
                patchAndReload(bindings)
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    fun deleteVariable(binding: WorkerBinding) {
        val s = settings ?: return
        if (!canWrite) return
        viewModelScope.launch {
            try {
                patchAndReload(s.inheritedBindings(excludingName = binding.name))
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            }
        }
    }

    // MARK: - 批量导入（JSON）

    /** 批量导入变量（plain_text）：单次 PATCH，导入项设为实体、其余绑定 inherit，同名覆盖。原子。 */
    fun bulkImportVariables(pairs: List<Pair<String, String>>, onDone: () -> Unit) {
        val s = settings ?: return
        if (!canWrite || _uiState.value.isSaving || pairs.isEmpty()) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, error = null) }
            try {
                val imported = pairs.map { it.first }.toSet()
                val bindings = s.validBindings.filterNot { it.name in imported }.map { it.asInherit() } +
                    pairs.map { (name, value) -> WorkerBindingInput("plain_text", name, value) }
                patchAndReload(bindings)
                onDone()
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    /** 批量导入密钥（secret_text）：走 secrets-bulk 端点单次 PATCH 原子生效，同名覆盖（>100 项分批）。 */
    fun bulkImportSecrets(pairs: List<Pair<String, String>>, onDone: () -> Unit) {
        if (!canWrite || _uiState.value.isSaving || pairs.isEmpty()) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, error = null) }
            try {
                val accountId = accountId()
                pairs.chunked(100).forEach { chunk ->
                    workerRepository.bulkPatchSecrets(accountId, scriptName, chunk)
                }
                _uiState.update { it.copy(secrets = workerRepository.listSecrets(accountId, scriptName)) }
                onDone()
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
                runCatching {
                    _uiState.update { it.copy(secrets = workerRepository.listSecrets(accountId(), scriptName)) }
                }
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    private suspend fun patchAndReload(bindings: List<WorkerBindingInput>) {
        val s = settings ?: return
        val accountId = accountId()
        workerRepository.patchSettings(accountId, scriptName, bindings, s)
        val fresh = workerRepository.settings(accountId, scriptName)
        settings = fresh
        _uiState.update {
            it.copy(
                variables = fresh.validBindings.filter { b -> b.isPlainText }.sortedBy { b -> b.name },
                otherBindings = fresh.validBindings.filter { b -> !b.isPlainText && !b.isSecret }.sortedBy { b -> b.name },
                boundNames = fresh.validBindings.map { b -> b.name }.toSet(),
            )
        }
    }

    // MARK: - 快速绑定 D1 / KV

    /** 打开绑定选择器时按需加载可选资源（各类型读权限缺失时静默跳过对应列表）。 */
    fun loadResources() {
        if (resourcesLoaded || _uiState.value.loadingResources) return
        viewModelScope.launch {
            _uiState.update { it.copy(loadingResources = true) }
            try {
                val accountId = accountId()
                val d1 = if (canReadD1) runCatching { storageRepository.listDatabases(accountId) }.getOrDefault(emptyList()) else emptyList()
                val kv = if (canReadKV) runCatching { storageRepository.listNamespaces(accountId) }.getOrDefault(emptyList()) else emptyList()
                // 绑定只按桶名引用，区域限制桶（EU / US…）需要额外的 jurisdiction 字段，这里只列默认区域的桶
                val r2 = if (canReadR2) {
                    runCatching { storageRepository.listBuckets(accountId) }.getOrDefault(emptyList())
                        .filter { it.jurisdictionOrNull == null }
                } else emptyList()
                _uiState.update { it.copy(d1Databases = d1, kvNamespaces = kv, r2Buckets = r2) }
                resourcesLoaded = true
            } finally {
                _uiState.update { it.copy(loadingResources = false) }
            }
        }
    }

    /** 绑定一个 D1 数据库 / KV 命名空间：新绑定为实体、其余绑定 inherit，单次 PATCH，原子保留既有。 */
    fun bindResource(resource: WorkerBindingInput) {
        val s = settings ?: return
        if (!canWrite || _uiState.value.isSaving) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, error = null) }
            try {
                patchAndReload(s.inheritedBindings(excludingName = resource.name) + resource)
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    /** 解除某个 D1 / KV 绑定（其余绑定 inherit 回写）。 */
    fun unbindResource(binding: WorkerBinding) {
        val s = settings ?: return
        if (!canWrite) return
        viewModelScope.launch {
            try {
                patchAndReload(s.inheritedBindings(excludingName = binding.name))
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            }
        }
    }

    private suspend fun accountId(): String {
        accountStore.ensureLoaded()
        return accountStore.selectedAccountId.value ?: error("no account")
    }
}

// MARK: - Cron 触发器（整组 read-modify-write）

data class WorkerTriggersUiState(
    val schedules: List<WorkerSchedule> = emptyList(),
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val loaded: Boolean = false,
    val canWrite: Boolean = false,
    val error: String? = null,
)

@HiltViewModel
class WorkerTriggersViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val accountStore: AccountStore,
    private val workerRepository: WorkerRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    private val scriptName: String = checkNotNull(savedStateHandle["scriptName"])
    private val canWrite = authRepository.hasScope(Scopes.WORKERS_WRITE)

    private val _uiState = MutableStateFlow(WorkerTriggersUiState(canWrite = canWrite))
    val uiState: StateFlow<WorkerTriggersUiState> = _uiState.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                val schedules = workerRepository.schedules(accountId(), scriptName)
                _uiState.update { it.copy(schedules = schedules, loaded = true) }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
        }
    }

    fun addCron(cron: String) {
        val trimmed = cron.trim()
        if (!canWrite || _uiState.value.isSaving || trimmed.isEmpty()) return
        if (_uiState.value.schedules.any { it.cron == trimmed }) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, error = null) }
            try {
                val crons = _uiState.value.schedules.map { it.cron } + trimmed
                workerRepository.putSchedules(accountId(), scriptName, crons)
                reload()
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    fun deleteCron(schedule: WorkerSchedule) {
        if (!canWrite) return
        viewModelScope.launch {
            try {
                val crons = _uiState.value.schedules.filter { it.cron != schedule.cron }.map { it.cron }
                workerRepository.putSchedules(accountId(), scriptName, crons)
                reload()
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            }
        }
    }

    private suspend fun reload() {
        runCatching { workerRepository.schedules(accountId(), scriptName) }
            .onSuccess { list -> _uiState.update { it.copy(schedules = list) } }
    }

    private suspend fun accountId(): String {
        accountStore.ensureLoaded()
        return accountStore.selectedAccountId.value ?: error("no account")
    }
}

// MARK: - 域名 / 路由（workers.dev 子域 + 自定义域 + Zone 路由）

data class WorkerRoutesUiState(
    val subdomain: WorkerSubdomain? = null,
    val workersDevUrl: String? = null, // 子域开启且账号前缀已知时的完整访问地址
    val customDomains: List<WorkerCustomDomain> = emptyList(),
    val routes: List<ScopedWorkerRoute> = emptyList(),
    val zones: List<jiamin.chen.orangecloud.data.model.Zone> = emptyList(),
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val togglingSubdomain: Boolean = false,
    val loaded: Boolean = false,
    val canWrite: Boolean = false,
    val error: String? = null,
)

@HiltViewModel
class WorkerRoutesViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val accountStore: AccountStore,
    private val workerRepository: WorkerRepository,
    private val zoneRepository: ZoneRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    private val scriptName: String = checkNotNull(savedStateHandle["scriptName"])
    private val canWrite = authRepository.hasScope(Scopes.WORKERS_WRITE)
    private var accountSubdomain: String? = null // 账号级 workers.dev 前缀

    private val _uiState = MutableStateFlow(WorkerRoutesUiState(canWrite = canWrite))
    val uiState: StateFlow<WorkerRoutesUiState> = _uiState.asStateFlow()

    init { load() }

    /** 子域已开启且账号前缀已知时的完整访问地址：https://<脚本名>.<前缀>.workers.dev。 */
    private fun workersDevUrl(sub: WorkerSubdomain?): String? =
        accountSubdomain?.takeIf { sub?.enabled == true && it.isNotEmpty() }
            ?.let { "https://$scriptName.$it.workers.dev" }

    fun load() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                val accountId = accountId()
                val zones = zoneRepository.listZones(accountId)
                val customDomains = workerRepository.customDomains(accountId, scriptName)
                // 子域可能未在账号开通，单独容错，不阻断整页
                val subdomain = runCatching { workerRepository.subdomain(accountId, scriptName) }.getOrNull()
                accountSubdomain = runCatching { workerRepository.accountSubdomain(accountId) }.getOrNull()
                _uiState.update {
                    it.copy(
                        zones = zones, customDomains = customDomains, subdomain = subdomain,
                        workersDevUrl = workersDevUrl(subdomain), loaded = true,
                    )
                }
                loadRoutes(zones)
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
        }
    }

    /** 逐 zone 查路由并过滤本脚本（routes 端点是 zone 级）。 */
    private suspend fun loadRoutes(zones: List<jiamin.chen.orangecloud.data.model.Zone>) {
        val collected = mutableListOf<ScopedWorkerRoute>()
        for (zone in zones) {
            val zoneRoutes = runCatching { workerRepository.routes(zone.id) }.getOrDefault(emptyList())
            for (route in zoneRoutes) {
                if (route.script == scriptName) collected += ScopedWorkerRoute(zone.id, zone.name, route)
            }
        }
        _uiState.update { it.copy(routes = collected.sortedBy { r -> r.route.pattern }) }
    }

    fun toggleSubdomain(enabled: Boolean) {
        if (!canWrite || _uiState.value.togglingSubdomain) return
        viewModelScope.launch {
            _uiState.update { it.copy(togglingSubdomain = true, error = null) }
            try {
                val accountId = accountId()
                workerRepository.setSubdomain(accountId, scriptName, enabled)
                val fresh = runCatching { workerRepository.subdomain(accountId, scriptName) }.getOrNull()
                _uiState.update { it.copy(subdomain = fresh, workersDevUrl = workersDevUrl(fresh)) }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            } finally {
                _uiState.update { it.copy(togglingSubdomain = false) }
            }
        }
    }

    fun attachDomain(hostname: String, zoneId: String) {
        if (!canWrite || _uiState.value.isSaving) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, error = null) }
            try {
                val accountId = accountId()
                workerRepository.attachDomain(accountId, scriptName, hostname, zoneId)
                _uiState.update { it.copy(customDomains = workerRepository.customDomains(accountId, scriptName)) }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    fun detachDomain(domain: WorkerCustomDomain) {
        if (!canWrite) return
        viewModelScope.launch {
            try {
                workerRepository.deleteDomain(accountId(), domain.id)
                _uiState.update { it.copy(customDomains = it.customDomains.filterNot { d -> d.id == domain.id }) }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            }
        }
    }

    fun addRoute(zoneId: String, pattern: String) {
        val trimmed = pattern.trim()
        if (!canWrite || _uiState.value.isSaving || trimmed.isEmpty()) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, error = null) }
            try {
                workerRepository.createRoute(zoneId, trimmed, scriptName)
                loadRoutes(_uiState.value.zones)
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            } finally {
                _uiState.update { it.copy(isSaving = false) }
            }
        }
    }

    fun deleteRoute(scoped: ScopedWorkerRoute) {
        if (!canWrite) return
        viewModelScope.launch {
            try {
                workerRepository.deleteRoute(scoped.zoneId, scoped.route.id)
                _uiState.update { it.copy(routes = it.routes.filterNot { r -> r.route.id == scoped.route.id && r.zoneId == scoped.zoneId }) }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message) }
            }
        }
    }

    private suspend fun accountId(): String {
        accountStore.ensureLoaded()
        return accountStore.selectedAccountId.value ?: error("no account")
    }
}
