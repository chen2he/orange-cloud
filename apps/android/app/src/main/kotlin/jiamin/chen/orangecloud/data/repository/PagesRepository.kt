package jiamin.chen.orangecloud.data.repository

import jiamin.chen.orangecloud.core.crypto.Blake3
import jiamin.chen.orangecloud.core.network.ApiError
import jiamin.chen.orangecloud.core.network.CfApiClient
import jiamin.chen.orangecloud.core.network.CfEnvelope
import jiamin.chen.orangecloud.data.model.PagesAssetMetadata
import jiamin.chen.orangecloud.data.model.PagesAssetUpload
import jiamin.chen.orangecloud.data.model.PagesCreateRequest
import jiamin.chen.orangecloud.data.model.PagesDeployFile
import jiamin.chen.orangecloud.data.model.PagesDeployment
import jiamin.chen.orangecloud.data.model.PagesDomain
import jiamin.chen.orangecloud.data.model.PagesDomainAddRequest
import jiamin.chen.orangecloud.data.model.PagesEmptyBody
import jiamin.chen.orangecloud.data.model.PagesHashesBody
import jiamin.chen.orangecloud.data.model.PagesProject
import jiamin.chen.orangecloud.data.model.PagesProjectUpdate
import jiamin.chen.orangecloud.data.model.PagesUploadToken
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import java.util.Base64
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Cloudflare Pages（account 级）：项目与部署。对应 iOS PagesService。读 page.read，写 page.write。
 * CF Pages 列表端点只认 `page`（传 per_page 会被拒），故逐页取靠 total_pages 收尾。
 */
