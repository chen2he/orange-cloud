//
//  FileProviderMountManager.swift
//  Orange Cloud
//
//  主 App 侧：把某个 R2 桶注册为系统「文件」App 里的一个 NSFileProviderDomain
//  （挂载 / 卸载 / 查询是否已挂载）。真正的读写由 OrangeCloudFileProvider extension 承担。
//  domain identifier 用 [[FileProviderDomainID]] 编码，extension 据此还原凭证与 R2 目标。
//  区域限制桶的辖区（eu / us / fedramp…）也编进 identifier，extension 每个请求据此带
//  cf-r2-jurisdiction 头；同名桶在不同辖区是两个 domain。
//
//  仅在工程已包含 File Provider extension target 时生效；该框架对主 App 可用。
//

import Foundation
import FileProvider

@MainActor
enum FileProviderMountManager {

    /// 当前账号 + 桶是否已在「文件」中挂载
    static func isMounted(sessionId: UUID, accountId: String, bucketName: String, jurisdiction: String?) async -> Bool {
        let target = FileProviderDomainID.make(
            sessionId: sessionId, accountId: accountId, bucketName: bucketName, jurisdiction: jurisdiction
        )
        let domains = (try? await allDomains()) ?? []
        return domains.contains { $0.identifier.rawValue == target }
    }

    /// 挂载：新增一个 domain（已存在则幂等返回）。
    /// 不变式：同一 (account, bucket, 辖区) 在「文件」里只允许一个 domain。挂载前先清掉任何旧身份
    /// 残留的同桶 domain（sessionId 不同但 account+bucket 相同）——否则会在侧边栏出现同名、
    /// App 又触达不到的重复挂载目录（重装后 sessionId 重置 + 系统保留旧 domain 的典型表现）。
    static func mount(sessionId: UUID, accountId: String, bucketName: String, jurisdiction: String?) async throws {
        let id = FileProviderDomainID.make(
            sessionId: sessionId, accountId: accountId, bucketName: bucketName, jurisdiction: jurisdiction
        )
        let domains = (try? await allDomains()) ?? []
        let wantedJurisdiction = FileProviderDomainID.parse(id)?.jurisdiction

        for existing in domains {
            guard existing.identifier.rawValue != id,
                  let parsed = FileProviderDomainID.parse(existing.identifier.rawValue),
                  parsed.accountId == accountId, parsed.bucketName == bucketName,
                  parsed.jurisdiction == wantedJurisdiction else { continue }
            try? await remove(existing)   // 清掉同桶的孤儿 domain，best-effort
        }

        if domains.contains(where: { $0.identifier.rawValue == id }) { return }   // 已挂载，幂等
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: id),
            // 区域限制桶在侧边栏标出辖区，免得与同名的默认辖区桶分不清
            displayName: wantedJurisdiction.map { "\(bucketName) (\($0.uppercased()))" } ?? bucketName
        )
        try await add(domain)
    }

    /// 卸载：移除该 domain（连同系统侧已下载的副本）
    static func unmount(sessionId: UUID, accountId: String, bucketName: String, jurisdiction: String?) async throws {
        let id = FileProviderDomainID.make(
            sessionId: sessionId, accountId: accountId, bucketName: bucketName, jurisdiction: jurisdiction
        )
        let domains = try await allDomains()
        guard let domain = domains.first(where: { $0.identifier.rawValue == id }) else { return }
        try await remove(domain)
    }

    /// 启动自愈：移除「文件」里所有不属于当前存活登录身份的挂载 domain。
    /// domain identifier 编码了 sessionId，而 sessionId 存在 UserDefaults——卸载即清空、重装重置，
    /// 但系统会保留（甚至在重装后复活）旧的 domain 注册。这些旧 domain 的 sessionId 已不在存活集合里，
    /// App 的挂载/卸载只认当前身份，永远触达不到它们 → 侧边栏同名重复且删不掉、每重装一次多一个。
    /// 这里按存活 sessionId 把这类孤儿一并清掉（无法解析的历史 domain 也清）。登出态（空集合）下
    /// 不存在合法挂载，会清掉全部残留 domain，符合预期。
    static func reconcile(liveSessionIds: Set<String>) async {
        let domains = (try? await allDomains()) ?? []
        for domain in domains {
            if let parsed = FileProviderDomainID.parse(domain.identifier.rawValue),
               liveSessionIds.contains(parsed.sessionId.uuidString) {
                continue   // 属于当前存活身份的合法挂载，保留
            }
            try? await remove(domain)
        }
    }

    // MARK: - NSFileProviderManager 封装

    private static func add(_ domain: NSFileProviderDomain) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            NSFileProviderManager.add(domain) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    private static func remove(_ domain: NSFileProviderDomain) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            NSFileProviderManager.remove(domain) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    private static func allDomains() async throws -> [NSFileProviderDomain] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[NSFileProviderDomain], Error>) in
            NSFileProviderManager.getDomainsWithCompletionHandler { domains, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: domains) }
            }
        }
    }
}
