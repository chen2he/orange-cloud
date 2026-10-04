package jiamin.chen.orangecloud.data.repository

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import jiamin.chen.orangecloud.core.network.CfApiClient
import jiamin.chen.orangecloud.data.model.D1CreateRequest
import jiamin.chen.orangecloud.data.model.D1Database
import jiamin.chen.orangecloud.data.model.D1QueryRequest
import jiamin.chen.orangecloud.data.model.D1QueryResult
import jiamin.chen.orangecloud.data.model.KVCreateRequest
import jiamin.chen.orangecloud.data.model.KVKey
import jiamin.chen.orangecloud.data.model.KVNamespace
import jiamin.chen.orangecloud.data.model.R2Bucket
import jiamin.chen.orangecloud.data.model.R2BucketList
import jiamin.chen.orangecloud.data.model.R2CreateRequest
import jiamin.chen.orangecloud.data.model.R2BucketUsage
import jiamin.chen.orangecloud.data.model.R2CorsPolicy
import jiamin.chen.orangecloud.data.model.R2CustomDomain
import jiamin.chen.orangecloud.data.model.R2CustomDomainList
import jiamin.chen.orangecloud.data.model.R2ManagedDomain
import jiamin.chen.orangecloud.data.model.R2ManagedDomainUpdate
import jiamin.chen.orangecloud.data.model.R2Jurisdiction
import jiamin.chen.orangecloud.data.model.R2Object
import jiamin.chen.orangecloud.data.model.R2ObjectPage
import jiamin.chen.orangecloud.data.model.R2UsageData
import jiamin.chen.orangecloud.data.model.R2UsageVariables
import jiamin.chen.orangecloud.data.model.encodeStorageKey
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import java.io.File
import java.time.Instant
import java.time.ZoneOffset
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 存储仓库：R2 / D1 / KV（对应 iOS R2Service / D1Service / KVService）。
 * 派生/会话级数据不入 Room；游标分页一次一页，key 显式百分号编码。
 */
