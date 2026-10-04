//
//  SecurityInsightsViewModel.swift
//  Orange Cloud
//
//  安全洞察：拉未忽略的问题、按严重度分组（严重 > 中等 > 低）、按需扫描、逐条忽略。
//

import Foundation
import Observation

@Observable
@MainActor
final class SecurityInsightsViewModel {

    /// 按严重度分好的一组
    struct SeverityGroup: Identifiable {
        let severity: SecurityInsightSeverity
        let issues: [SecurityInsight]
        var id: String { severity.label }
    }

    private(set) var issues: [SecurityInsight] = []
    private(set) var loaded = false
    var isLoading = false
    var isScanning = false
    /// 正在忽略的问题 id（行内转圈）
    private(set) var dismissingId: String?
    var error: String?
    var didStartScan = false   // 「已发起扫描」提示 / sensoryFeedback 触发器
    var didDismiss = false     // sensoryFeedback 触发器

    private let service: SecurityInsightService
    private let zoneId: String

    init(service: SecurityInsightService, zoneId: String) {
        self.service = service
        self.zoneId = zoneId
    }

    /// 严重度分组，组内按发现时间新→旧
    var groups: [SeverityGroup] {
        Dictionary(grouping: issues, by: \.severityLevel)
            .sorted { $0.key < $1.key }
            .map { severity, items in
                SeverityGroup(
                    severity: severity,
                    issues: items.sorted { ($0.sinceDate ?? .distantPast) > ($1.sinceDate ?? .distantPast) }
                )
            }
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            // 服务端已按 dismissed=false 过滤；已解决（status=resolved）的保留，行内标注
            issues = try await service.insights(zoneId: zoneId)
            loaded = true
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
        isLoading = false
    }

    /// 按需扫描。账户级每 24 小时最多 5 次，超限时把 CF 的错误信息原样给用户。
    func startScan() async {
        guard !isScanning else { return }
        isScanning = true
        error = nil
        do {
            try await service.startScan(zoneId: zoneId)
            didStartScan.toggle()
        } catch {
            self.error = error.localizedDescription
        }
        isScanning = false
    }

    func dismiss(_ issue: SecurityInsight) async {
        guard dismissingId == nil else { return }
        dismissingId = issue.id
        error = nil
        do {
            try await service.dismiss(zoneId: zoneId, issueId: issue.id)
            issues.removeAll { $0.id == issue.id }
            didDismiss.toggle()
        } catch {
            self.error = error.localizedDescription
        }
        dismissingId = nil
    }
}
