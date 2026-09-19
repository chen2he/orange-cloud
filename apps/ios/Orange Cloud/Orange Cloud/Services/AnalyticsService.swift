//
//  AnalyticsService.swift
//  Orange Cloud
//
//  Zone 流量分析：GraphQL Analytics API → 归一化为图表数据点。
//  支持当前周期 + 前一等长周期（环比趋势）。
//

import Foundation

struct AnalyticsService {

    private let client: CFAPIClient

    init(client: CFAPIClient) {
        self.client = client
    }

    /// 当前周期的流量时间序列
    func zoneTraffic(zoneId: String, range: AnalyticsTimeRange) async throws -> [TrafficDataPoint] {
        let (since, until) = range.sinceUntil()
        return try await fetch(zoneId: zoneId, range: range, since: since, until: until)
    }

    /// 前一个等长周期（趋势对比用）
    func zoneTrafficPrevious(zoneId: String, range: AnalyticsTimeRange) async throws -> [TrafficDataPoint] {
        let (since, until) = range.previousSinceUntil()
        return try await fetch(zoneId: zoneId, range: range, since: since, until: until)
    }

    /// 按国家/地区聚合的流量（全球流量地图用）。各时间桶携带 countryMap，Swift 端按国家码合并求和。
    func zoneCountryTraffic(zoneId: String, range: AnalyticsTimeRange) async throws -> [CountryTraffic] {
        let (since, until) = range.sinceUntil()
        let query = range.usesHourlyGroups
            ? AnalyticsQueries.zoneCountryHourly(limit: range.limit)
            : AnalyticsQueries.zoneCountryDaily(limit: range.limit)

        let data: ZoneAnalyticsData = try await client.graphQL(
            query: query,
            variables: ZoneAnalyticsVariables(zoneTag: zoneId, since: since, until: until)
        )
        guard let zone = data.viewer.zones.first else { return [] }

        var aggregate: [String: (requests: Int, threats: Int, bytes: Int)] = [:]
        for group in zone.groups {
            for entry in group.sum?.countryMap ?? [] {
                guard let code = entry.clientCountryName, !code.isEmpty else { continue }
                aggregate[code, default: (0, 0, 0)].requests += entry.requests ?? 0
                aggregate[code, default: (0, 0, 0)].threats  += entry.threats ?? 0
                aggregate[code, default: (0, 0, 0)].bytes    += entry.bytes ?? 0
            }
        }

        return aggregate
            .map { CountryTraffic(countryCode: $0.key, requests: $0.value.requests, threats: $0.value.threats, bytes: $0.value.bytes) }
            .sorted { $0.requests > $1.requests }
    }

    /// Dashboard / Widget：多个 Zone 的 24h 流量（含前一窗口请求数做趋势），
    /// 一次 GraphQL 查完；失败回退为逐 Zone 并发查询（无趋势）。
    func trafficByZone24h(zoneIds: [String]) async throws -> [String: ZoneTrafficBundle] {
        guard !zoneIds.isEmpty else { return [:] }
        let range = AnalyticsTimeRange.last24h
        let (since, until) = range.sinceUntil()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let prevSince = formatter.string(from: Date().addingTimeInterval(-48 * 3600))

        do {
            let data: ZoneAnalyticsData = try await client.graphQL(
                query: AnalyticsQueries.multiZoneHourly(limit: range.limit),
                variables: MultiZoneAnalyticsVariables(
                    zoneTags: zoneIds, since: since, until: until, prevSince: prevSince
                )
            )
            var result: [String: ZoneTrafficBundle] = [:]
            for node in data.viewer.zones {
                guard let tag = node.zoneTag else { continue }
                let previous = (node.previous ?? []).reduce(0) { $0 + ($1.sum?.requests ?? 0) }
                result[tag] = ZoneTrafficBundle(
                    points: node.groups.compactMap { Self.dataPoint(from: $0) },
                    previousRequests: previous
                )
            }
            return result
        } catch {
            // 多 Zone 查询失败（如 schema 差异）→ 逐 Zone 并发兜底
            return await withTaskGroup(of: (String, [TrafficDataPoint]?).self) { group in
                for zoneId in zoneIds {
                    group.addTask {
                        (zoneId, try? await self.zoneTraffic(zoneId: zoneId, range: .last24h))
                    }
                }
                var result: [String: ZoneTrafficBundle] = [:]
                for await (zoneId, points) in group {
                    if let points {
                        result[zoneId] = ZoneTrafficBundle(points: points, previousRequests: nil)
                    }
                }
                return result
            }
        }
    }

