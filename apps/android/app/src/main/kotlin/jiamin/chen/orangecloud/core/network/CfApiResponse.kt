package jiamin.chen.orangecloud.core.network

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Cloudflare API 通用信封 { result, success, errors, messages, result_info }。
 * 与 iOS Models/CFAPIResponse.swift 对应；这里用单一信封承载可选 result_info（列表端点才有）。
 */
@Serializable
data class CfEnvelope<T>(
    val result: T? = null,
    val success: Boolean = false,
    val errors: List<CfApiError> = emptyList(),
    val messages: List<CfMessage> = emptyList(),
    @SerialName("result_info") val resultInfo: ResultInfo? = null,
)

@Serializable
data class CfApiError(
    val code: Int = 0,
    val message: String = "",
    /** 2026-08-21 起 403 等错误可能附带：该端点所需权限的文档地址。 */
    @SerialName("documentation_url") val documentationUrl: String? = null,
) {
    fun toCfError(): ApiError.CfError = ApiError.CfError(code, message, documentationUrl)
}

@Serializable
data class CfMessage(val code: Int = 0, val message: String = "")

@Serializable
data class ResultInfo(
    // 页码分页（Zone/DNS 等）
    val page: Int? = null,
    @SerialName("per_page") val perPage: Int? = null,
    @SerialName("total_pages") val totalPages: Int? = null,
    val count: Int? = null,
    @SerialName("total_count") val totalCount: Int? = null,
    // 游标分页（R2 对象、KV keys 等）
    val cursor: String? = null,
    @SerialName("is_truncated") val isTruncated: Boolean? = null,
    // R2 带 delimiter 列举时的「文件夹」前缀。实测 CF 返回的键就叫 delimited
    // （不是 delimited_prefixes），与 iOS CFAPIResponse.ResultInfo.delimited 一致。
    @SerialName("delimited") val delimitedPrefixes: List<String>? = null,
    // 对象式游标（Workers Issues 发生记录等）：result_info.cursors.after。
    // 共享信封里用 JsonElement 宽松接住，避免别的端点回成其它形态时整页解码失败。
    val cursors: JsonElement? = null,
) {
    /** cursors.after（下一页游标）；不存在或为空串时 null。 */
    val cursorAfter: String?
        get() = ((cursors as? JsonObject)?.get("after") as? JsonPrimitive)
            ?.takeIf { it.isString }?.content?.takeIf { it.isNotEmpty() }
}

/** 列表端点的解码结果：数据 + 分页信息 */
data class Paged<T>(val items: List<T>, val info: ResultInfo?)

// MARK: - GraphQL（分析端点，信封是 {data, errors}，GraphQL 错误时 HTTP 仍 200）

@Serializable
data class GraphQLRequest<V>(val query: String, val variables: V)

@Serializable
data class GraphQLResponse<D>(
    val data: D? = null,
    val errors: List<GraphQLError> = emptyList(),
)

@Serializable
data class GraphQLError(val message: String = "") {
    /**
     * 账户级数据集未授权。CF 的 GraphQL 不在 extensions 里给结构化码（安卓侧信封没解 extensions），
     * 只能按文案识别——与 DashboardViewModel 早先的判定口径一致，收拢到这里供各处复用。
     */
    val isAuthz: Boolean
        get() = message.lowercase().let { m ->
            "authz" in m || "not authorized" in m || "unauthorized" in m ||
                "permission" in m || "authentication" in m
        }
}
