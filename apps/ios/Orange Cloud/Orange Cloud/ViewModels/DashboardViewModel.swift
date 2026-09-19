//
//  DashboardViewModel.swift
//  Orange Cloud
//
//  Dashboard 域名卡片的 24h 流量数据（一次多 Zone GraphQL 查询）。
//

import Foundation
import Observation
import SwiftData
import WidgetKit

@Observable
@MainActor
final class DashboardViewModel {

    private(set) var trafficByZone: [String: ZoneTrafficBundle] = [:]
    private(set) var usage: AccountUsage?
    /// 资产数（Dashboard 指标格）：接口或权限不可用时保持 nil，格子自动回退
    private(set) var r2BucketCount: Int?
    private(set) var d1DatabaseCount: Int?
    /// 订阅识别结果；nil = 接口不可用（OAuth 无 billing scope 时的常态），回退本地预设
    private(set) var billing: BillingInfo?
    var isLoading = false

    /// 全账号 DNS 记录总数（首屏 total_count 汇总；nil = 未加载/无权限，回退已同步缓存计数）
    private(set) var dnsRecordTotal: Int?
    private(set) var isLoadingAssets = false
    /// 最近一次资产刷新是否失败（核心即 Zone 列表拉取失败）——驱动 Dashboard 顶部红色提示
    private(set) var loadFailed = false
    /// 用量加载完成但账号级分析全部失败（区分「仍在加载」与「加载失败」，避免永远卡骨架）
    private(set) var usageLoadFailed = false
    /// 账户级数据集未授权（免费账号常态）：UI 显示「无账户级数据权限」而非重试，且停发后续账户级查询
    private(set) var accountAnalyticsUnavailable = false
    /// 账户级数据只有部分时间窗被 authz 挡（如今日有数、本周期没有）：用量照常显示，
    /// 只在宫格上方加一条温和提示，说明缺的那部分显示为 0 不是加载失败
    private(set) var accountAnalyticsPartial = false

    // MARK: - 资源清单（命令搜索 / 跨类型置顶 / 告警中心共用）
    // 域名与 Workers 直接读 SwiftData 缓存，这里只补拉「概览页原本不持有」的四类；
    // 每类按 scope 门控惰性补拉，缺权限就留空数组（不报错、搜索里直接没有该类）。
    private(set) var r2Buckets:    [R2Bucket] = []
    private(set) var d1Databases:  [D1Database] = []
    private(set) var kvNamespaces: [KVNamespace] = []
    private(set) var tunnels:      [Tunnel] = []

    private var inventoryLoadedForAccount: String?
    private var inventoryTask: Task<Void, Never>?

    private var loadedZoneIds: Set<String> = []
    private var assetsLoadedForAccount: String?
    private var usageLoadedForAccount: String?
    private var billingAttemptedForAccount: String?
    private var analyticsUnavailableForAccount: String?

    // 加载跑在 VM 持有的非结构化 Task：.task(id:)/.refreshable 的手势或 body 重建会取消视图任务，
    // 若请求直接 await 在视图任务里，URLSession 把取消转成 .cancelled → try? 吞成 nil → 用量/资产
    // 永远空白卡骨架态。放进独立 Task 后手势取消波及不到它，加载照常跑完写状态。详见同名 bug 修复。
    private var assetsTask: Task<Void, Never>?
    private var usageTask: Task<Void, Never>?
    private var trafficTask: Task<Void, Never>?
    private let analyticsService: AnalyticsService
    private let accountService: AccountService
    private let r2Service: R2Service
    private let d1Service: D1Service
    private let zoneService: ZoneService
    private let workerService: WorkerService
    private let dnsService: DNSService
    private let kvService: KVService
    private let tunnelService: TunnelService

    init(
        analyticsService: AnalyticsService,
        accountService: AccountService,
        r2Service: R2Service,
        d1Service: D1Service,
        zoneService: ZoneService,
        workerService: WorkerService,
        dnsService: DNSService,
        kvService: KVService,
        tunnelService: TunnelService
    ) {
        self.analyticsService = analyticsService
        self.accountService = accountService
        self.r2Service = r2Service
        self.d1Service = d1Service
        self.zoneService = zoneService
        self.workerService = workerService
        self.dnsService = dnsService
        self.kvService = kvService
        self.tunnelService = tunnelService
    }