    /// 统计窗口：periodStart 传真实计费周期起点（UTC 锚定），nil 回退自然月。
    /// 「今日」与自然月的日界按用户设置（DayBoundary，默认 UTC，与免费额度重置口径一致）。
    private nonisolated static func usageVariables(accountId: String, periodStart: Date?) -> AccountUsageVariables {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let calendar = DayBoundary.current.calendar

        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let monthStart = periodStart ?? calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? todayStart

        return AccountUsageVariables(
            accountTag: accountId,
            monthStart: formatter.string(from: monthStart),
            todayStart: formatter.string(from: todayStart),
            now:        formatter.string(from: now)
        )
    }

    /// Workers CPU 总耗时（周期/今日，微秒）。独立查询，schema 不支持时抛错由调用方降级。
    func workersCpuTotals(accountId: String, periodStart: Date? = nil) async throws -> (monthUs: Double, todayUs: Double) {
        let data: WorkersCpuData = try await client.graphQL(
            query: WorkersCpuQuery.text,
            variables: Self.usageVariables(accountId: accountId, periodStart: periodStart)
        )
        guard let account = data.viewer.accounts.first else {
            throw APIError.notFound
        }
        let month = (account.month ?? []).reduce(0.0) { $0 + ($1.sum?.cpuTimeUs ?? 0) }
        let today = (account.today ?? []).reduce(0.0) { $0 + ($1.sum?.cpuTimeUs ?? 0) }
        return (month, today)
    }

    // MARK: - 单 Worker 指标

    /// 摘要 + 状态分解；CPU 总量 best-effort 合并
    func workerMetrics(accountId: String, scriptName: String, range: AnalyticsTimeRange) async throws -> WorkerMetrics {
        let (since, until) = range.datetimeWindow()
        let variables = WorkerMetricsVariables(
            accountTag: accountId, scriptName: scriptName, since: since, until: until
        )

        let data: WorkerMetricsData = try await client.graphQL(
            query: WorkerMetricsQueries.summary,
            variables: variables
        )
        guard let node = data.viewer.accounts.first else {
            throw APIError.notFound
        }

        let sums = (node.summary ?? []).reduce(into: (requests: 0, errors: 0, subrequests: 0)) {
            $0.requests    += $1.sum?.requests ?? 0
            $0.errors      += $1.sum?.errors ?? 0
            $0.subrequests += $1.sum?.subrequests ?? 0
        }
        let quantiles = node.summary?.first?.quantiles

        let breakdown = (node.byStatus ?? [])
            .compactMap { group -> (String, Int)? in
                guard let status = group.dimensions?.status else { return nil }
                return (status, group.sum?.requests ?? 0)
            }
            .sorted { $0.1 > $1.1 }

        var metrics = WorkerMetrics(
            requests:    sums.requests,
            errors:      sums.errors,
            subrequests: sums.subrequests,
            cpuP50Us:    quantiles?.cpuTimeP50,
            cpuP99Us:    quantiles?.cpuTimeP99,
            cpuTotalUs:  nil,
            statusBreakdown: breakdown
        )

        // CPU 总量（较新字段）独立请求，失败不影响摘要
        if let cpuData: WorkerCpuData = try? await client.graphQL(
            query: WorkerMetricsQueries.cpuTotal, variables: variables
        ) {
            let total = (cpuData.viewer.accounts.first?.summary ?? [])
                .reduce(0.0) { $0 + ($1.sum?.cpuTimeUs ?? 0) }
            metrics.cpuTotalUs = total
        }
        return metrics
    }

