package jiamin.chen.orangecloud.data.repository

import jiamin.chen.orangecloud.core.network.CfApiClient
import jiamin.chen.orangecloud.data.local.WorkerDao
import jiamin.chen.orangecloud.data.local.toEntity
import jiamin.chen.orangecloud.data.local.toWorker
import jiamin.chen.orangecloud.data.model.WorkerBindingInput
import jiamin.chen.orangecloud.data.model.WorkerContent
import jiamin.chen.orangecloud.data.model.WorkerDeployMetadata
import jiamin.chen.orangecloud.data.model.WorkerDeployment
import jiamin.chen.orangecloud.data.model.WorkerDeploymentsResult
import jiamin.chen.orangecloud.data.model.WorkerCustomDomain
import jiamin.chen.orangecloud.data.model.WorkerCustomDomainInput
import jiamin.chen.orangecloud.data.model.WorkerRoute
import jiamin.chen.orangecloud.data.model.WorkerRouteInput
import jiamin.chen.orangecloud.data.model.WorkerSchedule
import jiamin.chen.orangecloud.data.model.WorkerSchedulesResult
import jiamin.chen.orangecloud.data.model.WorkerScheduleInput
import jiamin.chen.orangecloud.data.model.WorkerPreview
import jiamin.chen.orangecloud.data.model.WorkerScript
import jiamin.chen.orangecloud.data.model.WorkerSecret
import jiamin.chen.orangecloud.data.model.WorkerSecretInput
import jiamin.chen.orangecloud.data.model.WorkerSecretsBulkPatch
import jiamin.chen.orangecloud.data.model.WorkerSettings
import jiamin.chen.orangecloud.data.model.WorkerSettingsPatch
import jiamin.chen.orangecloud.data.model.WorkerAccountSubdomain
import jiamin.chen.orangecloud.data.model.WorkerSubdomain
import jiamin.chen.orangecloud.data.model.WorkerSubdomainInput
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Workers 仓库：Room 为单一可信源，列表刷新后整账号替换缓存（对应 iOS WorkerService + CacheSync）。
 * 脚本配置（变量/密钥/触发器/域名）为会话级即时数据，不入 Room。该列表端点不分页。
 */
