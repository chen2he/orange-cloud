package jiamin.chen.orangecloud.data.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant
import java.time.temporal.ChronoUnit

// MARK: - 流量分析 adaptive 明细（2026-10-02 起 Free / Pro 的 adaptive 数据集保留 ≥31 天、可查 30 天）
// 现有图表仍走 httpRequests1hGroups / 1dGroups 不动；这里只给「访问明细」「安全事件」两段用。
// 查询前先读 zone settings 里各数据集的 enabled / maxDuration / notOlderThan，据此收窄时间范围或整段隐藏。

/** adaptive 数据集统一用 Time 标量：24h / 7d / 30d 都回溯到「现在」。 */
fun AnalyticsTimeRange.adaptiveWindow(now: Instant = Instant.now()): Pair<Instant, Instant> {
    val until = now.truncatedTo(ChronoUnit.SECONDS)
    val since = when (this) {
        AnalyticsTimeRange.LAST_24H -> until.minus(24, ChronoUnit.HOURS)
        AnalyticsTimeRange.LAST_7D -> until.minus(7, ChronoUnit.DAYS)
        AnalyticsTimeRange.LAST_30D -> until.minus(30, ChronoUnit.DAYS)
    }
    return since to until
}

@Serializable
data class ZoneTagVariables(val zoneTag: String)

// —— zone settings：数据集可用性 ——

@Serializable
data class AdaptiveSettingsData(val viewer: AdaptiveSettingsViewer? = null)

@Serializable
data class AdaptiveSettingsViewer(val zones: List<AdaptiveSettingsZone> = emptyList())

@Serializable
data class AdaptiveSettingsZone(val settings: AdaptiveZoneSettings? = null)

@Serializable
data class AdaptiveZoneSettings(
    val httpRequestsAdaptiveGroups: AdaptiveDatasetSetting? = null,
    val firewallEventsAdaptive: AdaptiveDatasetSetting? = null,
)

/** maxDuration / notOlderThan 单位为秒。 */
@Serializable
data class AdaptiveDatasetSetting(
    val enabled: Boolean? = null,
    val maxDuration: Long? = null,
    val notOlderThan: Long? = null,
) {
    /**
     * 按套餐限制收窄查询窗口：返回 (since, 是否被收窄)；数据集未开放返回 null。
     * 设置读不到（null）时不收窄，交给查询本身报错再降级。
     */
    fun clamp(since: Instant, until: Instant): Pair<Instant, Boolean>? {
        if (enabled == false) return null
        var start = since
        notOlderThan?.takeIf { it > 0 }?.let { start = maxOf(start, until.minusSeconds(it)) }
        maxDuration?.takeIf { it > 0 }?.let { start = maxOf(start, until.minusSeconds(it)) }
        if (!start.isBefore(until)) return null
        return start to (start != since)
    }
}

// —— 分组计数（dimensions 只取一个维度，按 JsonObject 宽松接住：状态码是数字、其余是字符串）——

@Serializable
data class AdaptiveCountGroup(
    val count: Long? = null,
    val dimensions: JsonObject? = null,
) {
    /** 唯一维度的取值文本；空串（如未知国家）返回 null。 */
    val label: String?
        get() = (dimensions?.values?.firstOrNull() as? JsonPrimitive)
            ?.takeIf { it !is JsonNull }?.content?.takeIf { it.isNotBlank() }
}

/** 一条排行：维度取值 + 次数。 */
data class TopItem(val label: String, val count: Long)

fun List<AdaptiveCountGroup>?.toTopItems(): List<TopItem> =
    orEmpty().mapNotNull { g -> g.label?.let { TopItem(it, g.count ?: 0L) } }
        .filter { it.count > 0 }
        .sortedByDescending { it.count }

// —— 访问明细：httpRequestsAdaptiveGroups 按四个维度各取前 10 ——

@Serializable
data class TrafficDetailsData(val viewer: TrafficDetailsViewer? = null)

@Serializable
data class TrafficDetailsViewer(val zones: List<TrafficDetailsZone> = emptyList())

