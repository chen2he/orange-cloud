package jiamin.chen.orangecloud.data.repository

import jiamin.chen.orangecloud.core.network.CfApiClient
import jiamin.chen.orangecloud.data.model.AccountUsage
import jiamin.chen.orangecloud.data.model.AccountUsageData
import jiamin.chen.orangecloud.data.model.AccountUsageQueries
import jiamin.chen.orangecloud.data.model.AccountUsageVariables
import jiamin.chen.orangecloud.data.model.AdaptiveAnalyticsQueries
import jiamin.chen.orangecloud.data.model.AdaptiveSettingsData
import jiamin.chen.orangecloud.data.model.AdaptiveZoneSettings
import jiamin.chen.orangecloud.data.model.SecurityEvents
import jiamin.chen.orangecloud.data.model.SecurityEventsData
import jiamin.chen.orangecloud.data.model.TrafficDetails
import jiamin.chen.orangecloud.data.model.TrafficDetailsData
import jiamin.chen.orangecloud.data.model.TrafficDimension
import jiamin.chen.orangecloud.data.model.ZoneTagVariables
import jiamin.chen.orangecloud.data.model.toTopItems
import jiamin.chen.orangecloud.data.model.AnalyticsGroup
import jiamin.chen.orangecloud.data.model.AnalyticsQueries
import jiamin.chen.orangecloud.data.model.AnalyticsTimeRange
import jiamin.chen.orangecloud.data.model.D1Usage
import jiamin.chen.orangecloud.data.model.D1UsageData
import jiamin.chen.orangecloud.data.model.D1UsageGroup
import jiamin.chen.orangecloud.data.model.D1UsageVariables
import jiamin.chen.orangecloud.data.model.KVOpsGroup
import jiamin.chen.orangecloud.data.model.KVUsage
import jiamin.chen.orangecloud.data.model.KVUsageData
import jiamin.chen.orangecloud.data.model.R2_CLASS_B_ACTIONS
import jiamin.chen.orangecloud.data.model.R2UsageData
import jiamin.chen.orangecloud.data.model.R2UsageVariables
import jiamin.chen.orangecloud.data.model.TrafficDataPoint
import jiamin.chen.orangecloud.data.model.WorkersCpuData
import jiamin.chen.orangecloud.data.model.ZoneAnalyticsData
import jiamin.chen.orangecloud.data.model.ZoneAnalyticsVariables
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Zone 流量分析：GraphQL Analytics API → 归一化数据点（对应 iOS AnalyticsService.zoneTraffic）。
 * 分析为只读派生数据，不入 Room；按时间范围在 ViewModel 会话级缓存。
 */