    /// 资源清单补拉（R2 / D1 / KV / Tunnel）。同一账号只拉一次，下拉刷新强制重拉；
    /// 每类各自 scope 门控，失败或无权限保持空数组（搜索/告警里自然缺席，不弹错）。
    /// 加载跑在 VM 持有的独立 Task：与 loadAssets 同理，手势取消不能波及它。
    func loadInventory(
        accountId: String,
        canReadR2: Bool,
        canReadD1: Bool,
        canReadKV: Bool,
        canReadTunnel: Bool,
        force: Bool = false
    ) async {
        guard !accountId.isEmpty else { return }
        guard force || inventoryLoadedForAccount != accountId else { return }
        if let inventoryTask {
            await inventoryTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoadInventory(
                accountId: accountId,
                canReadR2: canReadR2, canReadD1: canReadD1,
                canReadKV: canReadKV, canReadTunnel: canReadTunnel
            )
        }
        inventoryTask = task
        defer { inventoryTask = nil }
        await task.value
    }

    private func performLoadInventory(
        accountId: String,
        canReadR2: Bool,
        canReadD1: Bool,
        canReadKV: Bool,
        canReadTunnel: Bool
    ) async {
        if canReadR2, let buckets = try? await r2Service.listBuckets(accountId: accountId) {
            r2Buckets = buckets
            r2BucketCount = buckets.count
        }
        if canReadD1, let databases = try? await d1Service.listDatabases(accountId: accountId) {
            d1Databases = databases
            d1DatabaseCount = databases.count
        }
        if canReadKV, let namespaces = try? await kvService.listNamespaces(accountId: accountId) {
            kvNamespaces = namespaces
        }
        if canReadTunnel, let list = try? await tunnelService.listTunnels(accountId: accountId) {
            tunnels = list
        }
        inventoryLoadedForAccount = accountId
    }

    /// 首屏资产统计：拉 Zone / Worker 列表同步进缓存（指标格直接从 @Query 读到数量），
    /// DNS 记录数对每个 Zone 用 total_count 轻量汇总，不必等用户逐页进入 DNS 列表。
    /// 同一账号只拉一次，下拉刷新强制重拉。
    func loadAssets(
        accountId: String,
        accountName: String,
        canReadWorkers: Bool,
        canReadDNS: Bool,
        context: ModelContext,
        force: Bool = false
    ) async {
        guard force || assetsLoadedForAccount != accountId else { return }
        // 冷启动若持久缓存仍在有效期内，直接用缓存（@Query 已即时渲染），不重新拉网络
        if !force, assetsLoadedForAccount == nil, CachePolicy.zonesFresh(accountId: accountId, context: context) {
            assetsLoadedForAccount = accountId
            return
        }
        // 已有加载在跑：等它结束即可，不另起重复请求（手势取消波及不到这个独立 Task）
        if let assetsTask {
            await assetsTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoadAssets(
                accountId: accountId, accountName: accountName,
                canReadWorkers: canReadWorkers, canReadDNS: canReadDNS, context: context
            )
        }
        assetsTask = task
        defer { assetsTask = nil }
        await task.value
    }

