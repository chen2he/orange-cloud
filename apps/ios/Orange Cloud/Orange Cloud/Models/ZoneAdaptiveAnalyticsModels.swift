//
//  ZoneAdaptiveAnalyticsModels.swift
//  Orange Cloud
//
//  域名分析区下方的「访问明细」与「安全事件」：GraphQL adaptive 数据集。
//  2026-10-02 起 adaptive 数据集对 Free / Pro 保留 ≥31 天、允许 30 天查询；
//  上方原有图表（httpRequests1hGroups / 1dGroups）、小组件与手表取数一律不动。
//
//  - httpRequestsAdaptiveGroups：按国家/地区、状态码、路径、主机名取 Top 10（count 倒序）
//  - firewallEventsAdaptiveGroups：按处置方式（action）/ 来源（source）计数
//  - firewallEventsAdaptive：最近 20 条安全事件
//
//  查询前先读 zones.settings 的数据集能力（enabled / maxDuration / notOlderThan，单位秒），
//  按它收窄时间窗；数据集不可用就隐藏该块并给一句说明。读设置失败不阻塞，按原窗口查、出错再降级。
//

import Foundation

// MARK: - 访问明细维度

nonisolated enum TrafficBreakdownDimension: String, CaseIterable, Identifiable, Sendable {
    case country = "clientCountryName"
    case status  = "edgeResponseStatus"
    case path    = "clientRequestPath"
    case host    = "clientRequestHTTPHost"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .country: String(localized: "国家/地区")
        case .status:  String(localized: "状态码")
        case .path:    String(localized: "路径")
        case .host:    String(localized: "主机名")
        }
    }
}

/// 一行 Top N：维度取值 + 请求数
nonisolated struct TrafficBreakdownItem: Identifiable, Hashable, Sendable {
    let value: String
    let count: Int
    var id: String { value }
}

/// 四个维度的 Top 10
nonisolated struct TrafficBreakdown: Sendable {
    var items: [TrafficBreakdownDimension: [TrafficBreakdownItem]] = [:]
}

// MARK: - 安全事件

nonisolated struct SecurityEventSummary: Sendable {
    var byAction: [TrafficBreakdownItem] = []
    var bySource: [TrafficBreakdownItem] = []
}

nonisolated struct SecurityEvent: Codable, Identifiable, Hashable, Sendable {
    let datetime:              String?
    let action:                String?
    let source:                String?
    let clientIP:              String?
    let clientCountryName:     String?
    let clientRequestPath:     String?
    let clientRequestHTTPHost: String?
    let rayName:               String?

    /// Ray ID 唯一；个别事件缺 ray 时拼时间与路径兜底
    var id: String { rayName ?? "\(datetime ?? "")|\(clientIP ?? "")|\(clientRequestPath ?? "")" }

    var date: Date? { ISO8601Parse.date(datetime) }
}

/// 防火墙处置方式（action）的展示名：复用 WAF 规则动作的既有文案，认不出原样显示
nonisolated enum SecurityEventAction {
    static func label(_ raw: String?) -> String {
        switch raw {
        case "block":                         String(localized: "拦截")
        case "challenge":                     String(localized: "质询")
        case "managed_challenge":             String(localized: "托管质询")
        case "jschallenge", "js_challenge":   String(localized: "JS 质询")
        case "log":                           String(localized: "记录")
        case "skip", "bypass":                String(localized: "跳过")
        case "allow":                         String(localized: "放行")
        default:                              raw ?? "—"
        }
    }
}

// MARK: - 数据集能力（zones.settings）

nonisolated struct AdaptiveDatasetSettings: Codable, Sendable {
    let enabled:      Bool?
    /// 单次查询最长时间跨度（秒）
    let maxDuration:  Int?
    /// 最早可查到多久以前（秒）
    let notOlderThan: Int?
}

nonisolated struct AdaptiveSettingsData: Codable, Sendable {
    let viewer: Viewer
    nonisolated struct Viewer: Codable, Sendable { let zones: [Zone] }
    nonisolated struct Zone: Codable, Sendable { let settings: Settings? }
    nonisolated struct Settings: Codable, Sendable {
        let httpRequestsAdaptiveGroups: AdaptiveDatasetSettings?
        let firewallEventsAdaptive:     AdaptiveDatasetSettings?
    }
}

/// 某个数据集按能力收窄后的查询窗口
nonisolated struct AdaptiveWindow: Sendable {
    let since: Date
    let until: Date
    /// 比所选范围短（被 maxDuration / notOlderThan 截断）
    let isClamped: Bool

    var duration: TimeInterval { until.timeIntervalSince(since) }

    /// 按能力收窄：先截跨度，再截最早时间
    static func make(rangeSeconds: TimeInterval, settings: AdaptiveDatasetSettings?, now: Date = .now) -> AdaptiveWindow {
        var seconds = rangeSeconds
        if let max = settings?.maxDuration, max > 0 { seconds = min(seconds, TimeInterval(max)) }
        if let oldest = settings?.notOlderThan, oldest > 0 { seconds = min(seconds, TimeInterval(oldest)) }
        // 留 1 分钟余量，免得「恰好等于 30 天」被服务端判超
        let clamped = seconds < rangeSeconds - 60
        return AdaptiveWindow(since: now.addingTimeInterval(-seconds), until: now, isClamped: clamped)
    }
}

// MARK: - 查询

