//
//  WorkerIssuesService.swift
//  Orange Cloud
//
//  Workers Issues（公开测试）：账户级问题列表 / 汇总 / 详情 / 改状态 / 发生记录。
//  读 workers-observability.read，改状态 workers-observability.write。端点与字段见 WorkerIssueModels。
//

import Foundation

struct WorkerIssuesService {

    private let client: CFAPIClient

    init(client: CFAPIClient) {
        self.client = client
    }

    private func base(_ accountId: String) -> String {
        "accounts/\(accountId)/workers/observability/issues"
    }

    /// 一页问题（按最近发生时间倒序）。service 为 Worker 名，nil = 全账户。
    /// 返回本页条目与是否还有下一页。
    func issues(
        accountId: String,
        status: WorkerIssueStatus,
        service: String?,
        page: Int,
        perPage: Int = 50
    ) async throws -> (issues: [WorkerIssue], hasMore: Bool) {
        var items = [
            URLQueryItem(name: "status", value: status.rawValue),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "perPage", value: String(min(perPage, 100))),
            URLQueryItem(name: "orderBy", value: "lastObserved"),
            URLQueryItem(name: "order", value: "desc"),
        ]
        if let service, !service.isEmpty {
            items.append(URLQueryItem(name: "service", value: service))
        }
        let response: CFAPIResponseArray<WorkerIssue> = try await client.get(base(accountId), queryItems: items)
        guard response.success else {
            throw response.toAPIError()
        }
        let issues = response.result ?? []
        let hasMore: Bool
        if let totalPages = response.resultInfo?.totalPages {
            hasMore = page < totalPages
        } else {
            hasMore = issues.count >= min(perPage, 100)
        }
        return (issues, hasMore && !issues.isEmpty)
    }

    /// 汇总（活跃问题数 / 活跃发生次数 / 已解决数）。service 为 nil = 全账户。
    func summary(accountId: String, service: String?) async throws -> WorkerIssueSummary {
        var items: [URLQueryItem] = []
        if let service, !service.isEmpty {
            items.append(URLQueryItem(name: "service", value: service))
        }
        let response: CFAPIResponse<WorkerIssueSummary> = try await client.get(
            "\(base(accountId))/summary", queryItems: items
        )
        guard response.success, let result = response.result else {
            throw response.toAPIError()
        }
        return result
    }

    /// 单个问题详情（result.issue）
    func issue(accountId: String, issueId: String) async throws -> WorkerIssue? {
        let response: CFAPIResponse<WorkerIssueResult> = try await client.get(
            "\(base(accountId))/\(Self.encode(issueId))"
        )
        guard response.success else {
            throw response.toAPIError()
        }
        return response.result?.issue
    }

    /// 改状态（resolved / ignored / active）。返回服务端回的问题；解不出时为 nil，调用方本地兜底。
    func setStatus(accountId: String, issueId: String, status: WorkerIssueStatus) async throws -> WorkerIssue? {
        let response: CFAPIResponse<WorkerIssueResult> = try await client.patch(
            "\(base(accountId))/\(Self.encode(issueId))",
            body: WorkerIssueStatusUpdate(status: status.rawValue)
        )
        guard response.success else {
            throw response.toAPIError()
        }
        return response.result?.issue
    }

    /// 一页发生记录（游标分页，cursor 取上一页的 result_info.cursors.after）
    func occurrences(
        accountId: String,
        issueId: String,
        cursor: String?,
        perPage: Int = 20
    ) async throws -> (occurrences: [WorkerIssueOccurrence], nextCursor: String?) {
        var items = [URLQueryItem(name: "per_page", value: String(perPage))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        let response: WorkerIssueOccurrencesResponse = try await client.get(
            "\(base(accountId))/\(Self.encode(issueId))/occurrences",
            queryItems: items
        )
        guard response.success else {
            throw response.toAPIError()
        }
        return (response.result ?? [], response.nextCursor)
    }

    /// issueId 作路径段（path 视为已编码），保守百分号编码
    private static func encode(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? segment
    }
}
