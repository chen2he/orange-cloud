//
//  PrecursorModels.swift
//  Orange Cloud
//
//  会话级机器人检测（Precursor）：在整个会话中持续评估访客行为。
//  GET/PUT /zones/{id}/precursor（precursor.read / .write，全套餐）。
//  schema 已把这些字段标为 deprecated 且没给替代——只做 default_mode 选择，
//  enforcement_rules 不碰；PUT 是部分更新，只发 default_mode。
//

import Foundation

nonisolated struct PrecursorConfig: Codable, Sendable {
    /// off | min-friction | max-security（未知取值原样保留）
    let defaultMode: String?

    enum CodingKeys: String, CodingKey {
        case defaultMode = "default_mode"
    }
}

/// PUT 体：只发 default_mode
nonisolated struct PrecursorModeUpdate: Codable, Sendable {
    let defaultMode: String

    enum CodingKeys: String, CodingKey {
        case defaultMode = "default_mode"
    }
}

nonisolated enum PrecursorMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case minFriction = "min-friction"
    case maxSecurity = "max-security"

    var id: String { rawValue }

    var label: String {
        switch self {
        // 独立键：中文「关闭」已有别处译作 Close（动作），作模式名不对
        case .off:         String(localized: "precursor.mode.off", defaultValue: "关闭")
        case .minFriction: String(localized: "低打扰")
        case .maxSecurity: String(localized: "最高安全")
        }
    }

    /// 当前值的展示文案；未知档位原样显示
    static func displayLabel(for raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return PrecursorMode.off.label }
        return PrecursorMode(rawValue: raw)?.label ?? raw
    }
}