    /// 时间序列：24h 按小时、7d/30d 按天
    func workerSeries(accountId: String, scriptName: String, range: AnalyticsTimeRange) async throws -> [WorkerSeriesPoint] {
        let daily = range != .last24h
        let (since, until) = range.datetimeWindow()

        let data: WorkerSeriesData = try await client.graphQL(
            query: WorkerMetricsQueries.series(daily: daily),
            variables: WorkerMetricsVariables(
                accountTag: accountId, scriptName: scriptName, since: since, until: until
            )
        )

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        return (data.viewer.accounts.first?.series ?? []).compactMap { group in
            let date: Date? = if daily {
                group.dimensions?.date.flatMap { AnalyticsTimeRange.dayFormatter.date(from: $0) }
            } else {
                group.dimensions?.datetimeHour.flatMap { isoFormatter.date(from: $0) }
            }
            guard let date else { return nil }
            return WorkerSeriesPoint(
                date: date,
                requests: group.sum?.requests ?? 0,
                errors: group.sum?.errors ?? 0
            )
        }
    }

    /// D1 用量：行读/写（今日 + 周期）。date 维度按 UTC 天聚合。
    func d1Usage(accountId: String, periodStart: Date? = nil) async throws -> D1Usage {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let monthStart = periodStart ?? calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? todayStart

        let formatter = AnalyticsTimeRange.dayFormatter
        let data: D1UsageData = try await client.graphQL(
            query: D1UsageQuery.text,
            variables: D1UsageVariables(
                accountTag:  accountId,
                periodStart: formatter.string(from: monthStart),
                todayStart:  formatter.string(from: todayStart),
                until:       formatter.string(from: now)
            )
        )
        guard let account = data.viewer.accounts.first else {
            throw APIError.notFound
        }

        func totals(_ groups: [D1UsageGroup]?) -> (read: Int, written: Int) {
            (groups ?? []).reduce(into: (0, 0)) {
                $0.0 += $1.sum?.rowsRead ?? 0
                $0.1 += $1.sum?.rowsWritten ?? 0
            }
        }
        let period = totals(account.period)
        let today = totals(account.today)

        return D1Usage(
            rowsReadToday:     today.read,
            rowsWrittenToday:  today.written,
            rowsReadPeriod:    period.read,
            rowsWrittenPeriod: period.written
        )
    }

