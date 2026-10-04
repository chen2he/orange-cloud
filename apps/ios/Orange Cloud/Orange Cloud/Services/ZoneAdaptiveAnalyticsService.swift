//
//  ZoneAdaptiveAnalyticsService.swift
//  Orange Cloud
//
//  域名「访问明细」「安全事件」的 adaptive 数据集查询（analytics.read）。
//  与 AnalyticsService 分开：上方既有图表、小组件 / 手表取数不受任何影响。
//  查询与模型见 ZoneAdaptiveAnalyticsModels。
//

import Foundation

struct ZoneAdaptiveAnalyticsService {

    private let client: CFAPIClient

    init(client: CFAPIClient) {
        self.client = client
    }

    /// 数据集能力（enabled / maxDuration / notOlderThan）。失败抛错，调用方按「未知」处理不阻塞。
    func settings(zoneId: String) async throws -> AdaptiveSettingsData.Settings? {
        let data: AdaptiveSettingsData = try await client.graphQL(
            query: ZoneAdaptiveQueries.settings,
            variables: ZoneTagVariables(zoneTag: zoneId)
        )
        return data.viewer.zones.first?.settings
    }

    /// 四个维度的 Top 10（按请求数）
    func breakdown(zoneId: String, window: AdaptiveWindow) async throws -> TrafficBreakdown {
        let data: TrafficBreakdownData = try await client.graphQL(
            query: ZoneAdaptiveQueries.breakdown,
            variables: Self.variables(zoneId, window)
        )
        guard let zone = data.viewer.zones.first else { return TrafficBreakdown() }
        var result = TrafficBreakdown()
        result.items[.country] = Self.items(zone.countries) { $0.clientCountryName }
        result.items[.status]  = Self.items(zone.statuses) { $0.edgeResponseStatus.map(String.init) }
        result.items[.path]    = Self.items(zone.paths) { $0.clientRequestPath }
        result.items[.host]    = Self.items(zone.hosts) { $0.clientRequestHTTPHost }
        return result
    }

    /// 安全事件计数（按处置方式 / 按来源）
    func securitySummary(zoneId: String, window: AdaptiveWindow) async throws -> SecurityEventSummary {
        let data: FirewallGroupsData = try await client.graphQL(
            query: ZoneAdaptiveQueries.firewallGroups,
            variables: Self.variables(zoneId, window)
        )
        guard let zone = data.viewer.zones.first else { return SecurityEventSummary() }
        return SecurityEventSummary(
            byAction: Self.items(zone.byAction) { $0.action },
            bySource: Self.items(zone.bySource) { $0.source }
        )
    }

    /// 最近 20 条安全事件
    func recentSecurityEvents(zoneId: String, window: AdaptiveWindow) async throws -> [SecurityEvent] {
        let data: FirewallEventsData = try await client.graphQL(
            query: ZoneAdaptiveQueries.firewallEvents,
            variables: Self.variables(zoneId, window)
        )
        return data.viewer.zones.first?.events ?? []
    }

    // MARK: - 辅助

    private nonisolated static func variables(_ zoneId: String, _ window: AdaptiveWindow) -> ZoneWindowVariables {
        ZoneWindowVariables(
            zoneTag: zoneId,
            since: ISO8601Parse.plain.string(from: window.since),
            until: ISO8601Parse.plain.string(from: window.until)
        )
    }

    /// 分组 → Top N 行；空取值（如无国家信息）记作「—」
    private nonisolated static func items(
        _ groups: [AdaptiveCountGroup]?,
        value: (AdaptiveCountGroup.Dimensions) -> String?
    ) -> [TrafficBreakdownItem] {
        var merged: [String: Int] = [:]
        var order: [String] = []
        for group in groups ?? [] {
            let raw = group.dimensions.flatMap(value) ?? ""
            let key = raw.isEmpty ? "—" : raw
            if merged[key] == nil { order.append(key) }
            merged[key, default: 0] += group.count ?? 0
        }
        return order
            .map { TrafficBreakdownItem(value: $0, count: merged[$0] ?? 0) }
            .sorted { $0.count > $1.count }
    }
}
