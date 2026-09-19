//
//  WorkerLogsViewModel.swift
//  Orange Cloud
//
//  Workers 历史日志：按时间窗查 Observability 事件，游标续页（越翻越早）。
//  级别与关键词都下推到服务端过滤，避免只在本页内筛。
//

import Foundation
import Observation

@Observable
@MainActor
final class WorkerLogsViewModel {

    /// 查询时间窗。Workers Logs 的保留期有限（免费层更短），不提供超长范围。
    nonisolated enum TimeRange: String, CaseIterable, Identifiable, Sendable {
        case m30, h3, h24, d3

        var id: String { rawValue }

        var seconds: TimeInterval {
            switch self {
            case .m30: 30 * 60
            case .h3:  3 * 3600
            case .h24: 24 * 3600
            case .d3:  3 * 24 * 3600
            }
        }

        var label: String {
            switch self {
            case .m30: String(localized: "30 分钟")
            case .h3:  String(localized: "3 小时")
            case .h24: String(localized: "24 小时")
            case .d3:  String(localized: "3 天")
            }
        }
    }

    /// 级别筛选，与实时日志口径保持一致
    nonisolated enum LevelFilter: String, CaseIterable, Identifiable, Sendable {
        case all, log, debug, info, warn, error

        var id: String { rawValue }

        /// 下推给服务端的 $metadata.level 值；all 不下推
        var queryValue: String? { self == .all ? nil : rawValue }

        var title: String {
            switch self {
            case .all:   String(localized: "全部级别")
            case .log:   "log"
            case .debug: "debug"
            case .info:  "info"
            case .warn:  "warn"
            case .error: "error"
            }
        }
    }

    private(set) var events: [IdentifiedLogEvent] = []
    private(set) var totalCount: Int?
    private(set) var canLoadMore = false
    var isLoading = false
    var isLoadingMore = false
    var error: String?

    /// 改这三个都要重查（服务端过滤）
    var range: TimeRange = .h24
    var levelFilter: LevelFilter = .all
    var searchText = ""

    private let service: WorkerLogsService
    private let accountId: String
    private let scriptName: String

    /// 时间窗在首次加载时定住，续页复用同一窗口，避免翻页时窗口随时间漂移
    private var since: Date?
    private var until: Date?
    private var cursor: String?

    private static let pageSize = 100

    init(service: WorkerLogsService, accountId: String, scriptName: String) {
        self.service = service
        self.accountId = accountId
        self.scriptName = scriptName
    }

    /// 每次 load 递增；晚到的旧一代结果一律丢弃。
    /// 视图用两个 .task(id:) 调 load：改时间窗 / 级别会取消旧任务再起新任务，
    /// 以前的 `guard !isLoading` 会让新任务在旧任务的 catch 跑完之前直接退出——
    /// 结果是旧任务把「已取消」写进 error、清空列表，而新范围永远不查。
    private var loadGeneration = 0

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        error = nil

        let until = Date()
        let since = until.addingTimeInterval(-range.seconds)
        self.until = until
        self.since = since
        self.cursor = nil

        do {
            let result = try await service.events(
                accountId: accountId, scriptName: scriptName,
                since: since, until: until,
                level: levelFilter.queryValue, search: searchText,
                cursor: nil, limit: Self.pageSize
            )
            guard generation == loadGeneration else { return }
            let page = (result.events?.events ?? []).map { IdentifiedLogEvent(event: $0) }
            events = page
            totalCount = result.events?.count.map { Int($0) }
            cursor = page.last?.event.metadata?.id
            canLoadMore = page.count >= Self.pageSize && cursor != nil
        } catch {
            guard generation == loadGeneration, !error.isCancellation else { return }
            self.error = error.localizedDescription
            events = []
            totalCount = nil
            canLoadMore = false
        }
        isLoading = false
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, canLoadMore,
              let since, let until, let cursor else { return }
        isLoadingMore = true
        do {
            let result = try await service.events(
                accountId: accountId, scriptName: scriptName,
                since: since, until: until,
                level: levelFilter.queryValue, search: searchText,
                cursor: cursor, limit: Self.pageSize
            )
            let page = (result.events?.events ?? []).map { IdentifiedLogEvent(event: $0) }
            // 服务端游标偶发回重复条目，按 id 去重再追加
            let known = Set(events.map(\.id))
            events.append(contentsOf: page.filter { !known.contains($0.id) })
            self.cursor = page.last?.event.metadata?.id
            canLoadMore = page.count >= Self.pageSize && self.cursor != nil
        } catch {
            self.error = error.localizedDescription
            canLoadMore = false
        }
        isLoadingMore = false
    }
}
