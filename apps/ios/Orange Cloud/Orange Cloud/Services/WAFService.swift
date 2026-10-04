//
//  WAFService.swift
//  Orange Cloud
//
//  WAF 自定义规则：读 entrypoint ruleset；新建 / 编辑 / 删除 / 启停单条规则。
//

import Foundation

struct WAFService {

    private let client: CFAPIClient

    init(client: CFAPIClient) {
        self.client = client
    }

    /// 自定义防火墙规则的 entrypoint ruleset。Zone 还没建过自定义规则时返回 nil。
    /// 注意：该 404 带错误信封（"could not find entrypoint ruleset..."），
    /// 会被 CFAPIClient 解析为 cloudflareError 而非 notFound，两种都要接住。
    func customRuleset(zoneId: String) async throws -> WAFRuleset? {
        do {
            let response: CFAPIResponse<WAFRuleset> = try await client.get(
                "zones/\(zoneId)/rulesets/phases/http_request_firewall_custom/entrypoint"
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

    /// 启停规则，返回更新后的整个 ruleset
    func setRuleEnabled(
        zoneId: String,
        rulesetId: String,
        ruleId: String,
        enabled: Bool
    ) async throws -> WAFRuleset {
        let response: CFAPIResponse<WAFRuleset> = try await client.patch(
            "zones/\(zoneId)/rulesets/\(rulesetId)/rules/\(ruleId)",
            body: WAFRuleToggle(enabled: enabled)
        )
        guard response.success, let ruleset = response.result else {
            throw response.toAPIError()
        }
        return ruleset
    }

    /// 整条更新规则（动作 / 表达式 / 名称 / 启用），返回更新后的 ruleset
    func updateRule(
        zoneId: String,
        rulesetId: String,
        ruleId: String,
        rule: WAFRuleCreate
    ) async throws -> WAFRuleset {
        let response: CFAPIResponse<WAFRuleset> = try await client.patch(
            "zones/\(zoneId)/rulesets/\(rulesetId)/rules/\(ruleId)",
            body: rule
        )
        guard response.success, let ruleset = response.result else {
            throw response.toAPIError()
        }
        return ruleset
    }

    /// 向已有规则集追加规则，返回更新后的 ruleset
    func addRule(zoneId: String, rulesetId: String, rule: WAFRuleCreate) async throws -> WAFRuleset {
        let response: CFAPIResponse<WAFRuleset> = try await client.post(
            "zones/\(zoneId)/rulesets/\(rulesetId)/rules",
            body: rule
        )
        guard response.success, let ruleset = response.result else {
            throw response.toAPIError()
        }
        return ruleset
    }

    /// Zone 还没有自定义规则集时，用首条规则创建 entrypoint
    func createRuleset(zoneId: String, rule: WAFRuleCreate) async throws -> WAFRuleset {
        let response: CFAPIResponse<WAFRuleset> = try await client.put(
            "zones/\(zoneId)/rulesets/phases/http_request_firewall_custom/entrypoint",
            body: WAFEntrypointUpdate(rules: [rule])
        )
        guard response.success, let ruleset = response.result else {
            throw response.toAPIError()
        }
        return ruleset
    }

    /// 只校验不保存（?dry_run=true）：发与保存完全相同的请求——编辑走 PATCH 规则、
    /// 已有规则集走 POST 追加、还没有规则集走 PUT entrypoint。成功时 result 为 null，
    /// 失败原样抛 CF 的校验错误。
    func validateRule(zoneId: String, rulesetId: String?, ruleId: String?, rule: WAFRuleCreate) async throws {
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
                "zones/\(zoneId)/rulesets/phases/http_request_firewall_custom/entrypoint",
                body: WAFEntrypointUpdate(rules: [rule]),
                queryItems: dryRun
            )
        }
        guard response.success else {
            throw response.toAPIError()
        }
    }

    /// 删除规则（响应即更新后的 ruleset，但统一由调用方重新加载）
    func deleteRule(zoneId: String, rulesetId: String, ruleId: String) async throws {
        try await client.delete("zones/\(zoneId)/rulesets/\(rulesetId)/rules/\(ruleId)")
    }
}
