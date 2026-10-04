package jiamin.chen.orangecloud.data.repository

import jiamin.chen.orangecloud.core.network.ApiError
import jiamin.chen.orangecloud.core.network.CfApiClient
import jiamin.chen.orangecloud.data.model.CreateTunnelRequest
import jiamin.chen.orangecloud.data.model.Tunnel
import jiamin.chen.orangecloud.data.model.TunnelClient
import jiamin.chen.orangecloud.data.model.TunnelConfig
import jiamin.chen.orangecloud.data.model.TunnelConfigResult
import jiamin.chen.orangecloud.data.model.TunnelConfigUpdate
import jiamin.chen.orangecloud.data.model.TunnelConnection
import jiamin.chen.orangecloud.data.model.flattenedConnections
import jiamin.chen.orangecloud.data.model.WafEntrypointUpdate
import jiamin.chen.orangecloud.data.model.WafRule
import jiamin.chen.orangecloud.data.model.WafRuleCreate
import jiamin.chen.orangecloud.data.model.WafRuleToggle
import jiamin.chen.orangecloud.data.model.WafRuleset
import javax.inject.Inject
import javax.inject.Singleton

/**
 * WAF 自定义规则 + Cloudflare Tunnel（对应 iOS WAFService / TunnelService）。
 */
