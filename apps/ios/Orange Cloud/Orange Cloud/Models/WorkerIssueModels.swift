//
//  WorkerIssueModels.swift
//  Orange Cloud
//
//  Workers Issues（2026-09-30 公开测试）：Cloudflare 把 Worker 的未捕获异常、5xx 响应与
//  错误日志自动归类成「问题」。账户级端点，读 workers-observability.read，改状态 .write。
//    GET   /accounts/{id}/workers/observability/issues                 列表（页码分页）
//    GET   …/issues/summary?service=                                    汇总
//    GET   …/issues/{issueId}                                            详情（result.issue）
//    PATCH …/issues/{issueId}  {"status": "resolved"|"ignored"|"active"}  改状态
//    GET   …/issues/{issueId}/occurrences?per_page=&cursor=             发生记录（游标分页）
//
//  公开测试期字段随时可能变：全部可选、宽容解码。时间戳是数字，按毫秒处理；
//  小于 1e12 的按秒（防个别字段回秒级）。字段名是 camelCase（与多数 CF 端点不同）。
//

import Foundation

// MARK: - 状态

nonisolated enum WorkerIssueStatus: String, CaseIterable, Identifiable, Sendable {
    case active
    case resolved
    case ignored

    var id: String { rawValue }

    var label: String {
        switch self {
        case .active:   String(localized: "活跃")
        case .resolved: String(localized: "已解决")
        case .ignored:  String(localized: "已忽略")
        }
    }
}

// MARK: - 问题

nonisolated struct WorkerIssue: Codable, Identifiable, Hashable, Sendable {
    let id:            String
    let title:         String?
    /// Worker 名
    let service:       String?
    let status:        String?
    let count:         Int?
    let firstObserved: Date?
    let lastObserved:  Date?
    let statusUpdated: Date?
    let created:       Date?
    let updated:       Date?
    let type:          String?
    let fingerprint:   String?

    enum CodingKeys: String, CodingKey {
        case id, title, service, status, count, firstObserved, lastObserved
        case statusUpdated, created, updated, type, fingerprint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(String.self, forKey: .id)
        title         = try? c.decodeIfPresent(String.self, forKey: .title)
        service       = try? c.decodeIfPresent(String.self, forKey: .service)
        status        = try? c.decodeIfPresent(String.self, forKey: .status)
        count         = c.flexibleInt(.count)
        firstObserved = c.timestamp(.firstObserved)
        lastObserved  = c.timestamp(.lastObserved)
        statusUpdated = c.timestamp(.statusUpdated)
        created       = c.timestamp(.created)
        updated       = c.timestamp(.updated)
        type          = try? c.decodeIfPresent(String.self, forKey: .type)
        fingerprint   = try? c.decodeIfPresent(String.self, forKey: .fingerprint)
    }

    /// 已知状态；未知取值按活跃处理（只影响可用操作，不影响展示）
    var knownStatus: WorkerIssueStatus { WorkerIssueStatus(rawValue: status ?? "") ?? .active }

    var displayTitle: String {
        guard let title, !title.isEmpty else { return type ?? id }
        return title
    }

    /// 本地改状态（PATCH 响应解不出完整问题时兜底）
    func with(status: WorkerIssueStatus) -> WorkerIssue {
        WorkerIssue(copying: self, status: status.rawValue)
    }

    private init(copying other: WorkerIssue, status: String) {
        id = other.id; title = other.title; service = other.service
        self.status = status
        count = other.count; firstObserved = other.firstObserved; lastObserved = other.lastObserved
        statusUpdated = Date(); created = other.created; updated = other.updated
        type = other.type; fingerprint = other.fingerprint
    }
}

/// 详情 GET 的 result 是 {issue}；PATCH 的 result 文档写「更新后的问题」，
/// 两种形态（{issue} 包一层 / 直接是问题）都接住，解不出时 issue 为 nil 而不是整条失败。
nonisolated struct WorkerIssueResult: Codable, Sendable {
    let issue: WorkerIssue?

    enum CodingKeys: String, CodingKey { case issue }

    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let wrapped = try? c.decodeIfPresent(WorkerIssue.self, forKey: .issue) {
            issue = wrapped
        } else {
            issue = try? WorkerIssue(from: decoder)
        }
    }
}

// MARK: - 汇总

nonisolated struct WorkerIssueSummary: Codable, Sendable {
    let activeIssues:      Int?
    let activeOccurrences: Int?
    let resolvedIssues:    Int?
    let lastIssue:         Date?

    enum CodingKeys: String, CodingKey {
        case activeIssues, activeOccurrences, resolvedIssues, lastIssue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeIssues      = c.flexibleInt(.activeIssues)
        activeOccurrences = c.flexibleInt(.activeOccurrences)
        resolvedIssues    = c.flexibleInt(.resolvedIssues)
        lastIssue         = c.timestamp(.lastIssue)
    }
}

// MARK: - 发生记录

