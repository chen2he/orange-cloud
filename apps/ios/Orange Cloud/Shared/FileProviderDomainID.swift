//
//  FileProviderDomainID.swift
//  Orange Cloud — Shared（主 App + FileProvider extension 双 target 编译）
//
//  NSFileProviderDomain 的 identifier 编码方案：把「登录身份 / 账号 / 桶名」三段塞进
//  domain identifier，extension 拿到 domain 即可还原出凭证来源（按 sessionId 从共享
//  Keychain 读 token）与 R2 目标（accountId + bucketName）。无需额外 App Group 配置表。
//
//  区域限制桶（EU / US / FedRAMP）追加第四段辖区：`sessionId|accountId|bucket|eu`。
//  默认辖区仍是三段——已挂载的老 domain 标识不变，照常解析为默认辖区。
//  extension（Orange Cloud File）不编译 Shared，FileProviderExtension.parseDomain 与此处须同口径。
//
//  分隔符用 "|"：R2 桶名仅允许小写字母/数字/连字符，accountId 是十六进制，sessionId 是
//  UUID，辖区是小写字母/连字符，都不含 "|"，不会冲突。
//

import Foundation

nonisolated enum FileProviderDomainID {

    private static let separator: Character = "|"

    /// 组装 domain identifier 字符串。jurisdiction 为空 / default 时保持三段老格式。
    static func make(sessionId: UUID, accountId: String, bucketName: String, jurisdiction: String? = nil) -> String {
        let base = "\(sessionId.uuidString)\(separator)\(accountId)\(separator)\(bucketName)"
        guard let value = normalizedJurisdiction(jurisdiction) else { return base }
        return "\(base)\(separator)\(value)"
    }

    /// 解析 domain identifier；格式不符返回 nil。三段 = 默认辖区（jurisdiction 为 nil）。
    static func parse(_ identifier: String) -> (sessionId: UUID, accountId: String, bucketName: String, jurisdiction: String?)? {
        let parts = identifier.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 || parts.count == 4,
              let sessionId = UUID(uuidString: parts[0]),
              !parts[1].isEmpty, !parts[2].isEmpty else { return nil }
        let jurisdiction = parts.count == 4 ? normalizedJurisdiction(parts[3]) : nil
        return (sessionId, parts[1], parts[2], jurisdiction)
    }

    /// 空 / default → nil，其余小写
    private static func normalizedJurisdiction(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespaces).lowercased(),
              !value.isEmpty, value != "default" else { return nil }
        return value
    }
}
