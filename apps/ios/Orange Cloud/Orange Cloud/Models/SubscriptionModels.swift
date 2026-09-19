//
//  SubscriptionModels.swift
//  Orange Cloud
//
//  账号订阅（GET /accounts/{id}/subscriptions）。
//  注意：该端点需要 Billing 权限，而 Cloudflare OAuth scope 目录没有开放 billing，
//  正常情况下会 403——调用方按 best-effort 处理，失败回退本地套餐预设。
//

import Foundation

nonisolated struct AccountSubscription: Codable, Sendable {
    let id:                 String?
    let state:              String?      // "Trial" | "Provisioned" | "Paid" | "AwaitingPayment" | "Cancelled" | "Failed" | "Expired"
    let frequency:          String?      // "monthly" | "yearly" ...
    let currentPeriodStart: String?
    let currentPeriodEnd:   String?
    let ratePlan:           SubscriptionRatePlan?

    enum CodingKeys: String, CodingKey {
        case id, state, frequency
        case currentPeriodStart = "current_period_start"
        case currentPeriodEnd   = "current_period_end"
        case ratePlan           = "rate_plan"
    }

    var isActive: Bool {
        switch state?.lowercased() {
        case "cancelled", "expired", "failed": false
        default: true
        }
    }
}

nonisolated struct SubscriptionRatePlan: Codable, Sendable {
    let id:         String?
    let publicName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case publicName = "public_name"
    }
}

// BillingCycle 已移至 Shared/BillingCycle.swift（Widget 自取数需要同一套周期口径）

/// 从订阅列表归纳出的计费信息
nonisolated struct BillingInfo: Sendable {
    let workersPaid: Bool
    let r2Paid:      Bool
    /// Workers 订阅的当前计费周期（用于用量统计窗口）
    let periodStart: Date?
    let periodEnd:   Date?

    static func derive(from subscriptions: [AccountSubscription]) -> BillingInfo {
        let active = subscriptions.filter(\.isActive)

        func matches(_ subscription: AccountSubscription, keyword: String) -> Bool {
            let id = subscription.ratePlan?.id?.lowercased() ?? ""
            let name = subscription.ratePlan?.publicName?.lowercased() ?? ""
            return id.contains(keyword) || name.contains(keyword)
        }

        let workersSub = active.first { matches($0, keyword: "workers") }
        let r2Sub      = active.first { matches($0, keyword: "r2") }

        let formatter = ISO8601Parse.plain
        let periodSource = workersSub ?? r2Sub ?? active.first
        let start = periodSource?.currentPeriodStart.flatMap { formatter.date(from: $0) }
        let end   = periodSource?.currentPeriodEnd.flatMap { formatter.date(from: $0) }

        return BillingInfo(
            workersPaid: workersSub != nil,
            r2Paid:      r2Sub != nil,
            periodStart: start,
            periodEnd:   end
        )
    }
}
