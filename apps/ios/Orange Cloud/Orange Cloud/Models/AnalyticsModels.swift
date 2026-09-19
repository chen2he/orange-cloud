//
//  AnalyticsModels.swift
//  Orange Cloud
//
//  Zone 流量分析：GraphQL Analytics API 的查询模板、变量与响应模型。
//  数据集：httpRequests1hGroups（24h）/ httpRequests1dGroups（7d/30d）。
//

import Foundation

// MARK: - 时间范围

nonisolated enum AnalyticsTimeRange: String, CaseIterable, Identifiable, Sendable {
    case last24h = "24h"
    case last7d  = "7d"
    case last30d = "30d"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .last24h: String(localized: "24 小时")
        case .last7d:  String(localized: "7 天")
        case .last30d: String(localized: "30 天")
        }
    }

    var periodLabel: String {
        switch self {
        case .last24h: String(localized: "过去 24 小时")
        case .last7d:  String(localized: "过去 7 天")
        case .last30d: String(localized: "过去 30 天")
        }
    }

    /// 24h 用小时级数据集（Time 标量），7d/30d 用天级（Date 标量，规避低套餐的小时数据留存限制）
    var usesHourlyGroups: Bool { self == .last24h }

    var limit: Int {
        switch self {
        case .last24h: 25
        case .last7d:  7
        case .last30d: 30
        }
    }

    private var dayCount: Int { self == .last7d ? 6 : 29 }

    /// 当前周期的查询区间。小时级返回 ISO8601 datetime，天级返回 yyyy-MM-dd（UTC）
    func sinceUntil(now: Date = .now) -> (since: String, until: String) {
        if usesHourlyGroups {
            let formatter = ISO8601Parse.plain
            return (
                formatter.string(from: now.addingTimeInterval(-24 * 3600)),
                formatter.string(from: now)
            )
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -dayCount, to: today) ?? today
        return (Self.dayFormatter.string(from: start), Self.dayFormatter.string(from: today))
    }

    /// 前一个等长周期（环比趋势用）
    func previousSinceUntil(now: Date = .now) -> (since: String, until: String) {
        if usesHourlyGroups {
            let formatter = ISO8601Parse.plain
            return (
                formatter.string(from: now.addingTimeInterval(-48 * 3600)),
                formatter.string(from: now.addingTimeInterval(-24 * 3600))
            )
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.startOfDay(for: now)
        let until = calendar.date(byAdding: .day, value: -(dayCount + 1), to: today) ?? today
        let since = calendar.date(byAdding: .day, value: -dayCount, to: until) ?? until
        return (Self.dayFormatter.string(from: since), Self.dayFormatter.string(from: until))
    }

    /// 统一 ISO8601 datetime 窗口（Workers 指标等 Time 标量过滤用，三个范围通用）
    func datetimeWindow(now: Date = .now) -> (since: String, until: String) {
        let formatter = ISO8601Parse.plain
        let seconds: TimeInterval = switch self {
        case .last24h: 24 * 3600
        case .last7d:  7 * 24 * 3600
        case .last30d: 30 * 24 * 3600
        }
        return (
            formatter.string(from: now.addingTimeInterval(-seconds)),
            formatter.string(from: now)
        )
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

// MARK: - 查询模板

nonisolated enum AnalyticsQueries {

    /// 24h：小时级，$since/$until 是 Time 标量
    static func zoneHourly(limit: Int) -> String {
        """
        query ($zoneTag: string!, $since: Time!, $until: Time!) {
          viewer {
            zones(filter: { zoneTag: $zoneTag }) {
              httpRequests1hGroups(
                limit: \(limit),
                orderBy: [datetime_ASC],
                filter: { datetime_geq: $since, datetime_lt: $until }
              ) {
                dimensions { datetime }
                sum  { requests bytes threats pageViews cachedRequests cachedBytes }
                uniq { uniques }
              }
            }
          }
        }
        """
    }

    /// Dashboard / Widget：多 Zone 一次查询（24h 小时级 + 前一窗口请求总数），节点带回 zoneTag 用于归属
    static func multiZoneHourly(limit: Int) -> String {
        """
        query ($zoneTags: [string!], $since: Time!, $until: Time!, $prevSince: Time!) {
          viewer {
            zones(filter: { zoneTag_in: $zoneTags }) {
              zoneTag
              httpRequests1hGroups(
                limit: \(limit),
                orderBy: [datetime_ASC],
                filter: { datetime_geq: $since, datetime_lt: $until }
              ) {
                dimensions { datetime }
                sum  { requests bytes threats pageViews cachedRequests cachedBytes }
                uniq { uniques }
              }
              previous: httpRequests1hGroups(
                limit: \(limit),
                filter: { datetime_geq: $prevSince, datetime_lt: $since }
              ) {
                sum { requests }
              }
            }
          }
        }
        """
    }

    /// 7d/30d：天级，$since/$until 是 Date 标量
    static func zoneDaily(limit: Int) -> String {
        """
        query ($zoneTag: string!, $since: Date!, $until: Date!) {
          viewer {
            zones(filter: { zoneTag: $zoneTag }) {
              httpRequests1dGroups(
                limit: \(limit),
                orderBy: [date_ASC],
                filter: { date_geq: $since, date_leq: $until }
              ) {
                dimensions { date }
                sum  { requests bytes threats pageViews cachedRequests cachedBytes }
                uniq { uniques }
              }
            }
          }
        }
        """
    }

    /// 24h：按国家/地区聚合（小时桶各自携带 countryMap，Swift 端合并）
    static func zoneCountryHourly(limit: Int) -> String {
        """
        query ($zoneTag: string!, $since: Time!, $until: Time!) {
          viewer {
            zones(filter: { zoneTag: $zoneTag }) {
              httpRequests1hGroups(
                limit: \(limit),
                filter: { datetime_geq: $since, datetime_lt: $until }
              ) {
                sum { countryMap { clientCountryName requests threats bytes } }
              }
            }
          }
        }
        """
    }

    /// 7d/30d：按国家/地区聚合（天桶各自携带 countryMap）
    static func zoneCountryDaily(limit: Int) -> String {
        """
        query ($zoneTag: string!, $since: Date!, $until: Date!) {
          viewer {
            zones(filter: { zoneTag: $zoneTag }) {
              httpRequests1dGroups(
                limit: \(limit),
                filter: { date_geq: $since, date_leq: $until }
              ) {
                sum { countryMap { clientCountryName requests threats bytes } }
              }
            }
          }
        }
        """
    }
}

nonisolated struct ZoneAnalyticsVariables: Codable, Sendable {
    let zoneTag: String
    let since:   String
    let until:   String
}

nonisolated struct MultiZoneAnalyticsVariables: Codable, Sendable {
    let zoneTags:  [String]
    let since:     String
    let until:     String
    let prevSince: String     // 前一个 24h 窗口起点（趋势对比）
}

/// 多 Zone 查询的归一化结果：当前窗口数据点 + 前一窗口请求总数
nonisolated struct ZoneTrafficBundle: Sendable {
    let points:           [TrafficDataPoint]
    let previousRequests: Int?
}

// MARK: - GraphQL 响应模型

nonisolated struct ZoneAnalyticsData: Codable, Sendable {
    let viewer: AnalyticsViewer
}

nonisolated struct AnalyticsViewer: Codable, Sendable {
    let zones: [AnalyticsZoneNode]
}

nonisolated struct AnalyticsZoneNode: Codable, Sendable {
    let zoneTag: String?          // 多 Zone 查询时回传，单 Zone 查询不请求该字段
    let httpRequests1hGroups: [AnalyticsGroup]?
    let httpRequests1dGroups: [AnalyticsGroup]?
    let previous: [AnalyticsGroup]?    // 多 Zone 查询的前一窗口（仅 sum.requests）

    var groups: [AnalyticsGroup] {
        httpRequests1hGroups ?? httpRequests1dGroups ?? []
    }
}

nonisolated struct AnalyticsGroup: Codable, Sendable {
    let dimensions: AnalyticsDimensions?
    let sum:        AnalyticsSum?
    let uniq:       AnalyticsUniq?
}

nonisolated struct AnalyticsDimensions: Codable, Sendable {
    let datetime: String?    // 1hGroups
    let date:     String?    // 1dGroups
}

nonisolated struct AnalyticsSum: Codable, Sendable {
    let requests:       Int?
    let bytes:          Int?
    let threats:        Int?
    let pageViews:      Int?
    let cachedRequests: Int?
    let cachedBytes:    Int?
    let countryMap:     [CountryMapEntry]?    // 仅按国家聚合的查询请求该字段
}

/// GraphQL `sum.countryMap` 单条目（clientCountryName 是 ISO-3166-1 alpha-2）
nonisolated struct CountryMapEntry: Codable, Sendable {
    let clientCountryName: String?
    let requests:          Int?
    let threats:           Int?
    let bytes:             Int?
}

nonisolated struct AnalyticsUniq: Codable, Sendable {
    let uniques: Int?
}

// MARK: - 图表数据点（两种 dimensions 归一化后的统一形态）

nonisolated struct TrafficDataPoint: Identifiable, Sendable {
    let date:           Date
    let requests:       Int
    let bytes:          Int
    let threats:        Int
    let pageViews:      Int
    let uniques:        Int
    let cachedRequests: Int

    var id: Date { date }
}

// MARK: - 按国家/地区聚合（全球流量地图）

/// 窗口内单个国家/地区的流量聚合（countryMap 跨时间桶合并后的结果）
nonisolated struct CountryTraffic: Identifiable, Sendable {
    let countryCode: String    // ISO-3166-1 alpha-2，如 "US"、"CN"
    let requests:    Int
    let threats:     Int
    let bytes:       Int

    var id: String { countryCode }

    /// 本地化国家/地区名；无法解析（如 Tor 的 "T1"、未知码）时回退原始码
    var displayName: String {
        Locale.current.localizedString(forRegionCode: countryCode) ?? countryCode
    }
}
