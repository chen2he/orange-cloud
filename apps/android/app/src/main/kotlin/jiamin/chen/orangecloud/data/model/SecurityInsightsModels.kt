package jiamin.chen.orangecloud.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// MARK: - 安全洞察（Security Center Insights，全套餐，按需扫描）

/**
 * GET /zones/{id}/security-center/insights 的 result：{ count, page, per_page, issues[] }。
 * 不是标准列表信封（分页信息在 result 里而非 result_info）。
 */
@Serializable
data class SecurityInsightsPage(
    val count: Int? = null,
    val page: Int? = null,
    @SerialName("per_page") val perPage: Int? = null,
    val issues: List<SecurityInsight>? = null,
)

/**
 * 单条安全洞察。枚举字段一律按字符串解码：CF 新增类型 / 严重度时照常显示原文，不崩。
 * severity 在响应里是首字母大写（Low / Moderate / Critical）。
 */
@Serializable
data class SecurityInsight(
    val id: String,
    /** compliance_violation / email_security / exposed_infrastructure / insecure_configuration / weak_authentication / configuration_suggestion */
    @SerialName("issue_type") val issueType: String? = null,
    @SerialName("issue_class") val issueClass: String? = null,
    val severity: String? = null,
    val subject: String? = null,
    /** 问题出现的时间（date-time） */
    val since: String? = null,
    val timestamp: String? = null,
    /** active / resolved */
    val status: String? = null,
    val dismissed: Boolean? = null,
    /** 去处理的链接；以 / 开头的是控制台相对路径，需补 https://dash.cloudflare.com */
    @SerialName("resolve_link") val resolveLink: String? = null,
    @SerialName("resolve_text") val resolveText: String? = null,
    val payload: SecurityInsightPayload? = null,
) {
    /** 严重度档位：用于分组排序（严重 > 中等 > 低 > 未知）。 */
    val severityLevel: SecurityInsightSeverity
        get() = SecurityInsightSeverity.of(severity)

    /** 可直接打开的完整去处理链接；相对路径补控制台域名，其它非 http(s) 链接丢弃。 */
    val resolveUrl: String?
        get() {
            val link = resolveLink?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            return when {
                link.startsWith("/") -> "https://dash.cloudflare.com$link"
                link.startsWith("https://") || link.startsWith("http://") -> link
                else -> null
            }
        }
}

@Serializable
data class SecurityInsightPayload(
    @SerialName("detection_method") val detectionMethod: String? = null,
    @SerialName("zone_tag") val zoneTag: String? = null,
)

/** 严重度（按严重程度降序排列，UNKNOWN 兜底排最后）。 */
enum class SecurityInsightSeverity {
    CRITICAL, MODERATE, LOW, UNKNOWN;

    companion object {
        fun of(raw: String?): SecurityInsightSeverity = when (raw?.trim()?.lowercase()) {
            "critical" -> CRITICAL
            "moderate" -> MODERATE
            "low" -> LOW
            else -> UNKNOWN
        }
    }
}

/** POST .../insights/scans 的请求体：空对象表示扫描全部。 */
@Serializable
class SecurityInsightScanRequest

/** PUT .../insights/{id}/dismiss 请求体。 */
@Serializable
data class SecurityInsightDismissRequest(val dismiss: Boolean = true)