nonisolated enum ZoneAdaptiveQueries {

    static let settings = """
    query ($zoneTag: string!) {
      viewer {
        zones(filter: { zoneTag: $zoneTag }) {
          settings {
            httpRequestsAdaptiveGroups { enabled maxDuration notOlderThan }
            firewallEventsAdaptive { enabled maxDuration notOlderThan }
          }
        }
      }
    }
    """

    /// 四个维度各取 Top 10，别名区分；同一数据集，一次查完
    static let breakdown = """
    query ($zoneTag: string!, $since: Time!, $until: Time!) {
      viewer {
        zones(filter: { zoneTag: $zoneTag }) {
          countries: httpRequestsAdaptiveGroups(limit: 10, orderBy: [count_DESC], filter: { datetime_geq: $since, datetime_lt: $until }) {
            count
            dimensions { clientCountryName }
          }
          statuses: httpRequestsAdaptiveGroups(limit: 10, orderBy: [count_DESC], filter: { datetime_geq: $since, datetime_lt: $until }) {
            count
            dimensions { edgeResponseStatus }
          }
          paths: httpRequestsAdaptiveGroups(limit: 10, orderBy: [count_DESC], filter: { datetime_geq: $since, datetime_lt: $until }) {
            count
            dimensions { clientRequestPath }
          }
          hosts: httpRequestsAdaptiveGroups(limit: 10, orderBy: [count_DESC], filter: { datetime_geq: $since, datetime_lt: $until }) {
            count
            dimensions { clientRequestHTTPHost }
          }
        }
      }
    }
    """

    /// 安全事件计数：按处置方式 / 按来源
    static let firewallGroups = """
    query ($zoneTag: string!, $since: Time!, $until: Time!) {
      viewer {
        zones(filter: { zoneTag: $zoneTag }) {
          byAction: firewallEventsAdaptiveGroups(limit: 10, orderBy: [count_DESC], filter: { datetime_geq: $since, datetime_lt: $until }) {
            count
            dimensions { action }
          }
          bySource: firewallEventsAdaptiveGroups(limit: 10, orderBy: [count_DESC], filter: { datetime_geq: $since, datetime_lt: $until }) {
            count
            dimensions { source }
          }
        }
      }
    }
    """

    /// 最近 20 条安全事件（与计数分开查：任一失败不拖累另一块）
    static let firewallEvents = """
    query ($zoneTag: string!, $since: Time!, $until: Time!) {
      viewer {
        zones(filter: { zoneTag: $zoneTag }) {
          events: firewallEventsAdaptive(limit: 20, orderBy: [datetime_DESC], filter: { datetime_geq: $since, datetime_lt: $until }) {
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
    """
}

nonisolated struct ZoneTagVariables: Codable, Sendable {
    let zoneTag: String
}

nonisolated struct ZoneWindowVariables: Codable, Sendable {
    let zoneTag: String
    let since:   String
    let until:   String
}

// MARK: - 响应

/// adaptive groups 的一行：count + 任一维度（宽容解码，edgeResponseStatus 是数字）
nonisolated struct AdaptiveCountGroup: Codable, Sendable {
    let count: Int?
    let dimensions: Dimensions?

    nonisolated struct Dimensions: Codable, Sendable {
        let clientCountryName:     String?
        let edgeResponseStatus:    Int?
        let clientRequestPath:     String?
        let clientRequestHTTPHost: String?
        let action:                String?
        let source:                String?

        enum CodingKeys: String, CodingKey {
            case clientCountryName, edgeResponseStatus, clientRequestPath, clientRequestHTTPHost, action, source
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            clientCountryName     = try? c.decodeIfPresent(String.self, forKey: .clientCountryName)
            clientRequestPath     = try? c.decodeIfPresent(String.self, forKey: .clientRequestPath)
            clientRequestHTTPHost = try? c.decodeIfPresent(String.self, forKey: .clientRequestHTTPHost)
            action                = try? c.decodeIfPresent(String.self, forKey: .action)
            source                = try? c.decodeIfPresent(String.self, forKey: .source)
            if let code = try? c.decodeIfPresent(Int.self, forKey: .edgeResponseStatus) {
                edgeResponseStatus = code
            } else {
                edgeResponseStatus = (try? c.decodeIfPresent(String.self, forKey: .edgeResponseStatus)).flatMap { Int($0) }
            }
        }
    }
}

nonisolated struct TrafficBreakdownData: Codable, Sendable {
    let viewer: Viewer
    nonisolated struct Viewer: Codable, Sendable { let zones: [Zone] }
    nonisolated struct Zone: Codable, Sendable {
        let countries: [AdaptiveCountGroup]?
        let statuses:  [AdaptiveCountGroup]?
        let paths:     [AdaptiveCountGroup]?
        let hosts:     [AdaptiveCountGroup]?
    }
}

nonisolated struct FirewallGroupsData: Codable, Sendable {
    let viewer: Viewer
    nonisolated struct Viewer: Codable, Sendable { let zones: [Zone] }
    nonisolated struct Zone: Codable, Sendable {
        let byAction: [AdaptiveCountGroup]?
        let bySource: [AdaptiveCountGroup]?
    }
}

nonisolated struct FirewallEventsData: Codable, Sendable {
    let viewer: Viewer
    nonisolated struct Viewer: Codable, Sendable { let zones: [Zone] }
    nonisolated struct Zone: Codable, Sendable { let events: [SecurityEvent]? }
}
