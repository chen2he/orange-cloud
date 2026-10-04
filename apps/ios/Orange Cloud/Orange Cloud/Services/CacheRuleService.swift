//
//  CacheRuleService.swift
//  Orange Cloud
//
//  Cache Rules CRUD（Rulesets entrypoint，phase http_request_cache_settings）。
//  读 cache-settings.read，写 cache-settings.write。
//  与 WAF/Transform 同样容错：zone 还没建过缓存规则时 entrypoint 返回 404/错误信封，视为 nil。
//

import Foundation

struct CacheRuleService {

    private let client: CFAPIClient
    private let phase = "http_request_cache_settings"

    init(client: CFAPIClient) {
        self.client = client
    }

    /// 缓存规则的 entrypoint ruleset；zone 还没有缓存规则时返回 nil
    func ruleset(zoneId: String) async throws -> CacheRuleset? {
        do {
            let response: CFAPIResponse<CacheRuleset> = try await client.get(
                "zones/\(zoneId)/rulesets/phases/\(phase)/entrypoint"
            )
            guard response.success, let ruleset = response.result else {
                throw response.toAPIError()
            }
            return ruleset
        } catch APIError.notFound {
            return nil
        } catch let APIError.cloudflareError(code, message, docURL) {
            if message.localizedCaseInsensitiveContains("could not find entrypoint") {
                return nil
            }
            throw APIError.cloudflareError(code: code, message: message, documentationURL: docURL)
        }
    }

    /// 启停单条规则（PATCH 只更 enabled），返回更新后的整个 ruleset
    func setRuleEnabled(zoneId: String, rulesetId: String, ruleId: String, enabled: Bool) async throws -> CacheRuleset {
        let response: CFAPIResponse<CacheRuleset> = try await client.patch(
            "zones/\(zoneId)/rulesets/\(rulesetId)/rules/\(ruleId)",
            body: CacheRuleToggle(enabled: enabled)
        )
        guard response.success, let ruleset = response.result else {
            throw response.toAPIError()
        }
        return ruleset
    }

    /// 向已有规则集追加规则
    func addRule(zoneId: String, rulesetId: String, rule: CacheRuleCreate) async throws -> CacheRuleset {
        let response: CFAPIResponse<CacheRuleset> = try await client.post(
            "zones/\(zoneId)/rulesets/\(rulesetId)/rules",
            body: rule
        )
        guard response.success, let ruleset = response.result else {
            throw response.toAPIError()
        }
        return ruleset
    }

    /// 更新单条规则（PATCH，覆盖该规则的字段）
    func updateRule(zoneId: String, rulesetId: String, ruleId: String, rule: CacheRuleCreate) async throws -> CacheRuleset {
        let response: CFAPIResponse<CacheRuleset> = try await client.patch(
            "zones/\(zoneId)/rulesets/\(rulesetId)/rules/\(ruleId)",
            body: rule
        )
        guard response.success, let ruleset = response.result else {
            throw response.toAPIError()
        }
        return ruleset
    }

    /// zone 还没有缓存规则集时，用首条规则创建 entrypoint
    func createEntrypoint(zoneId: String, rule: CacheRuleCreate) async throws -> CacheRuleset {
        let response: CFAPIResponse<CacheRuleset> = try await client.put(
            "zones/\(zoneId)/rulesets/phases/\(phase)/entrypoint",
            body: CacheEntrypointUpdate(rules: [rule])
        )
        guard response.success, let ruleset = response.result else {
            throw response.toAPIError()
        }
        return ruleset
    }

    /// 只校验不保存（?dry_run=true）：与保存同一个请求（PATCH 规则 / POST 追加 / PUT entrypoint），
    /// 成功时 result 为 null，失败原样抛 CF 的校验错误。
    func validateRule(zoneId: String, rulesetId: String?, ruleId: String?, rule: CacheRuleCreate) async throws {
        let dryRun = [URLQueryItem(name: "dry_run", value: "true")]
        let response: CFAPIResponse<JSONValue>
        if let rulesetId, let ruleId {
            response = try await client.patch(
                "zones/\(zoneId)/rulesets/\(rulesetId)/rules/\(ruleId)", body: rule, queryItems: dryRun
            )
        } else if let rulesetId {
            response = try await client.post(
                "zones/\(zoneId)/rulesets/\(rulesetId)/rules", body: rule, queryItems: dryRun
            )
        } else {
            response = try await client.put(
                "zones/\(zoneId)/rulesets/phases/\(phase)/entrypoint",
                body: CacheEntrypointUpdate(rules: [rule]),
                queryItems: dryRun
            )
        }
        guard response.success else {
            throw response.toAPIError()
        }
    }

    /// 删除规则
    func deleteRule(zoneId: String, rulesetId: String, ruleId: String) async throws {
        try await client.delete("zones/\(zoneId)/rulesets/\(rulesetId)/rules/\(ruleId)")
    }
}