@Singleton
class StorageRepository @Inject constructor(
    @ApplicationContext private val context: Context,
    private val api: CfApiClient,
) {
    // MARK: - R2

    /** client/v4 单次 PUT 上限（~300MB）；超过无法在本 App 复制/上传（无 multipart / 服务端 copy）。 */
    val maxUploadBytes: Long = 300L * 1024 * 1024

    /**
     * 全部存储桶（含区域限制桶）。不带头的列表是否包含 EU / US 区域桶并不确定，
     * 故再分别带 cf-r2-jurisdiction: eu / us 各列一次（失败忽略），按 (name, jurisdiction) 合并去重。
     * 主列表失败照常抛出；探测列表回来的桶若缺 jurisdiction 字段，用探测的区域补上。
     * 同名桶可分属不同区域，故全程以 (name, jurisdiction) 而非 name 识别一个桶。
     */
    suspend fun listBuckets(accountId: String): List<R2Bucket> = coroutineScope {
        val path = "accounts/$accountId/r2/buckets"
        val query = listOf("per_page" to "100")
        val probes = R2Jurisdiction.PROBED.map { j ->
            async {
                runCatching {
                    api.get<R2BucketList>(path, query, R2Jurisdiction.headers(j)).buckets
                        // 只在字段缺失时补；回了 "default" 说明服务端忽略了头，原样保留以便与主列表去重
                        .map { if (it.jurisdiction == null) it.copy(jurisdiction = j) else it }
                }.getOrElse { if (it is CancellationException) throw it; emptyList() }
            }
        }
        val primary = api.get<R2BucketList>(path, query).buckets
        (primary + probes.awaitAll().flatten()).distinctBy { it.name to it.jurisdictionOrNull }
    }

    /** 创建 R2 桶（workers-r2-storage.write）。名称须小写字母/数字/连字符，3–63 位。 */
    suspend fun createBucket(accountId: String, name: String): R2Bucket =
        api.post("accounts/$accountId/r2/buckets", R2CreateRequest(name))

    /** 删除 R2 桶（workers-r2-storage.write）。Cloudflare 要求桶必须为空，否则报错。不可恢复。 */
    suspend fun deleteBucket(accountId: String, name: String, jurisdiction: String? = null) =
        api.delete("accounts/$accountId/r2/buckets/$name", R2Jurisdiction.headers(jurisdiction))

    /**
     * 对象列表一页。传 delimiter=/ 让服务端把子前缀折叠成「文件夹」，prefix 为当前所在文件夹；
     * result_info.delimited 即子文件夹前缀列表。
     */
    suspend fun listObjects(
        accountId: String,
        bucket: String,
        prefix: String,
        cursor: String?,
        jurisdiction: String? = null,
    ): R2ObjectPage {
        val query = buildList {
            add("per_page" to "100")
            add("delimiter" to "/")
            if (prefix.isNotEmpty()) add("prefix" to prefix)
            cursor?.let { add("cursor" to it) }
        }
        val paged = api.getList<R2Object>(
            "accounts/$accountId/r2/buckets/$bucket/objects",
            query,
            R2Jurisdiction.headers(jurisdiction),
        )
        val next = if (paged.info?.isTruncated == true) paged.info?.cursor else null
        return R2ObjectPage(paged.items, paged.info?.delimitedPrefixes.orEmpty(), next)
    }

    suspend fun getObjectBytes(accountId: String, bucket: String, key: String, jurisdiction: String? = null): ByteArray =
        api.getRaw(
            "accounts/$accountId/r2/buckets/$bucket/objects/${encodeStorageKey(key)}",
            headers = R2Jurisdiction.headers(jurisdiction),
        )

    /** 上传对象（原始字节 PUT，自带 Content-Type；result 可能为 null 故只校验 success）。 */
    suspend fun putObject(
        accountId: String,
        bucket: String,
        key: String,
        bytes: ByteArray,
        contentType: String,
        jurisdiction: String? = null,
    ) = api.putRawVoid(
        "accounts/$accountId/r2/buckets/$bucket/objects/${encodeStorageKey(key)}",
        bytes,
        contentType,
        R2Jurisdiction.headers(jurisdiction),
    )

    suspend fun deleteObject(accountId: String, bucket: String, key: String, jurisdiction: String? = null) =
        api.delete(
            "accounts/$accountId/r2/buckets/$bucket/objects/${encodeStorageKey(key)}",
            R2Jurisdiction.headers(jurisdiction),
        )

    /**
     * 流式复制对象到新 key（同桶，过临时文件不入内存）。onProgress 0→0.5 下载、0.5→1 上传。
     * client/v4 无服务端 copy / multipart，只能过设备；超 maxUploadBytes 无法复制。
     */
    suspend fun copyObject(
        accountId: String, bucket: String, sourceKey: String, destKey: String,
        contentType: String, jurisdiction: String? = null, onProgress: (Float) -> Unit,
    ) {
        val base = "accounts/$accountId/r2/buckets/$bucket/objects"
        val headers = R2Jurisdiction.headers(jurisdiction)
        val temp = File.createTempFile("r2copy", null, context.cacheDir)
        try {
            onProgress(0f)
            api.downloadToFile("$base/${encodeStorageKey(sourceKey)}", temp, headers)
            onProgress(0.5f)
            api.putFile("$base/${encodeStorageKey(destKey)}", temp, contentType, headers)
            onProgress(1f)
        } finally {
            temp.delete()
        }
    }

    /** 精确判断某 key 是否存在（client/v4 对象端点无 HEAD，用 prefix 列举核对）。 */
    suspend fun objectExists(accountId: String, bucket: String, key: String, jurisdiction: String? = null): Boolean =
        listObjects(accountId, bucket, prefix = key, cursor = null, jurisdiction = jurisdiction).objects.any { it.key == key }

    // MARK: - R2 桶设置（公开访问 / CORS）

    private fun bucketPath(accountId: String, bucket: String) = "accounts/$accountId/r2/buckets/$bucket"

    // 以下桶级调用都透传 jurisdiction：区域限制桶不带 cf-r2-jurisdiction 头会被当成不存在
    suspend fun managedDomain(accountId: String, bucket: String, jurisdiction: String? = null): R2ManagedDomain =
        api.get("${bucketPath(accountId, bucket)}/domains/managed", headers = R2Jurisdiction.headers(jurisdiction))

    suspend fun setManagedDomainEnabled(accountId: String, bucket: String, enabled: Boolean, jurisdiction: String? = null) =
        api.putChecked(
            "${bucketPath(accountId, bucket)}/domains/managed",
            R2ManagedDomainUpdate(enabled),
            R2Jurisdiction.headers(jurisdiction),
        )

    suspend fun customDomains(accountId: String, bucket: String, jurisdiction: String? = null): List<R2CustomDomain> =
        api.get<R2CustomDomainList>(
            "${bucketPath(accountId, bucket)}/domains/custom",
            headers = R2Jurisdiction.headers(jurisdiction),
        ).domains.orEmpty()

    suspend fun removeCustomDomain(accountId: String, bucket: String, domain: String, jurisdiction: String? = null) =
        api.delete(
            "${bucketPath(accountId, bucket)}/domains/custom/${encodeStorageKey(domain)}",
            R2Jurisdiction.headers(jurisdiction),
        )

    /** 当前 CORS 策略（无策略时返回空 rules）。 */
    suspend fun corsPolicy(accountId: String, bucket: String, jurisdiction: String? = null): R2CorsPolicy =
        runCatching {
            api.get<R2CorsPolicy>("${bucketPath(accountId, bucket)}/cors", headers = R2Jurisdiction.headers(jurisdiction))
        }.getOrDefault(R2CorsPolicy())

    /** 整组写入 CORS 策略（PUT 覆盖）。 */
    suspend fun putCorsPolicy(accountId: String, bucket: String, policy: R2CorsPolicy, jurisdiction: String? = null) =
        api.putChecked("${bucketPath(accountId, bucket)}/cors", policy, R2Jurisdiction.headers(jurisdiction))

    suspend fun deleteCorsPolicy(accountId: String, bucket: String, jurisdiction: String? = null) =
        api.delete("${bucketPath(accountId, bucket)}/cors", R2Jurisdiction.headers(jurisdiction))

    /**
     * 每桶用量（本月操作 Class A/B + 当前存储快照），account-analytics GraphQL。
     * 免费账号 / 无 R2 数据集权限时会被 authz 挡 → 调用方 best-effort 接住，返回空表。
     * 对齐 iOS AnalyticsService.r2UsageByBucket。
     */
    suspend fun r2UsageByBucket(accountId: String): Map<String, R2BucketUsage> {
        val now = Instant.now()
        val today = now.atZone(ZoneOffset.UTC).toLocalDate()
        val monthStart = today.withDayOfMonth(1).atStartOfDay(ZoneOffset.UTC).toInstant().toString()
        val todayStart = today.atStartOfDay(ZoneOffset.UTC).toInstant().toString()
        val data = api.graphQL<R2UsageData, R2UsageVariables>(
            R2_USAGE_QUERY,
            R2UsageVariables(accountId, monthStart, todayStart, now.toString()),
        )
        val account = data.viewer?.accounts?.firstOrNull() ?: return emptyMap()
        val map = mutableMapOf<String, R2BucketUsage>()
        account.r2Storage?.forEach { g ->
            val b = g.dimensions?.bucketName?.takeIf { it.isNotEmpty() } ?: return@forEach
            val cur = map[b] ?: R2BucketUsage()
            map[b] = cur.copy(
                storageBytes = (g.max?.payloadSize ?: 0) + (g.max?.metadataSize ?: 0),
                objectCount = g.max?.objectCount ?: 0,
            )
        }
        account.r2Ops?.forEach { g ->
            val b = g.dimensions?.bucketName?.takeIf { it.isNotEmpty() } ?: return@forEach
            val cur = map[b] ?: R2BucketUsage()
            val req = (g.sum?.requests ?: 0L).toInt()
            map[b] = if (isClassB(g.dimensions?.actionType)) {
                cur.copy(classBRequests = cur.classBRequests + req)
            } else {
                cur.copy(classARequests = cur.classARequests + req)
            }
        }
        return map
    }

    /** R2 Class B（读类）操作；其余计入 Class A。 */
    private fun isClassB(actionType: String?): Boolean = actionType in CLASS_B_ACTIONS

    companion object {
        private val CLASS_B_ACTIONS = setOf(
            "GetObject", "HeadObject", "HeadBucket", "UsageSummary",
            "GetBucketEncryption", "GetBucketLocation", "GetBucketCors", "GetBucketLifecycleConfiguration",
        )

        private val R2_USAGE_QUERY = """
            query (${'$'}accountTag: string!, ${'$'}monthStart: Time!, ${'$'}todayStart: Time!, ${'$'}now: Time!) {
              viewer {
                accounts(filter: { accountTag: ${'$'}accountTag }) {
                  r2Ops: r2OperationsAdaptiveGroups(
                    limit: 10000,
                    filter: { datetime_geq: ${'$'}monthStart, datetime_leq: ${'$'}now }
                  ) {
                    dimensions { actionType bucketName }
                    sum { requests }
                  }
                  r2Storage: r2StorageAdaptiveGroups(
                    limit: 1000,
                    filter: { datetime_geq: ${'$'}todayStart, datetime_leq: ${'$'}now }
                  ) {
                    dimensions { bucketName }
                    max { payloadSize metadataSize objectCount }
                  }
                }
              }
            }
        """.trimIndent()
    }

    // MARK: - D1

    suspend fun listDatabases(accountId: String): List<D1Database> {
        val all = mutableListOf<D1Database>()
        var page = 1
        while (true) {
            val paged = api.getList<D1Database>(
                "accounts/$accountId/d1/database",
                listOf("page" to page.toString(), "per_page" to "100"),
            )
            all += paged.items
            if (page >= (paged.info?.totalPages ?: 1)) break
            page++
        }
        return all
    }

    /**
     * 数据库详情。列表端点不返回 file_size / num_tables 的真实值（常年 0），
     * 这两个字段以详情端点为准（对齐 iOS D1Service.getDatabase）。
     */
    suspend fun getDatabase(accountId: String, databaseId: String): D1Database =
        api.get("accounts/$accountId/d1/database/$databaseId")

    /** 创建数据库。locationHint 为空走自动放置。 */
    suspend fun createDatabase(accountId: String, name: String, locationHint: String?): D1Database =
        api.post("accounts/$accountId/d1/database", D1CreateRequest(name, locationHint))

    /** 删除数据库（连同全部表与数据，不可恢复）。 */
    suspend fun deleteDatabase(accountId: String, databaseId: String) =
        api.delete("accounts/$accountId/d1/database/$databaseId")

    /** 执行 SQL（每条语句一个结果）。 */
    suspend fun query(accountId: String, databaseId: String, sql: String, params: List<String>? = null): List<D1QueryResult> =
        api.post("accounts/$accountId/d1/database/$databaseId/query", D1QueryRequest(sql, params))

    // MARK: - KV

    suspend fun listNamespaces(accountId: String): List<KVNamespace> {
        val all = mutableListOf<KVNamespace>()
        var page = 1
        while (true) {
            val paged = api.getList<KVNamespace>(
                "accounts/$accountId/storage/kv/namespaces",
                listOf("page" to page.toString(), "per_page" to "100"),
            )
            all += paged.items
            if (page >= (paged.info?.totalPages ?: 1)) break
            page++
        }
        return all
    }

    /** 创建 KV 命名空间（workers-kv-storage.write）。POST 返回新建的命名空间。 */
    suspend fun createNamespace(accountId: String, title: String): KVNamespace =
        api.post("accounts/$accountId/storage/kv/namespaces", KVCreateRequest(title))

    /** 删除 KV 命名空间（workers-kv-storage.write）。连同全部键值，不可恢复。 */
    suspend fun deleteNamespace(accountId: String, namespaceId: String) =
        api.delete("accounts/$accountId/storage/kv/namespaces/$namespaceId")

    /** 键列表（游标分页，一次一页）。cursor 为空串表示已到末尾。 */
    suspend fun listKeys(accountId: String, namespaceId: String, cursor: String?): Pair<List<KVKey>, String?> {
        val query = buildList {
            add("limit" to "100")
            cursor?.let { add("cursor" to it) }
        }
        val paged = api.getList<KVKey>("accounts/$accountId/storage/kv/namespaces/$namespaceId/keys", query)
        val next = paged.info?.cursor?.takeIf { it.isNotEmpty() }
        return paged.items to next
    }

    suspend fun getValue(accountId: String, namespaceId: String, key: String): ByteArray =
        api.getRaw("accounts/$accountId/storage/kv/namespaces/$namespaceId/values/${encodeStorageKey(key)}")

    /** 写文本值（multipart：value + metadata 两个 part 必填）。 */
    suspend fun putValue(accountId: String, namespaceId: String, key: String, value: String) =
        api.putMultipartVoid(
            "accounts/$accountId/storage/kv/namespaces/$namespaceId/values/${encodeStorageKey(key)}",
            mapOf("value" to value, "metadata" to "{}"),
        )

    suspend fun deleteKey(accountId: String, namespaceId: String, key: String) =
        api.delete("accounts/$accountId/storage/kv/namespaces/$namespaceId/values/${encodeStorageKey(key)}")
}