@Singleton
class PagesRepository @Inject constructor(
    private val api: CfApiClient,
) {
    suspend fun listProjects(accountId: String): List<PagesProject> {
        val all = mutableListOf<PagesProject>()
        var page = 1
        while (true) {
            val paged = api.getList<PagesProject>(
                "accounts/$accountId/pages/projects",
                listOf("page" to page.toString()),
            )
            all += paged.items
            val totalPages = paged.info?.totalPages ?: 1
            if (page >= totalPages || paged.items.isEmpty() || page >= 20) break
            page++
        }
        return all
    }

    suspend fun getProject(accountId: String, projectName: String): PagesProject =
        api.get("accounts/$accountId/pages/projects/$projectName")

    suspend fun createProject(accountId: String, name: String, productionBranch: String): PagesProject =
        api.post("accounts/$accountId/pages/projects", PagesCreateRequest(name, productionBranch))

    suspend fun updateProject(accountId: String, projectName: String, update: PagesProjectUpdate): PagesProject =
        api.patch("accounts/$accountId/pages/projects/$projectName", update)

    suspend fun deleteProject(accountId: String, projectName: String) =
        api.delete("accounts/$accountId/pages/projects/$projectName")

    suspend fun listDeployments(accountId: String, projectName: String): List<PagesDeployment> {
        val all = mutableListOf<PagesDeployment>()
        var page = 1
        while (true) {
            val paged = api.getList<PagesDeployment>(
                "accounts/$accountId/pages/projects/$projectName/deployments",
                listOf("page" to page.toString()),
            )
            all += paged.items
            val totalPages = paged.info?.totalPages ?: 1
            if (page >= totalPages || paged.items.isEmpty() || page >= 10) break
            page++
        }
        return all
    }

    // MARK: - 自定义域名

    /** 项目自定义域名列表。 */
    suspend fun listDomains(accountId: String, projectName: String): List<PagesDomain> =
        api.getList<PagesDomain>("accounts/$accountId/pages/projects/$projectName/domains").items

    /** 挂载自定义域名（page.write）。挂载后仍需 DNS 指向 <project>.pages.dev 才能生效。 */
    suspend fun addDomain(accountId: String, projectName: String, name: String): PagesDomain =
        api.post("accounts/$accountId/pages/projects/$projectName/domains", PagesDomainAddRequest(name))

    /** 重新验证域名（PATCH 触发重试；DNS 记录补好后用它催一次）。 */
    suspend fun retryDomain(accountId: String, projectName: String, domainName: String) {
        api.patch<kotlinx.serialization.json.JsonElement, PagesEmptyBody>(
            "accounts/$accountId/pages/projects/$projectName/domains/$domainName", PagesEmptyBody(),
        )
    }

    /** 从项目移除自定义域名（不动 DNS 记录）。 */
    suspend fun deleteDomain(accountId: String, projectName: String, domainName: String) =
        api.delete("accounts/$accountId/pages/projects/$projectName/domains/$domainName")

    /** 重试部署（重新构建并部署）。 */
    suspend fun retryDeployment(accountId: String, projectName: String, deploymentId: String): PagesDeployment =
        api.post("accounts/$accountId/pages/projects/$projectName/deployments/$deploymentId/retry", PagesEmptyBody())

    /** 回滚到某次部署（使其重新生效）。 */
    suspend fun rollbackDeployment(accountId: String, projectName: String, deploymentId: String): PagesDeployment =
        api.post("accounts/$accountId/pages/projects/$projectName/deployments/$deploymentId/rollback", PagesEmptyBody())

    /** 删除某次部署（page.write）。当前生产部署不可删，Cloudflare 会拒绝。不可恢复。 */
    suspend fun deleteDeployment(accountId: String, projectName: String, deploymentId: String) =
        api.delete("accounts/$accountId/pages/projects/$projectName/deployments/$deploymentId")

    // MARK: - 直接上传部署（Direct Upload）
    // 流程对齐 wrangler：取上传 JWT → check-missing 问缺哪些资源 → 缺的 base64 分批 upload
    // → upsert-hashes 关联全部哈希 → 带 manifest（路径→blake3 哈希）创建部署。资源端点用 JWT 鉴权。

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    /** 单文件上限 25 MiB（同 Pages）。 */
    val maxFileBytes = 25 * 1024 * 1024

    private suspend fun uploadToken(accountId: String, projectName: String): String =
        api.get<PagesUploadToken>("accounts/$accountId/pages/projects/$projectName/upload-token").jwt

    private suspend fun checkMissing(jwt: String, hashes: List<String>): List<String> {
        val body = json.encodeToString(PagesHashesBody.serializer(), PagesHashesBody(hashes)).encodeToByteArray()
        val bytes = api.bearerJson("POST", "pages/assets/check-missing", jwt, body)
        val env = json.decodeFromString(CfEnvelope.serializer(ListSerializer(String.serializer())), bytes.decodeToString())
        if (!env.success) throw ApiError.Cloudflare(env.errors.map { it.toCfError() })
        return env.result ?: emptyList()
    }

    private suspend fun uploadBatch(jwt: String, payloads: List<PagesAssetUpload>) {
        val body = json.encodeToString(ListSerializer(PagesAssetUpload.serializer()), payloads).encodeToByteArray()
        api.bearerJson("POST", "pages/assets/upload", jwt, body)
    }

    private suspend fun upsertHashes(jwt: String, hashes: List<String>) {
        val body = json.encodeToString(PagesHashesBody.serializer(), PagesHashesBody(hashes)).encodeToByteArray()
        api.bearerJson("POST", "pages/assets/upsert-hashes", jwt, body)
    }

    private suspend fun createDeployment(accountId: String, projectName: String, manifest: Map<String, String>): PagesDeployment {
        val manifestJson = json.encodeToString(kotlinx.serialization.builtins.MapSerializer(String.serializer(), String.serializer()), manifest)
        return api.postMultipart("accounts/$accountId/pages/projects/$projectName/deployments", mapOf("manifest" to manifestJson))
    }

    /**
     * 整套直接上传部署：算 blake3 manifest → check-missing → 分批传 → upsert → 建部署。
     * onProgress(uploaded, total) 报上传进度。返回新部署。
     */
    suspend fun deployFiles(
        accountId: String,
        projectName: String,
        files: List<PagesDeployFile>,
        onProgress: (uploaded: Int, total: Int) -> Unit,
    ): PagesDeployment {
        val manifest = LinkedHashMap<String, String>()
        val fileByHash = HashMap<String, PagesDeployFile>()
        val b64ByHash = HashMap<String, String>()
        for (f in files) {
            val ext = f.path.substringAfterLast('.', "")
            val b64 = Base64.getEncoder().encodeToString(f.data)
            val hash = Blake3.hashHexPrefix((b64 + ext).toByteArray(Charsets.UTF_8), 32)
            manifest[f.path] = hash
            fileByHash[hash] = f
            b64ByHash[hash] = b64
        }
        val jwt = uploadToken(accountId, projectName)
        val allHashes = manifest.values.toSet().toList()
        val missing = checkMissing(jwt, allHashes)
        val uploads = missing.mapNotNull { h -> fileByHash[h]?.let { f -> Triple(h, f, b64ByHash.getValue(h)) } }
        onProgress(0, uploads.size)
        var done = 0
        for (batch in batchUploads(uploads)) {
            val payloads = batch.map { (h, file, b64) -> PagesAssetUpload(h, b64, PagesAssetMetadata(file.contentType), true) }
            uploadBatch(jwt, payloads)
            done += batch.size
            onProgress(done, uploads.size)
        }
        upsertHashes(jwt, allHashes)
        return createDeployment(accountId, projectName, manifest)
    }

    /** 按累计原始字节（~8MB）或 50 个一批。 */
    private fun batchUploads(uploads: List<Triple<String, PagesDeployFile, String>>): List<List<Triple<String, PagesDeployFile, String>>> {
        val maxBytes = 8 * 1024 * 1024
        val maxCount = 50
        val result = ArrayList<List<Triple<String, PagesDeployFile, String>>>()
        var current = ArrayList<Triple<String, PagesDeployFile, String>>()
        var bytes = 0
        for (item in uploads) {
            val size = item.second.data.size
            if (current.isNotEmpty() && (bytes + size > maxBytes || current.size >= maxCount)) {
                result.add(current); current = ArrayList(); bytes = 0
            }
            current.add(item); bytes += size
        }
        if (current.isNotEmpty()) result.add(current)
        return result
    }
}
