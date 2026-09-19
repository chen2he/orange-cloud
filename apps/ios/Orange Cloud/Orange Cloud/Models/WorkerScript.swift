//
//  WorkerScript.swift
//  Orange Cloud
//
//  Workers 脚本模型。GET /accounts/{account_id}/workers/scripts
//

import Foundation

nonisolated struct WorkerScript: Codable, Identifiable, Hashable, Sendable {
    let id:         String        // 即脚本名，账号内唯一
    let etag:       String?
    let createdOn:  String?
    let modifiedOn: String?
    let usageModel: String?
    let handlers:   [String]?     // ["fetch", "scheduled"] 等
    let logpush:    Bool?

    enum CodingKeys: String, CodingKey {
        case id, etag, handlers, logpush
        case createdOn  = "created_on"
        case modifiedOn = "modified_on"
        case usageModel = "usage_model"
    }
}

extension WorkerScript {

    /// CF 返回 6 位小数的 ISO8601（如 2026-03-22T20:05:13.916883Z）
    nonisolated static func parseDate(_ string: String?) -> Date? {
        ISO8601Parse.date(string)
    }

    var modifiedDate: Date? { Self.parseDate(modifiedOn) }
    var createdDate:  Date? { Self.parseDate(createdOn) }
}