@Serializable
data class TrafficDetailsZone(
    val byCountry: List<AdaptiveCountGroup>? = null,
    val byStatus: List<AdaptiveCountGroup>? = null,
    val byPath: List<AdaptiveCountGroup>? = null,
    val byHost: List<AdaptiveCountGroup>? = null,
)

/** 访问明细的维度（顺序即界面上的切换顺序）。 */
enum class TrafficDimension { COUNTRY, STATUS, PATH, HOST }

data class TrafficDetails(val top: Map<TrafficDimension, List<TopItem>>) {
    val isEmpty: Boolean get() = top.values.all { it.isEmpty() }
}

// —— 安全事件：firewallEventsAdaptiveGroups 按处置 / 来源计数 + 最近 20 条 firewallEventsAdaptive ——

@Serializable
data class SecurityEventsData(val viewer: SecurityEventsViewer? = null)

@Serializable
data class SecurityEventsViewer(val zones: List<SecurityEventsZone> = emptyList())

@Serializable
data class SecurityEventsZone(
    val byAction: List<AdaptiveCountGroup>? = null,
    val bySource: List<AdaptiveCountGroup>? = null,
    val recent: List<FirewallEvent>? = null,
)

@Serializable
data class FirewallEvent(
    val datetime: String? = null,
    val action: String? = null,
    val source: String? = null,
    val clientIP: String? = null,
    val clientCountryName: String? = null,
    val clientRequestPath: String? = null,
    val clientRequestHTTPHost: String? = null,
    val rayName: String? = null,
)

data class SecurityEvents(
    val byAction: List<TopItem>,
    val bySource: List<TopItem>,
    val recent: List<FirewallEvent>,
) {
    val isEmpty: Boolean get() = byAction.isEmpty() && bySource.isEmpty() && recent.isEmpty()
}

/** adaptive 明细的 GraphQL 查询模板。 */
object AdaptiveAnalyticsQueries {
    val SETTINGS = """
        query (${'$'}zoneTag: string!) {
          viewer {
            zones(filter: { zoneTag: ${'$'}zoneTag }) {
              settings {
                httpRequestsAdaptiveGroups { enabled maxDuration notOlderThan }
                firewallEventsAdaptive { enabled maxDuration notOlderThan }
              }
            }
          }
        }
    """.trimIndent()

    private fun topBy(alias: String, dimension: String) = """
              $alias: httpRequestsAdaptiveGroups(
                limit: 10,
                orderBy: [count_DESC],
                filter: { datetime_geq: ${'$'}since, datetime_lt: ${'$'}until }
              ) {
                count
                dimensions { $dimension }
              }
    """

    val TRAFFIC_DETAILS = """
        query (${'$'}zoneTag: string!, ${'$'}since: Time!, ${'$'}until: Time!) {
          viewer {
            zones(filter: { zoneTag: ${'$'}zoneTag }) {
${topBy("byCountry", "clientCountryName")}
${topBy("byStatus", "edgeResponseStatus")}
${topBy("byPath", "clientRequestPath")}
${topBy("byHost", "clientRequestHTTPHost")}
            }
          }
        }
    """.trimIndent()

    val SECURITY_EVENTS = """
        query (${'$'}zoneTag: string!, ${'$'}since: Time!, ${'$'}until: Time!) {
          viewer {
            zones(filter: { zoneTag: ${'$'}zoneTag }) {
              byAction: firewallEventsAdaptiveGroups(
                limit: 10,
                orderBy: [count_DESC],
                filter: { datetime_geq: ${'$'}since, datetime_lt: ${'$'}until }
              ) {
                count
                dimensions { action }
              }
              bySource: firewallEventsAdaptiveGroups(
                limit: 10,
                orderBy: [count_DESC],
                filter: { datetime_geq: ${'$'}since, datetime_lt: ${'$'}until }
              ) {
                count
                dimensions { source }
              }
              recent: firewallEventsAdaptive(
                limit: 20,
                orderBy: [datetime_DESC],
                filter: { datetime_geq: ${'$'}since, datetime_lt: ${'$'}until }
              ) {
                datetime
                action
                source
                clientIP
                clientCountryName
                clientRequestPath
                clientRequestHTTPHost
                rayName
              }
            }
          }
        }
    """.trimIndent()
}
