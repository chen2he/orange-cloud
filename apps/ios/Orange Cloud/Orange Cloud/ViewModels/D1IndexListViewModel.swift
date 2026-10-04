//
//  D1IndexListViewModel.swift
//  Orange Cloud
//
//  D1 表结构补充：PRAGMA index_list(<table>) 读索引清单（只读，d1.read 即可）。
//  表名走标识符转义（双引号包裹 + 内部双引号加倍），不接受任意拼接。
//

import Foundation
import Observation

/// PRAGMA index_list 的一行
nonisolated struct D1IndexInfo: Identifiable, Sendable {
    let name:     String
    let isUnique: Bool
    /// c = CREATE INDEX 建的；u = UNIQUE 约束隐式建的；pk = 主键隐式建的
    let origin:   String

    var id: String { name }

    var originLabel: String {
        switch origin {
        case "pk": String(localized: "主键")
        case "u":  String(localized: "唯一约束")
        case "c":  String(localized: "手动创建")
        default:   origin
        }
    }
}

@Observable
@MainActor
final class D1IndexListViewModel {

    private(set) var indexes: [D1IndexInfo] = []
    private(set) var loaded = false
    var error: String?

    private let service: D1Service
    private let accountId: String
    private let databaseId: String
    private let tableName: String

    init(service: D1Service, accountId: String, databaseId: String, tableName: String) {
        self.service = service
        self.accountId = accountId
        self.databaseId = databaseId
        self.tableName = tableName
    }

    /// 标识符加引号并转义内部双引号，防注入（对齐 D1TableViewModel.quoted）
    private var quotedTable: String {
        "\"" + tableName.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    func load() async {
        guard !loaded else { return }
        do {
            let results = try await service.query(
                accountId: accountId, databaseId: databaseId,
                sql: "PRAGMA index_list(\(quotedTable))"
            )
            indexes = (results.first?.results ?? []).compactMap { row in
                guard case .string(let name) = row["name"] else { return nil }
                let unique = (row["unique"]?.displayText ?? "0") != "0"
                let origin = row["origin"]?.displayText ?? ""
                return D1IndexInfo(name: name, isUnique: unique, origin: origin)
            }
            loaded = true
        } catch {
            // 索引卡是补充信息，失败不打断表浏览，只在卡里提示
            self.error = D1FreeTierLimit.message(for: error)
            loaded = true
        }
    }
}
