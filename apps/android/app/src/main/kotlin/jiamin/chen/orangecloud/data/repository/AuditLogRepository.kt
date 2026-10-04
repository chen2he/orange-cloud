package jiamin.chen.orangecloud.data.repository

import jiamin.chen.orangecloud.core.network.ApiError
import jiamin.chen.orangecloud.core.network.CfApiClient
import jiamin.chen.orangecloud.data.model.AuditLogPage
import kotlinx.serialization.json.Json
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 账号审计日志（Audit Logs v2）只读查询，游标分页。对应 iOS AuditLogService。
 * since / before 为必填时间窗；direction=desc 取最近在前。仅需 account-settings.read。
 * 单独用宽松 Json 解码（v2 的 result_info.count 是字符串，靠 ignoreUnknownKeys 跳过）。
 */
@Singleton
class AuditLogRepository @Inject constructor(
    private val api: CfApiClient,
) {
    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }

    /** 拉取一页审计日志。cursor 为空取首页，非空续接下一页。 */
    suspend fun list(
        accountId: String,
        since: Instant,
        before: Instant,
        cursor: String?,
        limit: Int = 50,
    ): AuditLogPage {
        val query = buildList {
            add("since" to since.toString())
            add("before" to before.toString())
            add("limit" to limit.toString())
            add("direction" to "desc")
            if (!cursor.isNullOrEmpty()) add("cursor" to cursor)
        }
        val bytes = api.getRaw("accounts/$accountId/logs/audit", query)
        val page = runCatching { json.decodeFromString(AuditLogPage.serializer(), bytes.decodeToString()) }
            .getOrElse { throw ApiError.Decoding(it) }
        if (!page.success) {
            throw ApiError.Cloudflare(page.errors.orEmpty().map { it.toCfError() })
        }
        return page
    }
    /**
     * 某条审计日志所对应资源的完整变更序列（2026-07-27 上线）。
     *
     * 接口先用 id + action_time 定位源日志、从中推出资源标识，再回查同一资源的其它日志，
     * 所以 **actionTime 必须传**（用于收窄查找窗口），否则定位不到。
     *
     * result_info.history_status 表示识别质量：exact / approximate / unavailable，需如实透传。
     */
    suspend fun resourceHistory(
        accountId: String,
        entryId: String,
        actionTime: Instant,
        since: Instant,
        before: Instant,
        limit: Int = 50,
    ): AuditLogPage {
        val query = listOf(
            "action_time" to actionTime.toString(),
            "since" to since.toString(),
            "before" to before.toString(),
            "limit" to limit.toString(),
            "direction" to "desc",
        )
        val bytes = api.getRaw("accounts/$accountId/logs/audit/$entryId/history", query)
        val page = runCatching { json.decodeFromString(AuditLogPage.serializer(), bytes.decodeToString()) }
            .getOrElse { throw ApiError.Decoding(it) }
        if (!page.success) {
            throw ApiError.Cloudflare(page.errors.orEmpty().map { it.toCfError() })
        }
        return page
    }

}