nonisolated struct WorkerIssueOccurrence: Codable, Identifiable, Sendable {
    let id:         String
    let timestamp:  Date?
    let error:      OccurrenceError?
    let invocation: Invocation?

    enum CodingKeys: String, CodingKey {
        case id, timestamp, error, invocation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 个别条目可能缺 id：用时间戳兜底，保证列表可区分
        let ts = c.timestamp(.timestamp)
        id         = (try? c.decodeIfPresent(String.self, forKey: .id))
            ?? ts.map { String($0.timeIntervalSince1970) } ?? UUID().uuidString
        timestamp  = ts
        error      = try? c.decodeIfPresent(OccurrenceError.self, forKey: .error)
        invocation = try? c.decodeIfPresent(Invocation.self, forKey: .invocation)
    }

    nonisolated struct OccurrenceError: Codable, Sendable {
        let name:    String?
        let message: String?
        let stack:   String?
        let handled: Bool?

        enum CodingKeys: String, CodingKey { case name, message, stack, handled }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name    = try? c.decodeIfPresent(String.self, forKey: .name)
            message = try? c.decodeIfPresent(String.self, forKey: .message)
            stack   = try? c.decodeIfPresent(String.self, forKey: .stack)
            handled = try? c.decodeIfPresent(Bool.self, forKey: .handled)
        }
    }

    nonisolated struct Invocation: Codable, Sendable {
        let method:     String?
        let path:       String?
        let url:        String?
        let statusCode: Int?
        let rayId:      String?
        let cron:       String?
        let queue:      String?
        let type:       String?

        enum CodingKeys: String, CodingKey {
            case method, path, url, statusCode, rayId, cron, queue, type
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            method     = try? c.decodeIfPresent(String.self, forKey: .method)
            path       = try? c.decodeIfPresent(String.self, forKey: .path)
            url        = try? c.decodeIfPresent(String.self, forKey: .url)
            statusCode = c.flexibleInt(.statusCode)
            rayId      = try? c.decodeIfPresent(String.self, forKey: .rayId)
            cron       = try? c.decodeIfPresent(String.self, forKey: .cron)
            queue      = try? c.decodeIfPresent(String.self, forKey: .queue)
            type       = try? c.decodeIfPresent(String.self, forKey: .type)
        }

        /// 「方法 + 路径」；没有 HTTP 信息时退到 cron / 队列 / 触发类型
        var summary: String? {
            if let method, let target = path ?? url { return "\(method) \(target)" }
            if let target = path ?? url { return target }
            if let cron, !cron.isEmpty { return "cron \(cron)" }
            if let queue, !queue.isEmpty { return "queue \(queue)" }
            return type
        }
    }

    /// 「错误名: 消息」
    var headline: String {
        let name = error?.name?.isEmpty == false ? error?.name : nil
        let message = error?.message?.isEmpty == false ? error?.message : nil
        switch (name, message) {
        case let (n?, m?): return "\(n): \(m)"
        case let (n?, nil): return n
        case let (nil, m?): return m
        default: return invocation?.summary ?? id
        }
    }
}

/// occurrences 的信封：游标在 result_info.cursors.after（公共 ResultInfo 没有这一层，单独建模）
nonisolated struct WorkerIssueOccurrencesResponse: Codable, Sendable {
    let result:     [WorkerIssueOccurrence]?
    let success:    Bool
    let errors:     [CFAPIError]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case result, success, errors
        case resultInfo = "result_info"
    }

    private struct Info: Codable {
        let cursors: Cursors?
        struct Cursors: Codable { let after: String? }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        result     = try? c.decodeIfPresent([WorkerIssueOccurrence].self, forKey: .result)
        success    = try c.decode(Bool.self, forKey: .success)
        errors     = (try? c.decode([CFAPIError].self, forKey: .errors)) ?? []
        let after  = (try? c.decodeIfPresent(Info.self, forKey: .resultInfo))?.cursors?.after
        nextCursor = (after?.isEmpty == false) ? after : nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(result, forKey: .result)
        try c.encode(success, forKey: .success)
        try c.encode(errors, forKey: .errors)
    }

    func toAPIError() -> APIError {
        let err = errors.first
        return .cloudflareError(code: err?.code ?? 0,
                                message: err?.message ?? String(localized: "未知错误"),
                                documentationURL: err?.documentationURL)
    }
}

/// PATCH 请求体
nonisolated struct WorkerIssueStatusUpdate: Codable, Sendable {
    let status: String
}

// MARK: - 宽容解码辅助

private extension KeyedDecodingContainer {
    /// 数字时间戳 → Date：按毫秒，小于 1e12 视为秒；也接受数字字符串与 ISO8601
    nonisolated func timestamp(_ key: Key) -> Date? {
        if let number = try? decodeIfPresent(Double.self, forKey: key) {
            return Self.date(fromEpoch: number)
        }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            if let number = Double(text) { return Self.date(fromEpoch: number) }
            return ISO8601Parse.date(text)
        }
        return nil
    }

    /// 整数字段：兼容 Int / 浮点数 / 数字字符串
    nonisolated func flexibleInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return Int(text) }
        return nil
    }

    nonisolated private static func date(fromEpoch value: Double) -> Date? {
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value < 1e12 ? value : value / 1000)
    }
}