    /// 过去 1 小时的 Workers 错误总数（后台通知检测用）
    func workersErrorsLastHour(accountId: String) async throws -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = Date()
        let data: WorkersErrorsData = try await client.graphQL(
            query: WorkersErrorsQuery.text,
            variables: WorkersErrorsVariables(
                accountTag: accountId,
                since: formatter.string(from: now.addingTimeInterval(-3600)),
                until: formatter.string(from: now)
            )
        )
        guard let account = data.viewer.accounts.first else {
            throw APIError.notFound
        }
        return (account.window ?? []).reduce(0) { $0 + ($1.sum?.errors ?? 0) }
    }

    /// KV 用量：读/写操作（今日 + 周期，按 actionType 归类）
    func kvUsage(accountId: String, periodStart: Date? = nil) async throws -> KVUsage {
        let data: KVUsageData = try await client.graphQL(
            query: KVUsageQuery.operations,
            variables: d1DateVariables(accountId: accountId, periodStart: periodStart)
        )
        guard let account = data.viewer.accounts.first else {
            throw APIError.notFound
        }

        func totals(_ groups: [KVOpsGroup]?) -> (reads: Int, writes: Int) {
            (groups ?? []).reduce(into: (0, 0)) { result, group in
                let count = group.sum?.requests ?? 0
                switch group.dimensions?.actionType {
                case "read": result.0 += count
                case "write": result.1 += count
                default: break   // delete/list 不计入主额度行
                }
            }
        }
        let period = totals(account.period)
        let today = totals(account.today)

        return KVUsage(
            readsToday:   today.reads,
            writesToday:  today.writes,
            readsPeriod:  period.reads,
            writesPeriod: period.writes
        )
    }

    /// KV 当前存储（各 namespace 当日 max byteCount 求和）
    func kvStorageBytes(accountId: String) async throws -> Int {
        let data: KVUsageData = try await client.graphQL(
            query: KVUsageQuery.storage,
            variables: d1DateVariables(accountId: accountId, periodStart: nil)
        )
        guard let account = data.viewer.accounts.first else {
            throw APIError.notFound
        }
        return (account.storage ?? []).reduce(0) { $0 + ($1.max?.byteCount ?? 0) }
    }

    /// Date 标量窗口变量（D1/KV 共用）
    private nonisolated func d1DateVariables(accountId: String, periodStart: Date?) -> D1UsageVariables {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let monthStart = periodStart ?? calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? todayStart
        let formatter = AnalyticsTimeRange.dayFormatter
        return D1UsageVariables(
            accountTag:  accountId,
            periodStart: formatter.string(from: monthStart),
            todayStart:  formatter.string(from: todayStart),
            until:       formatter.string(from: now)
        )
    }

    /// 账号用量：Workers 调用（今日/周期）。R2 拆为独立查询（见 r2Usage），
    /// 账号无 R2 / 无 R2 数据集权限时不再拖垮 Workers 用量（issue #4）。
    ///
    /// partialAuthz = 只有部分时间窗被 authz 挡（免费账号常见：今日有数、周期没有），
    /// 此时返回的用量里缺的那部分是 0，调用方据此给出「部分数据不可用」的温和提示，
    /// 而不是把整块用量降级成「此账号无账户级数据查询权限」。
    func accountUsage(
        accountId: String,
        periodStart: Date? = nil
    ) async throws -> (usage: AccountUsage, partialAuthz: Bool) {
        let (data, partialAuthz): (AccountUsageData, Bool) = try await client.graphQLAllowingPartialAuthz(
            query: AccountUsageQuery.text,
            variables: Self.usageVariables(accountId: accountId, periodStart: periodStart)
        )

        guard let account = data.viewer.accounts.first else {
            throw APIError.notFound
        }

        let monthSum = (account.month ?? []).reduce(into: (requests: 0, errors: 0)) {
            $0.requests += $1.sum?.requests ?? 0
            $0.errors   += $1.sum?.errors ?? 0
        }
        let todayRequests = (account.today ?? []).reduce(0) { $0 + ($1.sum?.requests ?? 0) }
        let quantiles = account.month?.first?.quantiles

        return (
            AccountUsage(
                workersRequestsToday: todayRequests,
                workersRequestsMonth: monthSum.requests,
                workersErrorsMonth:   monthSum.errors,
                cpuP50Us:             quantiles?.cpuTimeP50,
                cpuP99Us:             quantiles?.cpuTimeP99,
                cpuTimeMonthUs:       nil,
                cpuTimeTodayUs:       nil
            ),
            partialAuthz
        )
    }

    /// R2 用量（操作分类 + 当前存储）独立查询。schema/权限不支持时抛错由调用方降级，
    /// 不影响 Workers 主用量（与 CPU/D1/KV 同策略）。
    func r2Usage(
        accountId: String,
        periodStart: Date? = nil
    ) async throws -> (classA: Int, classB: Int, storageBytes: Int, objectCount: Int) {
        let data: R2UsageData = try await client.graphQL(
            query: R2UsageQuery.text,
            variables: Self.usageVariables(accountId: accountId, periodStart: periodStart)
        )
        guard let account = data.viewer.accounts.first else {
            throw APIError.notFound
        }

        var classA = 0
        var classB = 0
        for group in account.r2Ops ?? [] {
            guard let action = group.dimensions?.actionType else { continue }
            let count = group.sum?.requests ?? 0
            if R2OperationClass.classA.contains(action) {
                classA += count
            } else if R2OperationClass.classB.contains(action) {
                classB += count
            }
        }

        var storageBytes = 0
        var objectCount = 0
        for group in account.r2Storage ?? [] {
            storageBytes += (group.max?.payloadSize ?? 0) + (group.max?.metadataSize ?? 0)
            objectCount  += group.max?.objectCount ?? 0
        }

        return (classA, classB, storageBytes, objectCount)
    }

    /// 每桶用量（本月操作 Class A/B + 当前存储/对象数快照）。复用账号级 R2 查询的 bucketName 维度。
    /// authz / schema 不支持时抛错由调用方降级（免费账号账户级 GraphQL 常被 authz 挡）。
    func r2UsageByBucket(accountId: String, periodStart: Date? = nil) async throws -> [String: R2BucketUsage] {
        let data: R2UsageData = try await client.graphQL(
            query: R2UsageQuery.text,
            variables: Self.usageVariables(accountId: accountId, periodStart: periodStart)
        )
        guard let account = data.viewer.accounts.first else {
            throw APIError.notFound
        }

        var byBucket: [String: R2BucketUsage] = [:]
        for group in account.r2Storage ?? [] {
            guard let bucket = group.dimensions?.bucketName, !bucket.isEmpty else { continue }
            var usage = byBucket[bucket] ?? R2BucketUsage()
            usage.storageBytes = (group.max?.payloadSize ?? 0) + (group.max?.metadataSize ?? 0)
            usage.objectCount  = group.max?.objectCount ?? 0
            byBucket[bucket] = usage
        }
        for group in account.r2Ops ?? [] {
            guard let bucket = group.dimensions?.bucketName, !bucket.isEmpty,
                  let action = group.dimensions?.actionType else { continue }
            let count = group.sum?.requests ?? 0
            var usage = byBucket[bucket] ?? R2BucketUsage()
            if R2OperationClass.classA.contains(action) {
                usage.classARequests += count
            } else if R2OperationClass.classB.contains(action) {
                usage.classBRequests += count
            }
            byBucket[bucket] = usage
        }
        return byBucket
    }

    private func fetch(
        zoneId: String,
        range: AnalyticsTimeRange,
        since: String,
        until: String
    ) async throws -> [TrafficDataPoint] {
        let query = range.usesHourlyGroups
            ? AnalyticsQueries.zoneHourly(limit: range.limit)
            : AnalyticsQueries.zoneDaily(limit: range.limit)

        let data: ZoneAnalyticsData = try await client.graphQL(
            query: query,
            variables: ZoneAnalyticsVariables(zoneTag: zoneId, since: since, until: until)
        )

        guard let zone = data.viewer.zones.first else { return [] }
        return zone.groups.compactMap { Self.dataPoint(from: $0) }
    }

    /// 两种 dimensions（datetime / date）归一化为统一数据点
    private nonisolated static func dataPoint(from group: AnalyticsGroup) -> TrafficDataPoint? {
        guard let date = parseDimension(group.dimensions) else { return nil }
        return TrafficDataPoint(
            date:           date,
            requests:       group.sum?.requests ?? 0,
            bytes:          group.sum?.bytes ?? 0,
            threats:        group.sum?.threats ?? 0,
            pageViews:      group.sum?.pageViews ?? 0,
            uniques:        group.uniq?.uniques ?? 0,
            cachedRequests: group.sum?.cachedRequests ?? 0
        )
    }

    private nonisolated static func parseDimension(_ dimensions: AnalyticsDimensions?) -> Date? {
        if let datetime = dimensions?.datetime {
            return ISO8601Parse.plain.date(from: datetime)
        }
        if let day = dimensions?.date {
            return AnalyticsTimeRange.dayFormatter.date(from: day)
        }
        return nil
    }
}
