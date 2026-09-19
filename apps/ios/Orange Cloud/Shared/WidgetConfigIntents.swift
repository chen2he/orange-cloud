//
//  WidgetConfigIntents.swift
//  Orange Cloud（主 App 与 Widget Extension 共享）
//
//  Widget 配置 Intent 及其参数类型。两条防线：
//  1. 必须同时编进两个 target——主 App 自带 App Intents（Core/Intents）时，
//     系统把 widget 配置 intent 归到主 App 名下解析，参数类型只登记在
//     extension 元数据里会解析失败。
//  2. 可选项一律用 AppEntity + EntityQuery，不用 AppEnum——iOS 26.5 存在
//     AppEnum 参数物化回归（见 FB22848510 同类报告），枚举值在 extension
//     进程里还原失败会静默掉回默认值；实体参数由我们自己的 entities(for:)
//     按 identifier 还原，不经过坏掉的路径。
//

import Foundation
import AppIntents

// MARK: - 账号选项（账号总览 / 用量 Widget 可固定某个账号）

nonisolated struct WidgetAccountEntity: AppEntity, Identifiable {

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "账号"
    static let defaultQuery = WidgetAccountEntityQuery()

    let id:        String     // accountId
    let name:      String
    let sessionId: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String, sessionId: String) {
        self.id = id
        self.name = name
        self.sessionId = sessionId
    }

    init(_ account: WidgetAccount) {
        self.init(id: account.id, name: account.name, sessionId: account.sessionId)
    }
}

nonisolated struct WidgetAccountEntityQuery: EntityQuery {

    private func all() -> [WidgetAccountEntity] {
        WidgetDataStore.loadAccounts().map(WidgetAccountEntity.init)
    }

    func entities(for identifiers: [WidgetAccountEntity.ID]) async throws -> [WidgetAccountEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetAccountEntity] {
        all()
    }

    /// 默认 = App Group 记录的当前账号；缺省取目录第一个
    func defaultResult() async -> WidgetAccountEntity? {
        let entities = all()
        if let current = WidgetSnapshot.currentAccountId(),
           let match = entities.first(where: { $0.id == current }) {
            return match
        }
        return entities.first
    }
}

// MARK: - 账号总览 Widget：配置 Intent（固定某个账号）

nonisolated struct AccountOverviewConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择账号"
    static let description = IntentDescription("展示某个账号的 24 小时请求与域名状态")

    @Parameter(title: "账号")
    var account: WidgetAccountEntity?
}

// MARK: - 用量 Widget：服务选项

nonisolated struct UsageServiceEntity: AppEntity, Identifiable {

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "服务"
    static let defaultQuery = UsageServiceEntityQuery()

    let id:   String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static let all: [UsageServiceEntity] = [
        UsageServiceEntity(id: "workers", name: "Workers"),
        UsageServiceEntity(id: "r2",      name: "R2"),
        UsageServiceEntity(id: "d1",      name: "D1"),
        UsageServiceEntity(id: "kv",      name: "KV"),
    ]
}

nonisolated struct UsageServiceEntityQuery: EntityQuery {

    func entities(for identifiers: [UsageServiceEntity.ID]) async throws -> [UsageServiceEntity] {
        UsageServiceEntity.all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [UsageServiceEntity] {
        UsageServiceEntity.all
    }

    func defaultResult() async -> UsageServiceEntity? {
        UsageServiceEntity.all.first
    }
}

nonisolated struct UsageConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择服务"
    static let description = IntentDescription("展示某个服务的额度使用情况")

    @Parameter(title: "服务")
    var service: UsageServiceEntity?

    @Parameter(title: "账号")
    var account: WidgetAccountEntity?

    /// 所选服务 id（未配置时回退 Workers）
    var serviceId: String { service?.id ?? "workers" }
}

// MARK: - 域名 Widget：可选择的域名实体（来自快照）

