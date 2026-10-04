//
//  SecurityInsightService.swift
//  Orange Cloud
//
//  安全洞察（zone-settings.read / .write，全套餐可用）。端点与字段见 SecurityInsightModels。
//

import Foundation

struct SecurityInsightService {

    private let client: CFAPIClient

    init(client: CFAPIClient) {
        self.client = client
    }

    /// 未忽略的问题（页码分页，逐页拉全；封顶 10 页防异常响应死循环）
    func insights(zoneId: String) async throws -> [SecurityInsight] {
        let perPage = 100
        var all: [SecurityInsight] = []
        for page in 1...10 {
            let response: CFAPIResponse<SecurityInsightPage> = try await client.get(
                "zones/\(zoneId)/security-center/insights",
                queryItems: [
                    URLQueryItem(name: "dismissed", value: "false"),
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "per_page", value: String(perPage)),
                ]
            )
            guard response.success, let result = response.result else {
                throw response.toAPIError()
            }
            let issues = result.issues ?? []
            all.append(contentsOf: issues)
            let total = result.count ?? all.count
            guard issues.count == perPage, all.count < total else { break }
        }
        return all
    }

    /// 发起按需扫描（空 body = 扫描全部）。账户级每 24 小时最多 5 次，超限时 CF 回业务错误，原样透出。
    func startScan(zoneId: String) async throws {
        let response: CFAPIResponse<JSONValue> = try await client.post(
            "zones/\(zoneId)/security-center/insights/scans",
            body: SecurityInsightScanRequest()
        )
        guard response.success else {
            throw response.toAPIError()
        }
    }

    /// 忽略一条问题
    func dismiss(zoneId: String, issueId: String) async throws {
        // 写操作只看 success；result 形态不作假设（JSONValue 宽容接住对象 / null）
        let response: CFAPIResponse<JSONValue> = try await client.put(
            "zones/\(zoneId)/security-center/insights/\(issueId)/dismiss",
            body: SecurityInsightDismissRequest(dismiss: true)
        )
        guard response.success else {
            throw response.toAPIError()
        }
    }
}
