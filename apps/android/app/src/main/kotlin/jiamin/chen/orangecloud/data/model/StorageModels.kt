package jiamin.chen.orangecloud.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

// MARK: - R2

/** GET /accounts/{id}/r2/buckets 的 result 是 { buckets: [...] }（不是数组）。 */
@Serializable
data class R2BucketList(val buckets: List<R2Bucket> = emptyList())

@Serializable
data class R2Bucket(
    val name: String,
    @SerialName("creation_date") val creationDate: String? = null,
    val location: String? = null,
    @SerialName("storage_class") val storageClass: String? = null,
    /**
     * 数据驻留区域：default / eu / us / fedramp / fedramp-high。
     * 非 default 的桶，其所有桶级 REST 调用都必须带 cf-r2-jurisdiction 头，否则 CF 当作不存在。
     */
    val jurisdiction: String? = null,
) {
    /** 规整后的区域（缺省 / default 均为 null），用于去重与透传。 */
    val jurisdictionOrNull: String? get() = R2Jurisdiction.normalize(jurisdiction)
}

/** R2 区域限制（jurisdiction）工具。2026-08 起除 EU 外新增 US；FedRAMP 仅政府账户。 */
object R2Jurisdiction {
    const val HEADER = "cf-r2-jurisdiction"

    /** 列表时额外探测的区域（不带头的列表是否包含区域桶并不确定，见规格 W1-5）。 */
    val PROBED: List<String> = listOf("eu", "us")

    fun normalize(raw: String?): String? =
        raw?.trim()?.lowercase()?.takeIf { it.isNotEmpty() && it != "default" }

    /** 桶级请求要带的头；默认区域返回空表。 */
    fun headers(jurisdiction: String?): Map<String, String> =
        normalize(jurisdiction)?.let { mapOf(HEADER to it) } ?: emptyMap()
}

@Serializable
data class R2Object(
    val key: String,
    val etag: String? = null,
    @SerialName("last_modified") val lastModified: String? = null,
    val size: Long? = null,
    @SerialName("http_metadata") val httpMetadata: R2HttpMetadata? = null,
    @SerialName("storage_class") val storageClass: String? = null,
)

@Serializable
data class R2HttpMetadata(val contentType: String? = null)  // R2 对象元数据是 camelCase

// MARK: - D1

@Serializable
data class D1Database(
    val uuid: String,
    val name: String,
    val version: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("file_size") val fileSize: Long? = null,
    @SerialName("num_tables") val numTables: Int? = null,
)

@Serializable
data class D1QueryRequest(
    val sql: String,
    val params: List<String>? = null,
)

/**
 * 新建数据库（POST /accounts/{id}/d1/database）请求体。primaryLocationHint 为空时
 * 不编码进 JSON（explicitNulls=false），由 Cloudflare 就近放置。
 */
@Serializable
data class D1CreateRequest(
    val name: String,
    @SerialName("primary_location_hint") val primaryLocationHint: String? = null,
)

/** PRAGMA table_info 解析后的列结构（运行期结构，非 API 模型）。 */
data class D1Column(
    val name: String,
    val type: String,
    val isPrimaryKey: Boolean,
)

/** POST /query 的 result 是 [D1QueryResult]（每条语句一个结果）。 */
@Serializable
data class D1QueryResult(
    val results: List<Map<String, JsonElement>>? = null,
    val success: Boolean = false,
    val meta: D1QueryMeta? = null,
)

@Serializable
data class D1QueryMeta(
    val duration: Double? = null,
    val changes: Int? = null,
    @SerialName("last_row_id") val lastRowId: Long? = null,
    @SerialName("rows_read") val rowsRead: Int? = null,
    @SerialName("rows_written") val rowsWritten: Int? = null,
)

/** 创建 R2 桶请求体。R2 端点为 camelCase（无 snake 映射，对齐 iOS R2CreateRequest）。 */
@Serializable
data class R2CreateRequest(
    val name: String,
    val locationHint: String? = null,
    val storageClass: String? = null,
)

// MARK: - KV

@Serializable
data class KVNamespace(
    val id: String,
    val title: String,
)

/** 创建 KV 命名空间请求体。 */
@Serializable
data class KVCreateRequest(val title: String)

@Serializable
data class KVKey(
    val name: String,
    val expiration: Long? = null,   // Unix 秒
)

// MARK: - 存储路径编码

/**
 * R2 / KV key 可含任意字符（/ 空格等），按 iOS `.alphanumerics` 口径百分号编码后拼路径；
 * CfApiClient 把 path 视为已编码，OkHttp toHttpUrl 保留 %XX 不二次编码。
 */
fun encodeStorageKey(key: String): String = buildString {
    for (byte in key.encodeToByteArray()) {
        val c = byte.toInt() and 0xFF
        if (c in 0x30..0x39 || c in 0x41..0x5A || c in 0x61..0x7A) {
            append(c.toChar())
        } else {
            append('%').append("%02X".format(c))
        }
    }
}