nonisolated struct WidgetZoneEntity: AppEntity, Identifiable {

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "域名"
    static let defaultQuery = WidgetZoneEntityQuery()

    let id:   String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

nonisolated struct WidgetZoneEntityQuery: EntityQuery {

    /// 快照优先；为空时直接用 token 从 API 拉域名列表（不依赖打开 App）
    private func allEntities() async -> [WidgetZoneEntity] {
        let cached = WidgetDataStore.loadZones().map { WidgetZoneEntity(id: $0.id, name: $0.name) }
        if !cached.isEmpty {
            return cached
        }
        return await fetchZonesFromAPI()
    }

    private func fetchZonesFromAPI() async -> [WidgetZoneEntity] {
        guard let token = SharedAuth.currentValidAccessToken() else { return [] }
        struct Envelope: Decodable {
            let result: [Zone]?
            let resultInfo: Info?
            struct Zone: Decodable {
                let id: String
                let name: String
            }
            struct Info: Decodable {
                let totalPages: Int?
                enum CodingKeys: String, CodingKey { case totalPages = "total_pages" }
            }
            enum CodingKeys: String, CodingKey { case result; case resultInfo = "result_info" }
        }
        // 以前只取一页 50 个：域名多的身份在 App 还没打开过时，选择器里挑不到后面的域名。翻页到底（最多 10 页）。
        var zones: [WidgetZoneEntity] = []
        var page = 1
        while page <= 10 {
            var request = URLRequest(
                url: URL(string: "https://api.cloudflare.com/client/v4/zones?per_page=100&order=name&page=\(page)")!
            )
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(Envelope.self, from: data) else { break }
            zones.append(contentsOf: (decoded.result ?? []).map { WidgetZoneEntity(id: $0.id, name: $0.name) })
            guard page < (decoded.resultInfo?.totalPages ?? 1) else { break }
            page += 1
        }
        return zones
    }

    func entities(for identifiers: [WidgetZoneEntity.ID]) async throws -> [WidgetZoneEntity] {
        await allEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetZoneEntity] {
        await allEntities()
    }

    func defaultResult() async -> WidgetZoneEntity? {
        await allEntities().first
    }
}

// MARK: - 域名 Widget：指标选项

/// 指标的展示/取数逻辑（视图层用，不直接做 intent 参数）
nonisolated enum ZoneWidgetMetric: String {
    case requests
    case bandwidth
    case threats
    case visitors

    var label: String {
        switch self {
        case .requests:  String(localized: "请求 · 24h")
        case .bandwidth: String(localized: "带宽 · 24h")
        case .threats:   String(localized: "已拦截威胁 · 24h")
        case .visitors:  String(localized: "独立访客 · 24h")
        }
    }

    var displayName: String {
        switch self {
        case .requests:  String(localized: "请求")
        case .bandwidth: String(localized: "带宽")
        case .threats:   String(localized: "拦截威胁")
        case .visitors:  String(localized: "独立访客")
        }
    }

    /// SF Symbol（锁屏 inline / Watch complication 用）
    var symbol: String {
        switch self {
        case .requests:  "chart.bar.fill"
        case .bandwidth: "arrow.down.circle.fill"
        case .threats:   "shield.lefthalf.filled"
        case .visitors:  "person.2.fill"
        }
    }

    func valueText(_ zone: WidgetZoneMetrics) -> String {
        switch self {
        case .requests:  zone.requests.formatted(.number.notation(.compactName))
        case .bandwidth: Int64(zone.bytes).ocBytes
        case .threats:   zone.threats.formatted(.number.notation(.compactName))
        case .visitors:  zone.uniques.formatted(.number.notation(.compactName))
        }
    }

    func series(_ zone: WidgetZoneMetrics) -> [Int] {
        switch self {
        case .bandwidth: zone.bytesSeries
        default:         zone.requestsSeries
        }
    }
}

nonisolated struct ZoneMetricEntity: AppEntity, Identifiable {

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "指标"
    static let defaultQuery = ZoneMetricEntityQuery()

    let id:   String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static let all: [ZoneMetricEntity] = [
        ZoneWidgetMetric.requests, .bandwidth, .threats, .visitors,
    ].map { ZoneMetricEntity(id: $0.rawValue, name: $0.displayName) }
}

nonisolated struct ZoneMetricEntityQuery: EntityQuery {

    func entities(for identifiers: [ZoneMetricEntity.ID]) async throws -> [ZoneMetricEntity] {
        ZoneMetricEntity.all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ZoneMetricEntity] {
        ZoneMetricEntity.all
    }

    func defaultResult() async -> ZoneMetricEntity? {
        ZoneMetricEntity.all.first
    }
}

// MARK: - 域名 Widget：配置 Intent

nonisolated struct ZoneStatConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择域名与指标"
    static let description = IntentDescription("展示某个域名的单项 24h 指标")

    @Parameter(title: "域名")
    var zone: WidgetZoneEntity?

    @Parameter(title: "指标")
    var metric: ZoneMetricEntity?

    /// 所选指标（未配置时回退请求）
    var resolvedMetric: ZoneWidgetMetric {
        metric.flatMap { ZoneWidgetMetric(rawValue: $0.id) } ?? .requests
    }
}

nonisolated struct ZoneChartConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择域名"
    static let description = IntentDescription("展示某个域名的请求地形与总览")

    @Parameter(title: "域名")
    var zone: WidgetZoneEntity?
}