@Singleton
class AnalyticsRepository @Inject constructor(
    private val api: CfApiClient,
) {
    /** 单个 Worker 指标（请求/错误/子请求），对应 iOS workerMetrics 摘要。 */
    suspend fun workerMetrics(
        accountId: String,
        scriptName: String,
        range: AnalyticsTimeRange = AnalyticsTimeRange.LAST_24H,
    ): jiamin.chen.orangecloud.data.model.WorkerMetrics {
        val (since, until) = range.sinceUntil()
        val data = api.graphQL<jiamin.chen.orangecloud.data.model.WorkerMetricsData, jiamin.chen.orangecloud.data.model.WorkerMetricsVariables>(
            AnalyticsQueries.workerSummary(),
            jiamin.chen.orangecloud.data.model.WorkerMetricsVariables(accountId, scriptName, since, until),
        )
        val node = data.viewer.accounts.firstOrNull()
        val sums = node?.summary.orEmpty()
        val quantiles = sums.firstOrNull()?.quantiles
        val breakdown = node?.byStatus.orEmpty()
            .mapNotNull { g -> g.dimensions?.status?.let { jiamin.chen.orangecloud.data.model.WorkerStatusCount(it, g.sum?.requests ?: 0L) } }
            .filter { it.requests > 0 }
            .sortedByDescending { it.requests }
        return jiamin.chen.orangecloud.data.model.WorkerMetrics(
            requests = sums.sumOf { it.sum?.requests ?: 0L },
            errors = sums.sumOf { it.sum?.errors ?: 0L },
            subrequests = sums.sumOf { it.sum?.subrequests ?: 0L },
            cpuP50Us = quantiles?.cpuTimeP50,
            cpuP99Us = quantiles?.cpuTimeP99,
            statusBreakdown = breakdown,
        )
    }

    /** 单个 Worker 调用趋势（请求/错误时间序列）。 */
    suspend fun workerSeries(
        accountId: String,
        scriptName: String,
        range: AnalyticsTimeRange,
    ): List<jiamin.chen.orangecloud.data.model.WorkerSeriesPoint> {
        val (since, until) = range.sinceUntil()
        val data = api.graphQL<jiamin.chen.orangecloud.data.model.WorkerSeriesData, jiamin.chen.orangecloud.data.model.WorkerMetricsVariables>(
            AnalyticsQueries.workerSeries(daily = !range.usesHourlyGroups),
            jiamin.chen.orangecloud.data.model.WorkerMetricsVariables(accountId, scriptName, since, until),
        )
        return data.viewer.accounts.firstOrNull()?.series.orEmpty().mapNotNull { g ->
            val date = AnalyticsTimeRange.parseDimension(g.dimensions?.datetimeHour, g.dimensions?.date) ?: return@mapNotNull null
            jiamin.chen.orangecloud.data.model.WorkerSeriesPoint(date, g.sum?.requests ?: 0L, g.sum?.errors ?: 0L)
        }
    }

    /** 按国家/地区聚合请求量（合并同国家的多日/多小时分组），降序取前若干。 */
    suspend fun zoneCountryTraffic(zoneId: String, range: AnalyticsTimeRange): List<jiamin.chen.orangecloud.data.model.CountryTraffic> {
        val (since, until) = range.sinceUntil()
        val query = if (range.usesHourlyGroups) {
            AnalyticsQueries.zoneCountryHourly(1000)
        } else {
            AnalyticsQueries.zoneCountryDaily(1000)
        }
        val data = api.graphQL<jiamin.chen.orangecloud.data.model.ZoneCountryData, ZoneAnalyticsVariables>(
            query,
            ZoneAnalyticsVariables(zoneTag = zoneId, since = since, until = until),
        )
        val groups = data.viewer.zones.firstOrNull()?.groups.orEmpty()
        return groups
            .mapNotNull { g -> g.dimensions?.clientCountryName?.let { it to (g.sum?.requests?.toLong() ?: 0L) } }
            .groupingBy { it.first }.fold(0L) { acc, e -> acc + e.second }
            .map { (country, requests) -> jiamin.chen.orangecloud.data.model.CountryTraffic(country, requests) }
            .filter { it.requests > 0 }
            .sortedByDescending { it.requests }
    }

    suspend fun zoneTraffic(zoneId: String, range: AnalyticsTimeRange): List<TrafficDataPoint> {
        val (since, until) = range.sinceUntil()
        val query = if (range.usesHourlyGroups) {
            AnalyticsQueries.zoneHourly(range.limit)
        } else {
            AnalyticsQueries.zoneDaily(range.limit)
        }
        val data = api.graphQL<ZoneAnalyticsData, ZoneAnalyticsVariables>(
            query,
            ZoneAnalyticsVariables(zoneTag = zoneId, since = since, until = until),
        )
        val zone = data.viewer.zones.firstOrNull() ?: return emptyList()
        return zone.groups.mapNotNull { it.toDataPoint() }
    }

    // MARK: - adaptive 明细（访问明细 / 安全事件），现有 1h/1d 图表不受影响

    /** zone 上 adaptive 数据集的可用性与时间限制；读不到时调用方按「不收窄」处理。 */
    suspend fun adaptiveSettings(zoneId: String): AdaptiveZoneSettings? =
        api.graphQL<AdaptiveSettingsData, ZoneTagVariables>(AdaptiveAnalyticsQueries.SETTINGS, ZoneTagVariables(zoneId))
            .viewer?.zones?.firstOrNull()?.settings

    /** 访问明细：国家/地区、状态码、路径、主机名各取请求数前 10（httpRequestsAdaptiveGroups）。 */
    suspend fun trafficDetails(zoneId: String, since: Instant, until: Instant): TrafficDetails {
        val data = api.graphQL<TrafficDetailsData, ZoneAnalyticsVariables>(
            AdaptiveAnalyticsQueries.TRAFFIC_DETAILS,
            ZoneAnalyticsVariables(zoneId, since.toString(), until.toString()),
        )
        val zone = data.viewer?.zones?.firstOrNull()
        return TrafficDetails(
            mapOf(
                TrafficDimension.COUNTRY to zone?.byCountry.toTopItems(),
                TrafficDimension.STATUS to zone?.byStatus.toTopItems(),
                TrafficDimension.PATH to zone?.byPath.toTopItems(),
                TrafficDimension.HOST to zone?.byHost.toTopItems(),
            ),
        )
    }

    /** 安全事件：按处置方式 / 来源计数 + 最近 20 条（firewallEventsAdaptive*）。 */
    suspend fun securityEvents(zoneId: String, since: Instant, until: Instant): SecurityEvents {
        val data = api.graphQL<SecurityEventsData, ZoneAnalyticsVariables>(
            AdaptiveAnalyticsQueries.SECURITY_EVENTS,
            ZoneAnalyticsVariables(zoneId, since.toString(), until.toString()),
        )
        val zone = data.viewer?.zones?.firstOrNull()
        return SecurityEvents(
            byAction = zone?.byAction.toTopItems(),
            bySource = zone?.bySource.toTopItems(),
            recent = zone?.recent.orEmpty(),
        )
    }

    // MARK: - 账号用量（Dashboard 用量模块，对应 iOS AnalyticsService account usage 系列）

    /** Time 标量窗口（Workers / R2）：periodStart 传计费周期起点，null 回退自然月（UTC）。 */
    private fun usageVariables(accountId: String, periodStart: Instant?): AccountUsageVariables {
        val now = Instant.now().truncatedTo(ChronoUnit.SECONDS)
        val todayStart = now.atZone(ZoneOffset.UTC).toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant()
        val monthStart = periodStart
            ?: now.atZone(ZoneOffset.UTC).toLocalDate().withDayOfMonth(1).atStartOfDay(ZoneOffset.UTC).toInstant()
        val iso = DateTimeFormatter.ISO_INSTANT
        return AccountUsageVariables(accountId, iso.format(monthStart), iso.format(todayStart), iso.format(now))
    }

    /** Date 标量窗口（D1 / KV）：yyyy-MM-dd（UTC）。 */
    private fun dateVariables(accountId: String, periodStart: Instant?): D1UsageVariables {
        val today = Instant.now().atZone(ZoneOffset.UTC).toLocalDate()
        val monthStart = periodStart?.atZone(ZoneOffset.UTC)?.toLocalDate() ?: today.withDayOfMonth(1)
        val day = DateTimeFormatter.ISO_LOCAL_DATE
        return D1UsageVariables(accountId, monthStart.format(day), today.format(day), today.format(day))
    }

    /**
     * Workers 账号用量（今日/周期请求、月度错误、单次 CPU 分位）。整账号无账户级数据权限时
     * （authz 且信封里连数据都没有）由 api.graphQL 抛出交调用方降级。
     *
     * partialAuthz = 只有部分时间窗被 authz 挡（免费账号常见：今日有数、周期没有），
     * 返回的用量里缺的那部分是 0，调用方据此给温和提示而不是整块降级。
     */
    data class AccountWorkersUsage(val usage: AccountUsage, val partialAuthz: Boolean)

    suspend fun accountWorkersUsage(accountId: String, periodStart: Instant?): AccountWorkersUsage {
        val (data, partialAuthz) = api.graphQLAllowingPartialAuthz<AccountUsageData, AccountUsageVariables>(
            AccountUsageQueries.WORKERS, usageVariables(accountId, periodStart),
        )
        val node = data.viewer.accounts.firstOrNull() ?: error("no account")
        val q = node.month?.firstOrNull()?.quantiles
        return AccountWorkersUsage(
            AccountUsage(
                workersRequestsToday = node.today.orEmpty().sumOf { it.sum?.requests ?: 0L },
                workersRequestsMonth = node.month.orEmpty().sumOf { it.sum?.requests ?: 0L },
                workersErrorsMonth = node.month.orEmpty().sumOf { it.sum?.errors ?: 0L },
                cpuP50Us = q?.cpuTimeP50,
                cpuP99Us = q?.cpuTimeP99,
            ),
            partialAuthz,
        )
    }

    /** Workers CPU 总耗时（周期/今日，微秒）。schema 不支持时抛错由调用方降级。 */
    suspend fun workersCpuTotals(accountId: String, periodStart: Instant?): Pair<Double, Double> {
        val data = api.graphQL<WorkersCpuData, AccountUsageVariables>(
            AccountUsageQueries.WORKERS_CPU, usageVariables(accountId, periodStart),
        )
        val node = data.viewer.accounts.firstOrNull() ?: return 0.0 to 0.0
        val month = node.month.orEmpty().sumOf { it.sum?.cpuTimeUs ?: 0.0 }
        val today = node.today.orEmpty().sumOf { it.sum?.cpuTimeUs ?: 0.0 }
        return month to today
    }

    /** R2 账号级用量：A/B 类操作合计 + 当前存储/对象数。读类计 Class B，其余 Class A。 */
    data class R2Totals(val classA: Long, val classB: Long, val storageBytes: Long, val objectCount: Long)

    suspend fun accountR2Usage(accountId: String, periodStart: Instant?): R2Totals {
        val v = usageVariables(accountId, periodStart)
        val data = api.graphQL<R2UsageData, R2UsageVariables>(
            AccountUsageQueries.R2, R2UsageVariables(v.accountTag, v.monthStart, v.todayStart, v.now),
        )
        val account = data.viewer?.accounts?.firstOrNull() ?: return R2Totals(0, 0, 0, 0)
        var classA = 0L
        var classB = 0L
        account.r2Ops?.forEach { g ->
            val action = g.dimensions?.actionType ?: return@forEach
            val count = g.sum?.requests ?: 0L
            if (action in R2_CLASS_B_ACTIONS) classB += count else classA += count
        }
        var storage = 0L
        var objects = 0L
        account.r2Storage?.forEach { g ->
            storage += (g.max?.payloadSize ?: 0L) + (g.max?.metadataSize ?: 0L)
            objects += (g.max?.objectCount ?: 0).toLong()
        }
        return R2Totals(classA, classB, storage, objects)
    }

    /** D1 行读/写（今日 + 周期）。 */
    suspend fun d1Usage(accountId: String, periodStart: Instant?): D1Usage {
        val data = api.graphQL<D1UsageData, D1UsageVariables>(
            AccountUsageQueries.D1, dateVariables(accountId, periodStart),
        )
        val node = data.viewer.accounts.firstOrNull() ?: error("no account")
        fun totals(groups: List<D1UsageGroup>?): Pair<Long, Long> {
            var read = 0L
            var written = 0L
            groups?.forEach { read += it.sum?.rowsRead ?: 0L; written += it.sum?.rowsWritten ?: 0L }
            return read to written
        }
        val (periodRead, periodWritten) = totals(node.period)
        val (todayRead, todayWritten) = totals(node.today)
        return D1Usage(todayRead, todayWritten, periodRead, periodWritten)
    }

    /** KV 读/写（今日 + 周期；delete/list 不计入主额度行）。 */
    suspend fun kvUsage(accountId: String, periodStart: Instant?): KVUsage {
        val data = api.graphQL<KVUsageData, D1UsageVariables>(
            AccountUsageQueries.KV_OPERATIONS, dateVariables(accountId, periodStart),
        )
        val node = data.viewer.accounts.firstOrNull() ?: error("no account")
        fun totals(groups: List<KVOpsGroup>?): Pair<Long, Long> {
            var reads = 0L
            var writes = 0L
            groups?.forEach {
                val count = it.sum?.requests ?: 0L
                when (it.dimensions?.actionType) {
                    "read" -> reads += count
                    "write" -> writes += count
                }
            }
            return reads to writes
        }
        val (periodReads, periodWrites) = totals(node.period)
        val (todayReads, todayWrites) = totals(node.today)
        return KVUsage(todayReads, todayWrites, periodReads, periodWrites)
    }

    /** KV 当前存储（各 namespace 当日 max byteCount 求和）。 */
    suspend fun kvStorageBytes(accountId: String): Long {
        val data = api.graphQL<KVUsageData, D1UsageVariables>(
            AccountUsageQueries.KV_STORAGE, dateVariables(accountId, null),
        )
        val node = data.viewer.accounts.firstOrNull() ?: return 0L
        return node.storage.orEmpty().sumOf { it.max?.byteCount ?: 0L }
    }
}

private fun AnalyticsGroup.toDataPoint(): TrafficDataPoint? {
    val date = AnalyticsTimeRange.parseDimension(dimensions?.datetime, dimensions?.date) ?: return null
    return TrafficDataPoint(
        date = date,
        requests = sum?.requests ?: 0,
        bytes = sum?.bytes ?: 0,
        threats = sum?.threats ?: 0,
        pageViews = sum?.pageViews ?: 0,
        uniques = uniq?.uniques ?: 0,
        cachedRequests = sum?.cachedRequests ?: 0,
    )
}
