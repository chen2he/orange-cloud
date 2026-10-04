//
//  ZoneTrafficDetailsViewModel.swift
//  Orange Cloud
//
//  域名分析区的「访问明细」（Top 10 国家/地区 · 状态码 · 路径 · 主机名）与「安全事件」
//  （按处置方式 / 按来源计数 + 最近 20 条）。跟随上方分析区所选范围（24h 免费、7d/30d Pro，
//  范围闸门由 ZoneAnalyticsSection 的选择器负责），按范围做会话级内存缓存。
//
//  先读 zones.settings 的数据集能力收窄时间窗；数据集关闭 / 未授权则该块标记为不可用（隐藏并说明），
//  读设置失败不阻塞，按所选范围直接查、出错再降级。
//

import Foundation
import Observation

@Observable
@MainActor
final class ZoneTrafficDetailsViewModel {

    /// 某一块（访问明细 / 安全事件）在某个范围下的加载结果
    struct BlockState<Value> {
        var value: Value?
        /// 数据集未开放 / 未授权：隐藏内容，只给一句说明
        var unavailable = false
        var error: String?
        /// 实际查询窗口（被数据集能力截断时用于提示）
        var window: AdaptiveWindow?
    }

    struct SecurityValue {
        var summary: SecurityEventSummary
        var events: [SecurityEvent]
    }

    struct Snapshot {
        var traffic = BlockState<TrafficBreakdown>()
        var security = BlockState<SecurityValue>()
    }

    private(set) var snapshot: Snapshot?
    var isLoading = false
    /// 访问明细当前选中的维度
    var dimension: TrafficBreakdownDimension = .country

    private var cache: [AnalyticsTimeRange: Snapshot] = [:]
    private var settings: AdaptiveSettingsData.Settings?
    private var settingsLoaded = false
    /// 最近一次请求的范围：晚到的旧范围结果只进缓存、不上屏
    private var requestedRange: AnalyticsTimeRange?

    private let service: ZoneAdaptiveAnalyticsService
    private let zoneId: String

    init(service: ZoneAdaptiveAnalyticsService, zoneId: String) {
        self.service = service
        self.zoneId = zoneId
    }

    func load(range: AnalyticsTimeRange, force: Bool = false) async {
        requestedRange = range
        if !force, let cached = cache[range] {
            snapshot = cached
            return
        }
        isLoading = true
        if !settingsLoaded || force {
            // 读不到能力设置（schema / 权限差异）就当未知，按所选范围直接查
            settings = try? await service.settings(zoneId: zoneId)
            settingsLoaded = true
        }
        let seconds = Self.seconds(of: range)

        async let trafficTask = loadTraffic(seconds: seconds)
        async let securityTask = loadSecurity(seconds: seconds)
        let result = Snapshot(traffic: await trafficTask, security: await securityTask)

        guard !Task.isCancelled else { return }
        cache[range] = result
        guard range == requestedRange else { return }
        snapshot = result
        isLoading = false
    }

    /// 下拉刷新：清空缓存、重读能力设置
    func refresh(range: AnalyticsTimeRange) async {
        cache.removeAll()
        await load(range: range, force: true)
    }

    // MARK: - 两块各自加载（互不拖累）

    private func loadTraffic(seconds: TimeInterval) async -> BlockState<TrafficBreakdown> {
        var state = BlockState<TrafficBreakdown>()
        let datasetSettings = settings?.httpRequestsAdaptiveGroups
        if datasetSettings?.enabled == false {
            state.unavailable = true
            return state
        }
        let window = AdaptiveWindow.make(rangeSeconds: seconds, settings: datasetSettings)
        state.window = window
        do {
            state.value = try await service.breakdown(zoneId: zoneId, window: window)
        } catch {
            Self.apply(error, to: &state)
        }
        return state
    }

    private func loadSecurity(seconds: TimeInterval) async -> BlockState<SecurityValue> {
        var state = BlockState<SecurityValue>()
        let datasetSettings = settings?.firewallEventsAdaptive
        if datasetSettings?.enabled == false {
            state.unavailable = true
            return state
        }
        let window = AdaptiveWindow.make(rangeSeconds: seconds, settings: datasetSettings)
        state.window = window
        // 计数与明细分开查：任一失败另一块照常展示
        async let summaryTask = service.securitySummary(zoneId: zoneId, window: window)
        async let eventsTask = service.recentSecurityEvents(zoneId: zoneId, window: window)
        var summary: SecurityEventSummary?
        var events: [SecurityEvent]?
        var firstError: Error?
        do { summary = try await summaryTask } catch { firstError = error }
        do { events = try await eventsTask } catch { firstError = firstError ?? error }

        if summary == nil && events == nil, let firstError {
            Self.apply(firstError, to: &state)
        } else {
            state.value = SecurityValue(summary: summary ?? SecurityEventSummary(), events: events ?? [])
        }
        return state
    }

    /// 未授权（套餐 / 权限不含该数据集）按不可用处理；其余记错误文案
    private static func apply<Value>(_ error: Error, to state: inout BlockState<Value>) {
        if let apiError = error as? APIError, apiError.isAccountNotAuthorized || apiError.isPermissionDenied {
            state.unavailable = true
        } else if !error.isCancellation {
            state.error = error.localizedDescription
        }
    }

    private static func seconds(of range: AnalyticsTimeRange) -> TimeInterval {
        switch range {
        case .last24h: 24 * 3600
        case .last7d:  7 * 24 * 3600
        case .last30d: 30 * 24 * 3600
        }
    }
}
