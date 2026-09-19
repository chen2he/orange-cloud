//
//  URLScannerService.swift
//  Orange Cloud
//
//  URL Scanner v2（url-scanner.read / .write）。
//
//  ⚠️ v2 全部端点都**不走 CF 标准信封**（无 success/errors/result 包装）：
//  - POST /scan 2xx 直接回 { uuid, api, result(报告网址 String), message, url, visibility }
//  - GET /result/{id} 2xx 直接回报告对象 { task, page, verdicts, stats, ... }，未就绪回 404
//  - 非 2xx 的错误体是 { message, status, errors:[{title, detail, status}] }，也不是 CF 的 {code, message}
//  以前按 CFAPIResponse<…> 解，提交这一步就必失败（Sentry APPLE-IOS-A0），整条链路从没通过。
//

import Foundation

struct URLScannerService {

    private let client: CFAPIClient

    init(client: CFAPIClient) {
        self.client = client
    }

    /// 提交扫描。异步任务，返回 uuid 后需轮询结果。
    func submit(accountId: String, url: String) async throws -> String? {
        do {
            let accepted: URLScanAccepted = try await client.post(
                "accounts/\(accountId)/urlscanner/v2/scan",
                body: URLScanSubmit(url: url)
            )
            return accepted.uuid
        } catch APIError.serverError(let status) where status == 409 {
            // 同一主机名短时间内已扫过，CF 直接拒绝（错误体非标准信封，client 只能映射成 409）
            throw APIError.cloudflareError(
                code: 409,
                message: String(localized: "该网址最近已扫描过，Cloudflare 暂不接受重复提交，请稍后再试。")
            )
        }
    }

    /// 取扫描报告。未就绪时接口 404，此处返回 nil 交由调用方继续轮询。
    func result(accountId: String, scanId: String) async throws -> URLScanResult? {
        do {
            let report: URLScanResult = try await client.get(
                "accounts/\(accountId)/urlscanner/v2/result/\(scanId)"
            )
            return report
        } catch APIError.notFound {
            return nil
        }
    }

    /// 截图 URL（PNG）。直接交给 AsyncImage 加载，鉴权头由 client 统一带。
    func screenshotPath(accountId: String, scanId: String) -> String {
        "accounts/\(accountId)/urlscanner/v2/screenshots/\(scanId).png"
    }
}
