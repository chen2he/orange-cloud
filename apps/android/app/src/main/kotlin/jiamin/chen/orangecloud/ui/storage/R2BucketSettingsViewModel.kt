package jiamin.chen.orangecloud.ui.storage

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import jiamin.chen.orangecloud.core.auth.AuthRepository
import jiamin.chen.orangecloud.core.auth.Scopes
import jiamin.chen.orangecloud.data.model.R2Catalog
import jiamin.chen.orangecloud.data.model.R2CatalogNamespace
import jiamin.chen.orangecloud.data.repository.R2CatalogRepository
import jiamin.chen.orangecloud.data.model.R2Bandwidth
import jiamin.chen.orangecloud.data.model.R2BucketUsage
import jiamin.chen.orangecloud.data.model.R2CorsRule
import jiamin.chen.orangecloud.data.model.R2CustomDomain
import jiamin.chen.orangecloud.data.model.R2Jurisdiction
import jiamin.chen.orangecloud.data.repository.AccountStore
import jiamin.chen.orangecloud.data.repository.StorageRepository
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface BucketSettingsEvent {
    data object CorsCleared : BucketSettingsEvent
    data object DomainRemoved : BucketSettingsEvent
    data class Error(val message: String?) : BucketSettingsEvent
}

data class R2BucketSettingsUiState(
    val bucket: String = "",
    val publicEnabled: Boolean = false,
    val publicDomain: String? = null,
    val publicLoaded: Boolean = false,
    val customDomains: List<R2CustomDomain> = emptyList(),
    val corsRules: List<R2CorsRule> = emptyList(),
    val corsLoaded: Boolean = false,
    /** 本桶用量（best-effort GraphQL，免费账号常被 authz 挡 → null 不显示）。 */
    val usage: R2BucketUsage? = null,
    /** 本桶近 30 天带宽（best-effort，同上）。 */
    val bandwidth: R2Bandwidth? = null,
    val isLoading: Boolean = false,
    val isTogglingPublic: Boolean = false,
    val missingScope: Boolean = false,
    val canWrite: Boolean = false,
    // R2 数据目录（Iceberg）。启用是计费动作，界面先弹确认再调这里。
    val catalog: R2Catalog? = null,
    val catalogNamespaces: List<R2CatalogNamespace> = emptyList(),
    val catalogLoaded: Boolean = false,
    val isCatalogMutating: Boolean = false,
    val canReadCatalog: Boolean = false,
    /** r2-catalog-sql.read：目录已启用时展示 R2 SQL 查询入口 */
    val canQuerySql: Boolean = false,
    val canWriteCatalog: Boolean = false,
) {
    val catalogEnabled: Boolean get() = catalog?.isActive == true
}

