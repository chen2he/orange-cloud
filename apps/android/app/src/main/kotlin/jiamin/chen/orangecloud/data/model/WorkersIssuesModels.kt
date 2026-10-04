package jiamin.chen.orangecloud.data.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import java.time.Instant
import java.time.OffsetDateTime

// MARK: - Workers Issues（可观测性，2026-09-30 公开测试）
// 把 Worker 的未捕获异常、5xx 响应、错误日志归并成「问题」。
// 端点 /accounts/{id}/workers/observability/issues…，字段 camelCase。
// 时间戳是数字（按毫秒；< 1e12 视为秒）。为防 CF 改成字符串，时间字段按 JsonElement 宽松解码。

/** 问题状态。未知值按原文保留，不当作任何一档。 */
object WorkerIssueStatus {
    const val ACTIVE = "active"
    const val RESOLVED = "resolved"
    const val IGNORED = "ignored"
    val filters: List<String> = listOf(ACTIVE, RESOLVED, IGNORED)
}

@Serializable
data class WorkerIssue(
    val id: String,
    val title: String? = null,
    /** Worker 名 */
    val service: String? = null,
    val status: String? = null,
    val count: Long? = null,
    val firstObserved: JsonElement? = null,
    val lastObserved: JsonElement? = null,
    val statusUpdated: JsonElement? = null,
    val created: JsonElement? = null,
    val updated: JsonElement? = null,
    val type: String? = null,
    val fingerprint: String? = null,
) {
    val firstObservedMillis: Long? get() = epochMillisOf(firstObserved)
    val lastObservedMillis: Long? get() = epochMillisOf(lastObserved)
}

/** GET …/issues/{id} 的 result：{ issue: {...} }。 */
@Serializable
data class WorkerIssueEnvelope(val issue: WorkerIssue? = null)

/** GET …/issues/summary 的 result。lastIssue 为最近一次问题的时间（可能为 null）。 */
@Serializable
data class WorkerIssuesSummary(
    val activeIssues: Long? = null,
    val activeOccurrences: Long? = null,
    val resolvedIssues: Long? = null,
    val lastIssue: JsonElement? = null,
)

/** PATCH …/issues/{id} 请求体。 */
@Serializable
data class WorkerIssueStatusUpdate(val status: String)

/** 单次发生（GET …/issues/{id}/occurrences，游标分页 result_info.cursors.after）。 */
@Serializable
data class WorkerIssueOccurrence(
    val id: String? = null,
    val timestamp: JsonElement? = null,
    val error: WorkerIssueError? = null,
    val invocation: WorkerIssueInvocation? = null,
    val trail: List<WorkerIssueTrailEntry>? = null,
) {
    val timestampMillis: Long? get() = epochMillisOf(timestamp)
}

@Serializable
data class WorkerIssueError(
    val name: String? = null,
    val message: String? = null,
    val stack: String? = null,
    val handled: Boolean? = null,
    /** 形态未定（字符串或对象），原样保留。 */
    val mechanism: JsonElement? = null,
)

@Serializable
data class WorkerIssueInvocation(
    val method: String? = null,
    val path: String? = null,
    val url: String? = null,
    val statusCode: Int? = null,
    val rayId: String? = null,
    val cron: String? = null,
    val queue: String? = null,
    /** fetch / scheduled / queue … */
    val type: String? = null,
)

@Serializable
data class WorkerIssueTrailEntry(
    val level: String? = null,
    val message: String? = null,
    val timestamp: JsonElement? = null,
)

/** 发生记录一页 + 下一页游标（null = 到底）。 */
data class WorkerIssueOccurrencePage(
    val items: List<WorkerIssueOccurrence>,
    val nextCursor: String?,
)

/**
 * 宽松解析时间戳：数字按毫秒（< 1e12 视为秒）；数字字符串同理；ISO 8601 字符串也接受。
 * 其余（null / 对象 / 布尔）返回 null。
 */
fun epochMillisOf(value: JsonElement?): Long? {
    val prim = value as? JsonPrimitive ?: return null
    if (prim.booleanOrNull != null && !prim.isString) return null
    val number = prim.doubleOrNull
    if (number != null) {
        if (number <= 0.0) return null
        return if (number < 1e12) (number * 1000).toLong() else number.toLong()
    }
    val text = prim.contentOrNull?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    return runCatching { Instant.parse(text).toEpochMilli() }.getOrNull()
        ?: runCatching { OffsetDateTime.parse(text).toInstant().toEpochMilli() }.getOrNull()
}
