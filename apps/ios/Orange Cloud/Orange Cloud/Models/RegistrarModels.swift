//
//  RegistrarModels.swift
//  Orange Cloud
//
//  Cloudflare Registrar —— 在 Cloudflare 注册的域名：到期日 / 自动续费 / 转移锁。
//
//  ⚠️ 必须用新版 API。旧的 /accounts/{id}/registrar/domains 系列于 2026-06-29 弃用、
//  **2026-09-27 停用**；新版在 /accounts/{id}/registrar/registrations 下。
//
//  两个由接口决定的边界，UI 必须如实反映：
//  · PATCH **只支持 auto_renew**（规范原文：currently supports updating auto_renew only），
//    转移锁 locked 是只读的 —— 不做成开关
//  · PATCH 返回的是**异步 workflow 状态**而非更新后的注册对象，故写入后需回读列表
//

import Foundation

nonisolated struct DomainRegistration: Codable, Identifiable, Hashable, Sendable {
    let domainName:  String
    /// 到期时间。registration_pending 期间可能为 null
    let expiresAt:   String?
    let createdAt:   String?
    /// 自动续费：开启即授权 Cloudflare 在到期前 30 天内扣默认支付方式
    let autoRenew:   Bool?
    /// 是否锁定转移。**只读**，新版 API 不支持经此端点修改
    let locked:      Bool?
    /// false / redaction
    let privacyMode: String?
    /// active / registration_pending / expired / suspended / redemption_period
    let status:      String?

    var id: String { domainName }

    enum CodingKeys: String, CodingKey {
        case locked, status
        case domainName  = "domain_name"
        case expiresAt   = "expires_at"
        case createdAt   = "created_at"
        case autoRenew   = "auto_renew"
        case privacyMode = "privacy_mode"
    }

    var statusText: String {
        switch status {
        case "active":               String(localized: "正常")
        case "registration_pending": String(localized: "注册中")
        case "expired":              String(localized: "已过期")
        case "suspended":            String(localized: "已暂停")
        case "redemption_period":    String(localized: "赎回期")
        default:                     status ?? String(localized: "未知")
        }
    }

    var expiryDate: Date? {
        guard let expiresAt else { return nil }
        return ISO8601DateFormatter.registrarParser.date(from: expiresAt)
    }

    /// 距到期天数；负数表示已过期
    var daysUntilExpiry: Int? {
        guard let expiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day
    }

    /// 30 天内到期且未开自动续费——需要用户尽快处理
    var needsAttention: Bool {
        guard let days = daysUntilExpiry else { return false }
        return days <= 30 && autoRenew != true
    }
}

/// PATCH 体。接口目前只认 auto_renew。
nonisolated struct RegistrationUpdate: Codable, Sendable {
    let autoRenew: Bool

    enum CodingKeys: String, CodingKey {
        case autoRenew = "auto_renew"
    }
}

nonisolated extension ISO8601DateFormatter {
    /// Registrar 的时间戳带小数秒，默认解析器接不住
    static let registrarParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// MARK: - 搜索新域名（domain-search / domain-check）

/// GET /registrar/domain-search 与 POST /registrar/domain-check 的 result（{ domains: [...] }）
nonisolated struct DomainSearchResponse: Codable, Sendable {
    let domains: [DomainAvailability]?
}

/// 单个候选域名。搜索结果可能是缓存（有延迟），domain-check 才是向注册局实时确认。
nonisolated struct DomainAvailability: Codable, Identifiable, Hashable, Sendable {
    let name:        String
    let registrable: Bool?
    /// standard | premium
    let tier:        String?
    /// 不可注册原因（见 DomainUnavailableReason）
    let reason:      String?
    let pricing:     DomainPricing?

    var id: String { name }
    var isRegistrable: Bool { registrable == true }
    var isPremium: Bool { tier == "premium" || reason == "domain_premium" }

    /// 不可注册原因的中文；未知原因原样显示
    var reasonText: String? {
        guard let reason, !reason.isEmpty else { return nil }
        return DomainUnavailableReason(rawValue: reason)?.label ?? reason
    }
}

/// 价格（字符串，保留注册商给的精度）
nonisolated struct DomainPricing: Codable, Hashable, Sendable {
    let currency:         String?
    let registrationCost: String?
    let renewalCost:      String?

    enum CodingKeys: String, CodingKey {
        case currency
        case registrationCost = "registration_cost"
        case renewalCost      = "renewal_cost"
    }
}

nonisolated enum DomainUnavailableReason: String, Sendable {
    case extensionNotSupportedViaAPI   = "extension_not_supported_via_api"
    case extensionNotSupported         = "extension_not_supported"
    case extensionDisallowsRegistration = "extension_disallows_registration"
    case domainPremium                 = "domain_premium"
    case domainUnavailable             = "domain_unavailable"

    var label: String {
        switch self {
        case .extensionNotSupportedViaAPI:    String(localized: "该后缀暂不支持通过 API 注册")
        case .extensionNotSupported:          String(localized: "Cloudflare 不支持该后缀")
        case .extensionDisallowsRegistration: String(localized: "该后缀不开放注册")
        case .domainPremium:                  String(localized: "溢价域名")
        case .domainUnavailable:              String(localized: "已被注册")
        }
    }
}

/// POST domain-check 请求体（≤ 20 个）
nonisolated struct DomainCheckRequest: Codable, Sendable {
    let domains: [String]
}