/** R2 桶设置：公开访问 (r2.dev) + 自定义域 + CORS（对应 iOS R2BucketSettingsView）。 */
@HiltViewModel
class R2BucketSettingsViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val accountStore: AccountStore,
    private val storageRepository: StorageRepository,
    private val catalogRepository: R2CatalogRepository,
    authRepository: AuthRepository,
) : ViewModel() {

    private val bucket: String = checkNotNull(savedStateHandle["bucket"])
    /** 区域限制桶的 jurisdiction，默认区域为 null；公开访问 / 自定义域 / CORS 都是桶级调用，须透传。 */
    private val jurisdiction: String? = R2Jurisdiction.normalize(savedStateHandle.get<String>("jurisdiction"))
    private val hasRead = authRepository.hasScope(Scopes.R2_READ)
    private val canWrite = authRepository.hasScope(Scopes.R2_WRITE)
    // 数据目录是另一条权限链路（r2-catalog.*），与 workers-r2.* 无关
    private val canReadCatalog = authRepository.hasScope(Scopes.R2_CATALOG_READ)
    private val canQuerySql = authRepository.hasScope(Scopes.R2_CATALOG_SQL_READ)
    private val canWriteCatalog = authRepository.hasScope(Scopes.R2_CATALOG_WRITE)

    private val _uiState = MutableStateFlow(
        R2BucketSettingsUiState(
            bucket = bucket,
            isLoading = hasRead,
            missingScope = !hasRead,
            canWrite = canWrite,
            canReadCatalog = canReadCatalog,
            canQuerySql = canQuerySql,
            canWriteCatalog = canWriteCatalog,
        ),
    )
    val uiState: StateFlow<R2BucketSettingsUiState> = _uiState.asStateFlow()

    private val eventChannel = Channel<BucketSettingsEvent>(Channel.BUFFERED)
    val events: Flow<BucketSettingsEvent> = eventChannel.receiveAsFlow()

    init {
        if (hasRead) load()
        if (canReadCatalog) loadCatalog()
    }

    fun load() {
        if (!hasRead) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            val accountId = accountStore.run { ensureLoaded(); selectedAccountId.value } ?: run {
                _uiState.update { it.copy(isLoading = false) }
                return@launch
            }
            // 三项各自独立、best-effort：单项失败（如 CORS 未设置）不影响其它。
            runCatching { storageRepository.managedDomain(accountId, bucket, jurisdiction) }.getOrNull()?.let { md ->
                _uiState.update { it.copy(publicEnabled = md.enabled ?: false, publicDomain = md.domain, publicLoaded = true) }
            }
            runCatching { storageRepository.customDomains(accountId, bucket, jurisdiction) }.getOrNull()?.let { domains ->
                _uiState.update { it.copy(customDomains = domains) }
            }
            runCatching { storageRepository.corsPolicy(accountId, bucket, jurisdiction) }.getOrNull()?.let { cors ->
                _uiState.update { it.copy(corsRules = cors.rules.orEmpty(), corsLoaded = true) }
            }
            // 用量 / 带宽是附加信息：account-analytics 常被 authz 挡，失败即不显示。
            // GraphQL 里区域桶的 bucketName 带「区域_」前缀（eu_xxx），按桶匹配 / 过滤都用这个形式。
            val analyticsName = R2Jurisdiction.analyticsBucketName(bucket, jurisdiction)
            runCatching { storageRepository.r2UsageByBucket(accountId)[analyticsName] }.getOrNull()?.let { u ->
                _uiState.update { it.copy(usage = u) }
            }
            runCatching { storageRepository.r2Bandwidth(accountId, analyticsName) }.getOrNull()?.let { bw ->
                _uiState.update { it.copy(bandwidth = bw) }
            }
            _uiState.update { it.copy(isLoading = false) }
        }
    }

    fun setPublic(enabled: Boolean) {
        if (!canWrite || _uiState.value.isTogglingPublic) return
        _uiState.update { it.copy(isTogglingPublic = true) }
        viewModelScope.launch {
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                storageRepository.setManagedDomainEnabled(accountId, bucket, enabled, jurisdiction)
                _uiState.update { it.copy(publicEnabled = enabled) }
            } catch (e: Exception) {
                eventChannel.send(BucketSettingsEvent.Error(e.message))
            } finally {
                _uiState.update { it.copy(isTogglingPublic = false) }
            }
        }
    }

    fun removeDomain(domain: String) {
        if (!canWrite) return
        viewModelScope.launch {
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                storageRepository.removeCustomDomain(accountId, bucket, domain, jurisdiction)
                _uiState.update { it.copy(customDomains = it.customDomains.filterNot { d -> d.domain == domain }) }
                eventChannel.send(BucketSettingsEvent.DomainRemoved)
            } catch (e: Exception) {
                eventChannel.send(BucketSettingsEvent.Error(e.message))
            }
        }
    }

    fun clearCors() {
        if (!canWrite) return
        viewModelScope.launch {
            try {
                val accountId = accountStore.selectedAccountId.value ?: error("no account")
                storageRepository.deleteCorsPolicy(accountId, bucket, jurisdiction)
                _uiState.update { it.copy(corsRules = emptyList()) }
                eventChannel.send(BucketSettingsEvent.CorsCleared)
            } catch (e: Exception) {
                eventChannel.send(BucketSettingsEvent.Error(e.message))
            }
        }
    }

    /** 读数据目录。未启用时接口 404，按「未启用」处理而非报错。 */
    fun loadCatalog() {
        if (!canReadCatalog) return
        viewModelScope.launch {
            accountStore.ensureLoaded()
            val accountId = accountStore.selectedAccountId.value ?: return@launch
            val catalog = runCatching { catalogRepository.catalog(accountId, bucket) }.getOrNull()
            // 命名空间只在已启用时才有意义；失败不连累目录状态显示
            val namespaces = if (catalog?.isActive == true) {
                runCatching { catalogRepository.namespaces(accountId, bucket) }.getOrDefault(emptyList())
            } else {
                emptyList()
            }
            _uiState.update {
                it.copy(catalog = catalog, catalogNamespaces = namespaces, catalogLoaded = true)
            }
        }
    }

    fun setCatalogEnabled(enabled: Boolean) {
        if (!canWriteCatalog || _uiState.value.isCatalogMutating) return
        viewModelScope.launch {
            _uiState.update { it.copy(isCatalogMutating = true) }
            val accountId = accountStore.selectedAccountId.value
            if (accountId != null) {
                runCatching {
                    if (enabled) {
                        catalogRepository.enable(accountId, bucket)
                    } else {
                        catalogRepository.disable(accountId, bucket)
                    }
                }
                    .onSuccess { loadCatalog() }
                    .onFailure { eventChannel.send(BucketSettingsEvent.Error(it.message)) }
            }
            _uiState.update { it.copy(isCatalogMutating = false) }
        }
    }

}