@Singleton
class WorkerRepository @Inject constructor(
    private val api: CfApiClient,
    private val workerDao: WorkerDao,
    private val json: Json,
) {
    fun observeWorkers(accountId: String): Flow<List<WorkerScript>> =
        workerDao.observeByAccount(accountId).map { rows -> rows.map { it.toWorker() } }

    suspend fun refreshWorkers(accountId: String) {
        val scripts = api.getList<WorkerScript>("accounts/$accountId/workers/scripts").items
        workerDao.replaceForAccount(accountId, scripts.map { it.toEntity(accountId) })
    }

    /**
     * 新建 / 覆盖一个 module Worker（粘贴的 JS 代码）。PUT 脚本 = multipart（metadata + worker.js 模块）。
     * 对应 iOS WorkerService.deployScript。成功后刷新 Room 列表。
     */
    suspend fun deployScript(accountId: String, name: String, code: String, compatibilityDate: String) {
        val metadata = """{"main_module":"worker.js","compatibility_date":"$compatibilityDate","bindings":[]}"""
        api.putMultipartFile<kotlinx.serialization.json.JsonElement>(
            "accounts/$accountId/workers/scripts/$name",
            metadata, "worker.js", code, "application/javascript+module",
        )
        refreshWorkers(accountId)
    }

    /**
     * 读现有源码用于原地编辑预填。必须走 /content/v2：v1 /content 对 OAuth 认证方案返回 cf=10405，
     * v2 与裸 GET 才放行（真机实测 2026-07-14，issue #55）。响应为 multipart/form-data（module）或裸 JS（service worker）。
     */
    suspend fun content(accountId: String, scriptName: String): WorkerContent {
        val bytes = api.getRaw("accounts/$accountId/workers/scripts/$scriptName/content/v2")
        return WorkerContent.parse(bytes)
    }

    /**
     * 原地编辑：只替换脚本正文，现有绑定按名 inherit 保留（连同读不到值的密钥），兼容性日期/标志沿用旧值。
     * 带 ?bindings_inherit=strict，缺绑定时报错而非静默丢弃。对应 iOS WorkerUploadViewModel.replace。
     */
    suspend fun replaceScript(accountId: String, name: String, code: String, isModule: Boolean) {
        val s = settings(accountId, name)
        val moduleName = "worker.js"
        val metadata = WorkerDeployMetadata(
            mainModule = if (isModule) moduleName else null,
            bodyPart = if (isModule) null else moduleName,
            compatibilityDate = s.compatibilityDate ?: java.time.LocalDate.now(java.time.ZoneOffset.UTC).toString(),
            compatibilityFlags = s.compatibilityFlags,
            bindings = s.inheritedBindings(),
        )
        api.putMultipartFile<kotlinx.serialization.json.JsonElement>(
            "accounts/$accountId/workers/scripts/$name",
            json.encodeToString(WorkerDeployMetadata.serializer(), metadata),
            moduleName, code,
            if (isModule) "application/javascript+module" else "application/javascript",
            query = listOf("bindings_inherit" to "strict"),
        )
        refreshWorkers(accountId)
    }

    /**
     * 删除整个 Worker 脚本（连同其部署、路由绑定）。OAuth 下放行（真机实测 issue #55）。
     * 需 workers-scripts.write。不可撤销。成功后刷新 Room 列表。
     */
    suspend fun deleteScript(accountId: String, name: String) {
        api.delete("accounts/$accountId/workers/scripts/$name")
        refreshWorkers(accountId)
    }

    // MARK: - 部署历史

    /** 部署列表（result.deployments，首项为活跃部署）。 */
    /** 预览（beta，只读）：按部署时间倒序取最近 20 个。 */
    suspend fun previews(accountId: String, workerName: String): List<WorkerPreview> =
        api.getList<WorkerPreview>(
            "accounts/$accountId/workers/workers/$workerName/previews",
            listOf("per_page" to "20", "order_by" to "deployed_on", "order" to "desc"),
        ).items

    suspend fun listDeployments(accountId: String, scriptName: String): List<WorkerDeployment> =
        api.get<WorkerDeploymentsResult>("accounts/$accountId/workers/scripts/$scriptName/deployments").deployments

    /** 删除某次部署（page.write 不需要，需 workers-scripts.write）。活跃部署 Cloudflare 会拒绝删除。 */
    suspend fun deleteDeployment(accountId: String, scriptName: String, deploymentId: String) =
        api.delete("accounts/$accountId/workers/scripts/$scriptName/deployments/$deploymentId")

    // MARK: - 设置（绑定 / 变量）

    /** 脚本设置（绑定 + 兼容性日期/标志）。 */
    suspend fun settings(accountId: String, scriptName: String): WorkerSettings =
        api.get("accounts/$accountId/workers/scripts/$scriptName/settings")

    /**
     * 改绑定（变量）：传入完整新 bindings（变更项为实体，其余 inherit），PATCH settings 不动代码。
     * CF 要求 settings 作为 multipart form part。
     */
    suspend fun patchSettings(accountId: String, scriptName: String, bindings: List<WorkerBindingInput>, settings: WorkerSettings) {
        val patch = WorkerSettingsPatch(
            bindings = bindings,
            compatibilityDate = settings.compatibilityDate,
            compatibilityFlags = settings.compatibilityFlags,
        )
        api.requestMultipartJsonChecked(
            method = "PATCH",
            path = "accounts/$accountId/workers/scripts/$scriptName/settings",
            partName = "settings",
            bodyJson = json.encodeToString(WorkerSettingsPatch.serializer(), patch),
        )
    }

    // MARK: - 密钥

    /** 密钥列表（仅名 + 类型，永不含值）。 */
    suspend fun listSecrets(accountId: String, scriptName: String): List<WorkerSecret> =
        api.getList<WorkerSecret>("accounts/$accountId/workers/scripts/$scriptName/secrets").items

    /** 新建 / 更新密钥。 */
    suspend fun putSecret(accountId: String, scriptName: String, name: String, text: String) =
        api.putChecked("accounts/$accountId/workers/scripts/$scriptName/secrets", WorkerSecretInput(name, text))

    /** 删除密钥。 */
    /** 批量写密钥（secrets-bulk，单次 ≤100 项原子生效；删除走单条端点，见模型注释）。 */
    suspend fun bulkPatchSecrets(accountId: String, scriptName: String, upserts: List<Pair<String, String>>) {
        val body = WorkerSecretsBulkPatch(
            secrets = upserts.associate { (name, text) -> name to WorkerSecretInput(name, text) },
        )
        api.patchChecked("accounts/$accountId/workers/scripts/$scriptName/secrets-bulk", body)
    }

    suspend fun deleteSecret(accountId: String, scriptName: String, name: String) =
        api.delete("accounts/$accountId/workers/scripts/$scriptName/secrets/$name")

    // MARK: - Cron 触发器

    suspend fun schedules(accountId: String, scriptName: String): List<WorkerSchedule> =
        api.get<WorkerSchedulesResult>("accounts/$accountId/workers/scripts/$scriptName/schedules").schedules

    /** 整组替换 Cron（请求体是裸数组 [{cron}]；漏传即删）。 */
    suspend fun putSchedules(accountId: String, scriptName: String, crons: List<String>) =
        api.putChecked("accounts/$accountId/workers/scripts/$scriptName/schedules", crons.map { WorkerScheduleInput(it) })

    // MARK: - 域名 / 路由

    /** workers.dev 子域状态。 */
    suspend fun subdomain(accountId: String, scriptName: String): WorkerSubdomain =
        api.get("accounts/$accountId/workers/scripts/$scriptName/subdomain")

    /** 账号级 workers.dev 子域前缀（拼 <脚本名>.<前缀>.workers.dev）。账号未注册时 subdomain 为 null。 */
    suspend fun accountSubdomain(accountId: String): String? =
        api.get<WorkerAccountSubdomain>("accounts/$accountId/workers/subdomain").subdomain

    /** 切换 workers.dev 子域。 */
    suspend fun setSubdomain(accountId: String, scriptName: String, enabled: Boolean) =
        api.postChecked("accounts/$accountId/workers/scripts/$scriptName/subdomain", WorkerSubdomainInput(enabled))

    /** 该脚本的自定义域（按 service 过滤）。 */
    suspend fun customDomains(accountId: String, scriptName: String): List<WorkerCustomDomain> =
        api.getList<WorkerCustomDomain>("accounts/$accountId/workers/domains", listOf("service" to scriptName)).items

    /** 挂载自定义域到该脚本。 */
    suspend fun attachDomain(accountId: String, scriptName: String, hostname: String, zoneId: String) =
        api.putChecked("accounts/$accountId/workers/domains", WorkerCustomDomainInput(hostname, scriptName, zoneId))

    /** 卸载自定义域。 */
    suspend fun deleteDomain(accountId: String, domainId: String) =
        api.delete("accounts/$accountId/workers/domains/$domainId")

    /** zone 下全部 Worker 路由（调用方按 script 过滤到本脚本）。 */
    suspend fun routes(zoneId: String): List<WorkerRoute> =
        api.getList<WorkerRoute>("zones/$zoneId/workers/routes").items

    /** 新建路由（pattern → script）。 */
    suspend fun createRoute(zoneId: String, pattern: String, scriptName: String) =
        api.postChecked("zones/$zoneId/workers/routes", WorkerRouteInput(pattern, scriptName))

    /** 删除路由。 */
    suspend fun deleteRoute(zoneId: String, routeId: String) =
        api.delete("zones/$zoneId/workers/routes/$routeId")
}
