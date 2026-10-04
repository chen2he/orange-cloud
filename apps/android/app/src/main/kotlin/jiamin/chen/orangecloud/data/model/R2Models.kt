package jiamin.chen.orangecloud.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// MARK: - R2 公开访问 / CORS（桶设置）。对应 iOS 1.4.0 StorageModels R2 升级部分。

/** 托管公开访问 URL（r2.dev）。GET/PUT .../domains/managed */
@Serializable
data class R2ManagedDomain(
    @SerialName("bucketId") val bucketId: String? = null,
    val domain: String? = null,
    val enabled: Boolean? = null,
)

@Serializable
data class R2ManagedDomainUpdate(val enabled: Boolean)

/** 自定义域列表。GET .../domains/custom */
@Serializable
data class R2CustomDomainList(val domains: List<R2CustomDomain>? = null)

@Serializable
data class R2CustomDomain(
    val domain: String,
    val enabled: Boolean? = null,
    val status: R2CustomDomainStatus? = null,
    @SerialName("minTLS") val minTls: String? = null,
)

@Serializable
data class R2CustomDomainStatus(
    val ownership: String? = null,
    val ssl: String? = null,
)

/** 桶 CORS 策略。GET/PUT/DELETE .../cors。PUT 是整组替换。 */
@Serializable
data class R2CorsPolicy(val rules: List<R2CorsRule>? = null)

@Serializable
data class R2CorsRule(
    val id: String? = null,
    val allowed: R2CorsAllowed? = null,
    @SerialName("exposeHeaders") val exposeHeaders: List<String>? = null,
    @SerialName("maxAgeSeconds") val maxAgeSeconds: Int? = null,
)

@Serializable
data class R2CorsAllowed(
    val methods: List<String>? = null,
    val origins: List<String>? = null,
    val headers: List<String>? = null,
)

// MARK: - 文件夹浏览 / 用量（非序列化派生类型）

/** 对象列表一页：对象 + 折叠出的子文件夹前缀 + 下一页游标。 */
data class R2ObjectPage(
    val objects: List<R2Object>,
    val folderPrefixes: List<String>,
    val nextCursor: String?,
)

/** 一个「文件夹」= 某个折叠前缀（形如 a/b/）。name 取相对当前层的末段。 */
data class R2Folder(val prefix: String, val parentPrefix: String) {
    val name: String
        get() {
            val relative = prefix.removePrefix(parentPrefix).trim('/')
            return relative.ifEmpty { prefix.trim('/') }
        }

    companion object {
        fun makeList(prefixes: List<String>, parentPrefix: String): List<R2Folder> =
            prefixes.toSet().filter { it != parentPrefix }.map { R2Folder(it, parentPrefix) }.sortedBy { it.name }

        /** 当前前缀的上一层（去掉末段）。根层返回空串。 */
        fun parentOf(prefix: String): String {
            val trimmed = prefix.trim('/')
            val lastSlash = trimmed.lastIndexOf('/')
            return if (lastSlash < 0) "" else trimmed.substring(0, lastSlash) + "/"
        }
    }
}

/** 每桶用量快照（本月操作 + 当前存储），best-effort GraphQL，authz 挡时为空。 */
data class R2BucketUsage(
    val classARequests: Int = 0,
    val classBRequests: Int = 0,
    val storageBytes: Long = 0,
    val objectCount: Int = 0,
) {
    val totalRequests: Int get() = classARequests + classBRequests
}

// MARK: - R2 带宽（r2BandwidthUsageAdaptiveGroups，近 30 天；不含 < 100 KiB 的传输）

/** 带宽合计（字节）。 */
data class R2Bandwidth(val uploadBytes: Long, val downloadBytes: Long)

/** bucketName 为 null 时不编码（explicitNulls=false），即账户级合计。 */
@Serializable
data class R2BandwidthVariables(
    val accountTag: String,
    val since: String,
    val until: String,
    val bucketName: String? = null,
)

@Serializable
data class R2BandwidthData(val viewer: R2BandwidthViewer? = null)

@Serializable
data class R2BandwidthViewer(val accounts: List<R2BandwidthAccount> = emptyList())

@Serializable
data class R2BandwidthAccount(val r2BandwidthUsageAdaptiveGroups: List<R2BandwidthGroup>? = null)

@Serializable
data class R2BandwidthGroup(val sum: R2BandwidthSum? = null, val dimensions: R2BandwidthDim? = null)

@Serializable
data class R2BandwidthSum(val bytesUpload: Long = 0, val bytesDownload: Long = 0)

@Serializable
data class R2BandwidthDim(val date: String? = null)

// MARK: - 每桶用量 GraphQL（account-analytics，免费账号常被 authz 挡，best-effort）

@Serializable
data class R2UsageVariables(
    val accountTag: String,
    val monthStart: String,
    val todayStart: String,
    val now: String,
)

@Serializable
data class R2UsageData(val viewer: R2UsageViewer? = null)

@Serializable
data class R2UsageViewer(val accounts: List<R2UsageAccount> = emptyList())

@Serializable
data class R2UsageAccount(
    val r2Ops: List<R2OpsGroup>? = null,
    val r2Storage: List<R2StorageGroup>? = null,
)

@Serializable
data class R2OpsGroup(val dimensions: R2OpsDim? = null, val sum: R2OpsSum? = null)

@Serializable
data class R2OpsDim(val actionType: String? = null, val bucketName: String? = null)

@Serializable
data class R2OpsSum(val requests: Long = 0)

@Serializable
data class R2StorageGroup(val dimensions: R2StorageDim? = null, val max: R2StorageMax? = null)

@Serializable
data class R2StorageDim(val bucketName: String? = null)

@Serializable
data class R2StorageMax(
    val payloadSize: Long = 0,
    val metadataSize: Long = 0,
    val objectCount: Int = 0,
)
