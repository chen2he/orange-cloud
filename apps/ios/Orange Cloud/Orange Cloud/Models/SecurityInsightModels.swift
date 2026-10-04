//
//  SecurityInsightModels.swift
//  Orange Cloud
//
//  安全洞察（Security Center Insights）：zone 级的安全配置问题清单。
//  GET  /zones/{id}/security-center/insights?dismissed=false&page=&per_page=
//  POST /zones/{id}/security-center/insights/scans        （按需扫描，账户级共享 5 次 / 24h）
//  PUT  /zones/{id}/security-center/insights/{issue}/dismiss
//
//  全套餐可用；权限 Zone Settings Read / Write（zone-settings.read / .write）。
//  枚举字段（issue_type / severity / status）一律按字符串解码：CF 日后加类型不至于整页解码失败，
//  未知取值原样展示。注意 severity 在响应里是首字母大写（Low / Moderate / Critical）。
//

import Foundation

/// GET insights 的 result（对象型，问题列表在 issues 里）
nonisolated struct SecurityInsightPage: Codable, Sendable {
    let count:   Int?
    let page:    Int?
    let perPage: Int?
    let issues:  [SecurityInsight]?

    enum CodingKeys: String, CodingKey {
        case count, page, issues
        case perPage = "per_page"
    }
}

nonisolated struct SecurityInsight: Codable, Identifiable, Hashable, Sendable {
    let id:          String
    let issueType:   String?
    let issueClass:  String?
    let severity:    String?
    let subject:     String?
    let since:       String?
    let timestamp:   String?
    let status:      String?
    let dismissed:   Bool?
    let resolveLink: String?
    let resolveText: String?

    enum CodingKeys: String, CodingKey {
        case id, severity, subject, since, timestamp, status, dismissed
        case issueType   = "issue_type"
        case issueClass  = "issue_class"
        case resolveLink = "resolve_link"
        case resolveText = "resolve_text"
    }

    /// 严重度分组键（小写归一；响应是首字母大写）
    var severityLevel: SecurityInsightSeverity {
        SecurityInsightSeverity(apiValue: severity)
    }

    /// 类型标签：已知类型给中文名，未知类型退回 issue_type / issue_class 原文
    var typeLabel: String {
        SecurityInsightType(rawValue: issueType ?? "")?.label
            ?? issueType ?? issueClass ?? String(localized: "安全洞察")
    }

    var sinceDate: Date? { ISO8601Parse.date(since) }

    var isResolved: Bool { status?.lowercased() == "resolved" }

    /// 「去处理」链接：相对路径（以 / 开头）补全到 dash.cloudflare.com；只放行 http(s)
    var resolveURL: URL? {
        guard let raw = resolveLink?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let absolute = raw.hasPrefix("/") ? "https://dash.cloudflare.com" + raw : raw
        guard let url = URL(string: absolute),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }
}

/// 严重度：严重 > 中等 > 低；未知取值单独成组排最后
nonisolated enum SecurityInsightSeverity: Hashable, Comparable, Sendable {
    case critical, moderate, low
    case other(String)

    init(apiValue: String?) {
        switch apiValue?.lowercased() {
        case "critical": self = .critical
        case "moderate": self = .moderate
        case "low":      self = .low
        default:         self = .other(apiValue ?? "")
        }
    }

    /// 独立键：「严重」等中文键已被状态页（事故等级 Major）占用，共用会让英文显示成 Major
    var label: String {
        switch self {
        case .critical:        String(localized: "security_insight.severity.critical", defaultValue: "严重")
        case .moderate:        String(localized: "security_insight.severity.moderate", defaultValue: "中等")
        case .low:             String(localized: "security_insight.severity.low", defaultValue: "低")
        case .other(let raw):  raw.isEmpty ? String(localized: "其他") : raw
        }
    }

    private var rank: Int {
        switch self {
        case .critical: 0
        case .moderate: 1
        case .low:      2
        case .other:    3
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// issue_type 已知取值
nonisolated enum SecurityInsightType: String, Sendable {
    case complianceViolation    = "compliance_violation"
    case emailSecurity          = "email_security"
    case exposedInfrastructure  = "exposed_infrastructure"
    case insecureConfiguration  = "insecure_configuration"
    case weakAuthentication     = "weak_authentication"
    case configurationSuggestion = "configuration_suggestion"

    var label: String {
        switch self {
        case .complianceViolation:     String(localized: "合规问题")
        case .emailSecurity:           String(localized: "邮件安全")
        case .exposedInfrastructure:   String(localized: "暴露的基础设施")
        case .insecureConfiguration:   String(localized: "不安全的配置")
        case .weakAuthentication:      String(localized: "弱身份验证")
        case .configurationSuggestion: String(localized: "配置建议")
        }
    }
}

/// POST scans 的请求体：空对象 = 扫描全部（result 为 {scan_id}，App 不需要它）
nonisolated struct SecurityInsightScanRequest: Codable, Sendable {}

/// PUT dismiss 的请求体
nonisolated struct SecurityInsightDismissRequest: Codable, Sendable {
    let dismiss: Bool
}