@Singleton
class SecurityRepository @Inject constructor(
    private val api: CfApiClient,
) {
    /** 自定义防火墙规则 entrypoint ruleset；Zone 未建过自定义规则时返回 null（404/业务错误均接住）。 */
    suspend fun customRuleset(zoneId: String): WafRuleset? = try {
        api.get<WafRuleset>("zones/$zoneId/rulesets/phases/http_request_firewall_custom/entrypoint")
    } catch (e: ApiError.Http) {
        if (e.status == 404) null else throw e
    } catch (e: ApiError.Cloudflare) {
        if (e.errors.any { it.message.contains("could not find entrypoint", ignoreCase = true) }) null else throw e
    }

    /** 启停单条规则，返回更新后的整个 ruleset。 */
    suspend fun setRuleEnabled(zoneId: String, rulesetId: String, rule: WafRule, enabled: Boolean): WafRuleset =
        api.patch("zones/$zoneId/rulesets/$rulesetId/rules/${rule.id}", WafRuleToggle(enabled))

    /** 整条更新规则（动作 / 表达式 / 名称 / 启用），返回更新后的 ruleset。 */
    suspend fun updateRule(zoneId: String, rulesetId: String, ruleId: String, rule: WafRuleCreate): WafRuleset =
        api.patch("zones/$zoneId/rulesets/$rulesetId/rules/$ruleId", rule)

    /** 向已有规则集追加规则，返回更新后的 ruleset。 */
    suspend fun addRule(zoneId: String, rulesetId: String, rule: WafRuleCreate): WafRuleset =
        api.post("zones/$zoneId/rulesets/$rulesetId/rules", rule)

    /** Zone 还没有自定义规则集时，用首条规则创建 entrypoint。 */
    suspend fun createRuleset(zoneId: String, rule: WafRuleCreate): WafRuleset =
        api.put("zones/$zoneId/rulesets/phases/http_request_firewall_custom/entrypoint", WafEntrypointUpdate(listOf(rule)))

    /**
     * 校验（?dry_run=true）：与保存完全相同的请求，只校验不落盘，通过时 result 为 null。
     * ruleId 非空 → PATCH；rulesetId 非空 → POST 追加；都为空 → PUT entrypoint 建集。
     */
    suspend fun validateRule(zoneId: String, rulesetId: String?, ruleId: String?, rule: WafRuleCreate) {
        val dryRun = listOf("dry_run" to "true")
        when {
            ruleId != null && rulesetId != null ->
                api.sendChecked("PATCH", "zones/$zoneId/rulesets/$rulesetId/rules/$ruleId", rule, dryRun)
            rulesetId != null ->
                api.sendChecked("POST", "zones/$zoneId/rulesets/$rulesetId/rules", rule, dryRun)
            else -> api.sendChecked(
                "PUT",
                "zones/$zoneId/rulesets/phases/http_request_firewall_custom/entrypoint",
                WafEntrypointUpdate(listOf(rule)),
                dryRun,
            )
        }
    }

    /** 删除规则。 */
    suspend fun deleteRule(zoneId: String, rulesetId: String, ruleId: String) =
        api.delete("zones/$zoneId/rulesets/$rulesetId/rules/$ruleId")

    /** 账号下全部 Tunnel（排除已删除，页码分页）。 */
    suspend fun listTunnels(accountId: String): List<Tunnel> {
        val all = mutableListOf<Tunnel>()
        var page = 1
        while (true) {
            val paged = api.getList<Tunnel>(
                "accounts/$accountId/cfd_tunnel",
                listOf("is_deleted" to "false", "page" to page.toString(), "per_page" to "100"),
            )
            all += paged.items
            if (page >= (paged.info?.totalPages ?: 1)) break
            page++
        }
        return all
    }

    /**
     * 单条隧道详情。列表与详情共用同一结构。
     *
     * 注意：cfd_tunnel 对象曾内嵌 connections（扁平形态），CF 将于 **2026-10-05** 移除该字段，
     * 活跃连接改由 [tunnelConnections] 的专用端点提供，勿再依赖内嵌数组。
     */
    suspend fun getTunnel(accountId: String, tunnelId: String): Tunnel =
        api.get("accounts/$accountId/cfd_tunnel/$tunnelId")

    /**
     * 隧道的活跃连接（专用端点）。
     *
     * result 是 Client 数组（一个 cloudflared 进程一项），此处摊平为连接列表供 UI 直接消费。
     */
    suspend fun tunnelConnections(accountId: String, tunnelId: String): List<TunnelConnection> =
        api.getList<TunnelClient>("accounts/$accountId/cfd_tunnel/$tunnelId/connections")
            .items
            .flattenedConnections()

    // MARK: - 隧道生命周期（argotunnel.write）

    /** 新建远程托管隧道（config_src=cloudflare）。 */
    suspend fun createTunnel(accountId: String, name: String): Tunnel =
        api.post("accounts/$accountId/cfd_tunnel", CreateTunnelRequest(name))

    /** 隧道连接令牌（result 是裸 base64 字符串），用于 `cloudflared tunnel run --token`。 */
    suspend fun tunnelToken(accountId: String, tunnelId: String): String =
        api.get("accounts/$accountId/cfd_tunnel/$tunnelId/token")

    /** 清理失活连接（删除隧道前先调用；活跃的 cloudflared 仍会重连）。 */
    suspend fun deleteConnections(accountId: String, tunnelId: String) =
        api.delete("accounts/$accountId/cfd_tunnel/$tunnelId/connections")

    /** 删除隧道：先清理连接再删；若仍有活跃连接，CF 业务错误原样透出。 */
    suspend fun deleteTunnel(accountId: String, tunnelId: String) {
        runCatching { deleteConnections(accountId, tunnelId) }
        api.delete("accounts/$accountId/cfd_tunnel/$tunnelId")
    }

    // MARK: - 配置（公共主机名 / ingress，仅远程托管）

    /** 读隧道配置。新建后尚无配置时返回 null（404 或 config 为空均按「无配置」处理）。 */
    suspend fun configuration(accountId: String, tunnelId: String): TunnelConfig? = try {
        api.get<TunnelConfigResult>("accounts/$accountId/cfd_tunnel/$tunnelId/configurations").config
    } catch (e: ApiError.Http) {
        if (e.status == 404) null else throw e
    }

    /** 整组回写配置（catch-all 守在末尾由调用方保证），返回更新后的配置。 */
    suspend fun updateConfiguration(accountId: String, tunnelId: String, config: TunnelConfig): TunnelConfig {
        val result = api.put<TunnelConfigResult, TunnelConfigUpdate>(
            "accounts/$accountId/cfd_tunnel/$tunnelId/configurations",
            TunnelConfigUpdate(config),
        )
        return result.config ?: config
    }
}