    private func performLoadAssets(
        accountId: String,
        accountName: String,
        canReadWorkers: Bool,
        canReadDNS: Bool,
        context: ModelContext
    ) async {
        isLoadingAssets = true
        loadFailed = false
        defer { isLoadingAssets = false }

        // Zone 列表是 DNS 统计的基础；失败显示顶部红色提示，下次进入/下拉重试
        guard let zones = try? await zoneService.listZones(accountId: accountId) else {
            loadFailed = true
            return
        }
        CacheSync.syncZones(zones, accountId: accountId, accountName: accountName, context: context)

        if canReadWorkers, let scripts = try? await workerService.listScripts(accountId: accountId) {
            CacheSync.syncWorkers(scripts, accountId: accountId, context: context)
        }

        if canReadDNS {
            // 每个 Zone 一个轻量请求并发取 total_count；域名特别多时只统计前 50 个
            let service = dnsService
            let zoneIds = zones.prefix(50).map(\.id)
            let counts = await withTaskGroup(of: (String, Int)?.self) { group in
                for zoneId in zoneIds {
                    group.addTask {
                        (try? await service.recordCount(zoneId: zoneId)).map { (zoneId, $0) }
                    }
                }
                var acc: [(zoneId: String, count: Int)] = []
                for await pair in group {
                    if let pair { acc.append(pair) }
                }
                return acc
            }
            if zoneIds.isEmpty {
                dnsRecordTotal = 0
            } else if !counts.isEmpty {
                dnsRecordTotal = counts.reduce(0) { $0 + $1.count }
                // 分域名回写缓存：域名详情页首屏直显记录数（不再默认 0 条等进列表刷新）
                SafeCache.perform("dnsRecordCount 回写") {
                    let rows = try context.fetch(
                        FetchDescriptor<CachedZone>(predicate: #Predicate { $0.accountId == accountId })
                    )
                    let byId = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    for (zoneId, count) in counts {
                        byId[zoneId]?.dnsRecordCount = count
                    }
                    try context.save()
                }
            }
        }

        assetsLoadedForAccount = accountId
    }

    /// 账号用量（Workers/R2）。同一账号只拉一次，下拉刷新强制重拉。
    /// 周期起点优先级：订阅接口（best-effort）→ 手动账单日（fallbackPeriodStart）→ 自然月。
    func loadUsage(accountId: String, fallbackPeriodStart: Date? = nil, force: Bool = false) async {
        // 先用上次缓存即时填充（VM 被重建后切回概览不再空白重载），随后照常后台静默刷新
        if usage == nil, let cached = UsageCache.load(accountId: accountId) {
            usage = cached
        }
        guard force || usageLoadedForAccount != accountId else { return }
        if let usageTask {
            await usageTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoadUsage(accountId: accountId, fallbackPeriodStart: fallbackPeriodStart, force: force)
        }
        usageTask = task
        defer { usageTask = nil }
        await task.value
    }

    private func performLoadUsage(accountId: String, fallbackPeriodStart: Date?, force: Bool) async {
        usageLoadFailed = false   // 重试期间先回骨架态，加载完再据结果定

        // 已知该账号无账户级数据权限：非强制刷新直接降级，不再发注定 authz/403 失败的查询。
        // 下拉刷新（force）会重探，便于用户升级套餐后自动恢复。
        if !force, analyticsUnavailableForAccount == accountId {
            accountAnalyticsUnavailable = true
            accountAnalyticsPartial = false
            return
        }

        // 订阅接口需要 billing 权限（OAuth token 不带）：首个确定性拒绝后按账号跨启动记住，
        // 不再每次冷启动发一条注定 403 的探测（同账户级分析 authz 的惰性识别）；
        // 下拉刷新（force）会重探，权限恢复时自动回归并摘除标记。
        if force || billingAttemptedForAccount != accountId {
            billingAttemptedForAccount = accountId
            if force || !BillingProbeCache.isUnavailable(accountId: accountId) {
                do {
                    billing = BillingInfo.derive(from: try await accountService.listSubscriptions(accountId: accountId))
                    BillingProbeCache.markAvailable(accountId: accountId)
                } catch {
                    billing = nil
                    if let apiError = error as? APIError, apiError.isPermissionDenied {
                        BillingProbeCache.markUnavailable(accountId: accountId)
                        AppLog.network.info("subscriptions endpoint permission denied; skipping billing probe for account=\(accountId)")
                    }
                }
            }
        }

        // 订阅周期有效才采用：必须在过去、未结束，且不超过 GraphQL 数据留存（约 31 天）
        var periodStart: Date?
        if let billing,
           let start = billing.periodStart,
           start <= Date(),
           start > Date().addingTimeInterval(-31 * 24 * 3600),
           billing.periodEnd.map({ $0 > Date() }) ?? true {
            periodStart = start
        }
        periodStart = periodStart ?? fallbackPeriodStart

        // Workers 用量（账号级 GraphQL）。注意 HTTP 200 不代表 GraphQL 成功——Cloudflare 即使
        // 数据集报错也回 200，错误在响应体 errors 里（CFAPIClient.graphQL 会记 "graphQL error"）。
        // Workers 是账户级 analytics 的代表：authz 且信封里连数据都没有 = 整账号无账户级数据权限
        // → 直接降级并停发 R2/D1/KV/CPU 等其余注定失败的查询。
        // 但 authz 也可能只挡住部分时间窗（免费账号：今日有数、本周期没有），此时 CF 照常回已授权
        // 字段，CFAPIClient 会把它连同 partialAuthz 一起给回来——那种情况不降级，照常显示并加提示。
        let workers: AccountUsage?
        var partialAuthz = false
        do {
            let result = try await analyticsService.accountUsage(accountId: accountId, periodStart: periodStart)
            workers = result.usage
            partialAuthz = result.partialAuthz
        } catch let error as APIError where error.isAccountNotAuthorized {
            accountAnalyticsUnavailable = true
            accountAnalyticsPartial = false
            analyticsUnavailableForAccount = accountId
            self.usage = nil
            usageLoadFailed = false
            persistAnalyticsAvailability(false)
            AppLog.network.info("account-level analytics not authorized; skipping account datasets for account=\(accountId)")
            return
        } catch {
            workers = nil   // 其它失败（多为临时）：继续尝试 R2/D1/KV，能显示多少显示多少
        }

        // 账户级有权限（或仅 Workers 本次临时失败）：清除不可用态
        accountAnalyticsUnavailable = false
        accountAnalyticsPartial = partialAuthz
        analyticsUnavailableForAccount = nil

        var usage = workers ?? AccountUsage(
            workersRequestsToday: 0, workersRequestsMonth: 0, workersErrorsMonth: 0,
            cpuP50Us: nil, cpuP99Us: nil, cpuTimeMonthUs: nil, cpuTimeTodayUs: nil
        )
        var anyData = workers != nil

        // R2 用量（操作分类 + 存储）独立合并
        if let r2 = try? await analyticsService.r2Usage(accountId: accountId, periodStart: periodStart) {
            usage.r2ClassAMonth = r2.classA
            usage.r2ClassBMonth = r2.classB
            usage.r2StorageBytes = r2.storageBytes
            usage.r2ObjectCount = r2.objectCount
            anyData = true
        }
        // 存储改用 REST 指标（与 Dashboard 同源、免费额度只计 Standard），失败保留 GraphQL 值
        if let metrics = try? await r2Service.accountMetrics(accountId: accountId) {
            usage.r2StorageBytes = metrics.standardBytes
            usage.r2ObjectCount = metrics.standardObjects
            anyData = true
        }
        // 存储桶数（指标格用，失败保持 nil；不计入 anyData——它是统计格不是用量）
        if let buckets = try? await r2Service.listBuckets(accountId: accountId) {
            r2BucketCount = buckets.count
        }
        // CPU 总耗时（独立查询，schema 不支持时保持 nil → UI 回退分位展示）
        if let cpu = try? await analyticsService.workersCpuTotals(accountId: accountId, periodStart: periodStart) {
            usage.cpuTimeMonthUs = cpu.monthUs
            usage.cpuTimeTodayUs = cpu.todayUs
        }
        // D1 行读/写（独立查询）+ 存储（REST 数据库列表 fileSize 求和，需 d1.read）
        if let d1 = try? await analyticsService.d1Usage(accountId: accountId, periodStart: periodStart) {
            usage.d1Usage = d1
            anyData = true
        }
        if let databases = try? await d1Service.listDatabases(accountId: accountId) {
            usage.d1StorageBytes = databases.reduce(0) { $0 + ($1.fileSize ?? 0) }
            d1DatabaseCount = databases.count
            anyData = true
        }
        // KV 读/写 + 存储（独立查询）
        if let kv = try? await analyticsService.kvUsage(accountId: accountId, periodStart: periodStart) {
            usage.kvUsage = kv
            anyData = true
        }
        if let kvStorage = try? await analyticsService.kvStorageBytes(accountId: accountId) {
            usage.kvStorageBytes = kvStorage
            anyData = true
        }

        if anyData {
            self.usage = usage
            usageLoadFailed = false
            usageLoadedForAccount = accountId
            UsageCache.save(usage, accountId: accountId)   // 落盘供下次切回即时显示
            persistAnalyticsAvailability(true)
        } else {
            // 账号级分析全部失败（多为 GraphQL 数据集权限问题，见网络日志 "graphQL error"）。
            // 标记失败态让 UI 显示重试而非永远骨架；不写 usageLoadedForAccount，下次进入会重试。
            usageLoadFailed = true
            AppLog.network.error("account usage load produced no data (all account-level datasets failed)")
        }
    }

    /// 把账户级数据可用性落到 App Group 并广播给 Widget / Watch（统一一处，避免各端不一致）
    private func persistAnalyticsAvailability(_ available: Bool) {
        WidgetDataStore.saveAccountAnalyticsAvailable(available)
        WidgetCenter.shared.reloadTimelines(ofKind: "UsageWidget")
        WatchSessionManager.shared.pushCurrentState()
    }

    /// 拉取各 Zone 的 24h 流量。zone 集合没变化时跳过（Tab 切换不重复请求）。
    /// 成功后写入 Widget 快照（按域名的指标卡数据源）。
    func loadTraffic(zones: [(id: String, name: String)], accountId: String? = nil, force: Bool = false) async {
        let idSet = Set(zones.map(\.id))
        guard !idSet.isEmpty else { return }
        guard force || idSet != loadedZoneIds else { return }
        if let trafficTask {
            await trafficTask.value
            // 等待期间 zone 集合可能又变了（冷启动首批 zone 落库 / 用户置顶）：
            // 集合已是最新就结束，否则接着为新集合发请求，别让新卡片一直空着到下拉刷新。
            guard force || idSet != loadedZoneIds else { return }
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoadTraffic(zones: zones, idSet: idSet, accountId: accountId)
        }
        trafficTask = task
        defer { trafficTask = nil }
        await task.value
    }

    private func performLoadTraffic(zones: [(id: String, name: String)], idSet: Set<String>, accountId: String?) async {
        isLoading = true
        // 流量数据加载失败不打扰 Dashboard（卡片自动隐藏图表）
        if let traffic = try? await analyticsService.trafficByZone24h(zoneIds: zones.map(\.id)) {
            trafficByZone = traffic
            loadedZoneIds = idSet
            writeZoneWidgetSnapshots(zones: zones, traffic: traffic, accountId: accountId)
        }
        isLoading = false
    }

    /// Zone 指标快照 → App Group（Widget 数据源），按账号分桶
    private func writeZoneWidgetSnapshots(zones: [(id: String, name: String)], traffic: [String: ZoneTrafficBundle], accountId: String?) {
        let metrics: [WidgetZoneMetrics] = zones.compactMap { zone in
            guard let bundle = traffic[zone.id], !bundle.points.isEmpty else { return nil }
            let points = bundle.points
            let requests = points.reduce(0) { $0 + $1.requests }
            let cached = points.reduce(0) { $0 + $1.cachedRequests }
            var trend: Double?
            if let previous = bundle.previousRequests, previous > 0 {
                trend = (Double(requests) - Double(previous)) / Double(previous) * 100
            }
            return WidgetZoneMetrics(
                id: zone.id,
                name: zone.name,
                requests: requests,
                bytes: points.reduce(0) { $0 + $1.bytes },
                threats: points.reduce(0) { $0 + $1.threats },
                uniques: points.reduce(0) { $0 + $1.uniques },
                cacheHitRate: requests > 0 ? Double(cached) / Double(requests) * 100 : nil,
                requestsTrend: trend,
                requestsSeries: points.map(\.requests),
                bytesSeries: points.map(\.bytes),
                updatedAt: Date(),
                accountId: accountId
            )
        }
        guard !metrics.isEmpty else { return }
        WidgetDataStore.saveZones(metrics, accountId: accountId ?? "")
        WidgetCenter.shared.reloadTimelines(ofKind: "ZoneStatWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "ZoneChartWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "ZoneStatusWidget")
        // 数据刷新后把最新快照推给 Apple Watch
        WatchSessionManager.shared.pushCurrentState()
    }
}

/// 订阅接口可用性缓存（按账号，跨启动持久）：OAuth token 无 billing 权限时该接口恒 403（cf=10000），
/// 首个确定性拒绝后记住不再探测，免得每次启动固定一条 403 噪音；下拉刷新（force）会绕过重探。
nonisolated enum BillingProbeCache {

    private static let key = "billingProbeUnavailableAccounts"

    static func isUnavailable(accountId: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(accountId)
    }

    static func markUnavailable(accountId: String) {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !list.contains(accountId) else { return }
        list.append(accountId)
        UserDefaults.standard.set(list, forKey: key)
    }

    static func markAvailable(accountId: String) {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard let index = list.firstIndex(of: accountId) else { return }
        list.remove(at: index)
        UserDefaults.standard.set(list, forKey: key)
    }
}

/// 概览用量的本地缓存（按账号）。VM 在 iPad 侧栏返回概览时会被重建，内存里的 usage 随之丢失 →
/// 每次切回都空白重载。缓存让「先显示上次数据、后台静默刷新」成立，切回即有数。
nonisolated enum UsageCache {

    private static let key = "dashboardUsageByAccount"

    private static func loadMap() -> [String: AccountUsage] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let map = try? JSONDecoder().decode([String: AccountUsage].self, from: data) else { return [:] }
        return map
    }

    static func load(accountId: String) -> AccountUsage? {
        loadMap()[accountId]
    }

    static func save(_ usage: AccountUsage, accountId: String) {
        var map = loadMap()
        map[accountId] = usage
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
