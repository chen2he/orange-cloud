//
//  DNSRecord.swift
//  Orange Cloud
//

import Foundation

nonisolated struct DNSRecord: Codable, Identifiable, Hashable, Sendable {
    let id:        String
    let type:      String          // A, AAAA, CNAME, TXT, MX 等
    let name:      String
    let content:   String
    let proxied:   Bool?
    let ttl:       Int
    let priority:  Int?            // MX / SRV 记录需要
    let comment:   String?
    let createdOn: String?
    /// 列表带 include_shadow_metadata=true 时才有（遮蔽信息）
    let meta:      DNSRecordMeta?

    enum CodingKeys: String, CodingKey {
        case id, type, name, content, proxied, ttl, priority, comment, meta
        case createdOn = "created_on"
    }

    var isProxied: Bool { proxied ?? false }

    /// 该名称已被 NS 委派给别的名称服务器，Cloudflare 不会响应这条记录
    var isShadowed: Bool { !(meta?.shadowedBy ?? []).isEmpty }
    /// NS 委派记录遮蔽了多少条记录
    var shadowedRecordsCount: Int { meta?.shadowedRecordsCount ?? 0 }
}

/// dns_records 的 meta（2026 起 include_shadow_metadata=true 时附带遮蔽信息）。
/// meta 里还有 auto_added 等别的字段，这里只取两项且宽容解码，形态不符不拖垮整条记录。
nonisolated struct DNSRecordMeta: Codable, Hashable, Sendable {
    /// 遮蔽本记录的 NS 记录 id
    let shadowedBy: [String]?
    /// NS 委派记录上：被它遮蔽的记录数
    let shadowedRecordsCount: Int?

    enum CodingKeys: String, CodingKey {
        case shadowedBy = "shadowed_by"
        case shadowedRecordsCount = "shadowed_records_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shadowedBy = try? c.decodeIfPresent([String].self, forKey: .shadowedBy)
        shadowedRecordsCount = try? c.decodeIfPresent(Int.self, forKey: .shadowedRecordsCount)
    }
}

nonisolated struct CreateDNSRecord: Codable, Sendable {
    let type:     String
    let name:     String
    let content:  String
    let proxied:  Bool
    let ttl:      Int
    let priority: Int?             // 仅 MX / SRV，其他类型传 nil（不编码）
    let comment:  String?
}
