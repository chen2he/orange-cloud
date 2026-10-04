package jiamin.chen.orangecloud.data.repository

import jiamin.chen.orangecloud.core.network.ApiError
import jiamin.chen.orangecloud.core.network.CfApiClient
import jiamin.chen.orangecloud.data.model.CacheEntrypointUpdate
import jiamin.chen.orangecloud.data.model.CacheResponseRuleset
import jiamin.chen.orangecloud.data.model.CacheRuleCreate
import jiamin.chen.orangecloud.data.model.CacheRuleToggle
import jiamin.chen.orangecloud.data.model.CacheRuleset
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Cache Rules CRUD（Rulesets entrypoint，phase http_request_cache_settings）+ 缓存响应规则（http_response_cache_settings，
 * 仅查看 / 启停 / 删除）。对应 iOS CacheRuleService。
 * 读 cache-settings.read，写 .write；phase 还没有规则集时 entrypoint 返回 404/业务错误，视为 null。
 */
@Singleton
class CacheRuleRepository @Inject constructor(
    private val api: CfApiClient,
) {
    private val phase = "http_request_cache_settings"
    private val responsePhase = "http_response_cache_settings"

    /** 取缓存规则 entrypoint ruleset；无规则集时返回 null。 */
    suspend fun ruleset(zoneId: String): CacheRuleset? = entrypointOrNull {
        api.get<CacheRuleset>("zones/$zoneId/rulesets/phases/$phase/entrypoint")
    }

    /** 缓存响应规则（http_response_cache_settings）entrypoint；该阶段还没有规则集时返回 null。 */
    suspend fun responseRuleset(zoneId: String): CacheResponseRuleset? = entrypointOrNull {
        api.get<CacheResponseRuleset>("zones/$zoneId/rulesets/phases/$responsePhase/entrypoint")
    }

    /** phase 还没有 entrypoint 时 CF 回 404 或「could not find entrypoint」业务错误，统一视为 null。 */
    private inline fun <T> entrypointOrNull(block: () -> T): T? = try {
        block()
    } catch (e: ApiError.Http) {
        if (e.status == 404) null else throw e
    } catch (e: ApiError.Cloudflare) {
        if (e.errors.any { it.message.contains("could not find entrypoint", ignoreCase = true) }) null else throw e
    }

    /** 启停一条缓存响应规则（PATCH 只带 enabled，与请求阶段同一端点形态）。 */
    suspend fun setResponseRuleEnabled(zoneId: String, rulesetId: String, ruleId: String, enabled: Boolean): CacheResponseRuleset =
        api.patch("zones/$zoneId/rulesets/$rulesetId/rules/$ruleId", CacheRuleToggle(enabled))

    /**
     * 校验（?dry_run=true）：发与保存完全相同的请求，只校验不落盘，通过时 result 为 null。
     * ruleId 非空 → PATCH 该规则；rulesetId 非空 → POST 追加；都为空 → PUT entrypoint 建集。
     */
    suspend fun validateRule(zoneId: String, rulesetId: String?, ruleId: String?, rule: CacheRuleCreate) {
        val dryRun = listOf("dry_run" to "true")
        when {
            ruleId != null && rulesetId != null ->
                api.sendChecked("PATCH", "zones/$zoneId/rulesets/$rulesetId/rules/$ruleId", rule, dryRun)
            rulesetId != null ->
                api.sendChecked("POST", "zones/$zoneId/rulesets/$rulesetId/rules", rule, dryRun)
            else ->
                api.sendChecked("PUT", "zones/$zoneId/rulesets/phases/$phase/entrypoint", CacheEntrypointUpdate(listOf(rule)), dryRun)
        }
    }

    suspend fun setRuleEnabled(zoneId: String, rulesetId: String, ruleId: String, enabled: Boolean): CacheRuleset =
        api.patch("zones/$zoneId/rulesets/$rulesetId/rules/$ruleId", CacheRuleToggle(enabled))

    suspend fun addRule(zoneId: String, rulesetId: String, rule: CacheRuleCreate): CacheRuleset =
        api.post("zones/$zoneId/rulesets/$rulesetId/rules", rule)

    suspend fun updateRule(zoneId: String, rulesetId: String, ruleId: String, rule: CacheRuleCreate): CacheRuleset =
        api.patch("zones/$zoneId/rulesets/$rulesetId/rules/$ruleId", rule)

    /** phase 还没有规则集时，用首条规则创建 entrypoint。 */
    suspend fun createEntrypoint(zoneId: String, rule: CacheRuleCreate): CacheRuleset =
        api.put("zones/$zoneId/rulesets/phases/$phase/entrypoint", CacheEntrypointUpdate(listOf(rule)))

    suspend fun deleteRule(zoneId: String, rulesetId: String, ruleId: String) =
        api.delete("zones/$zoneId/rulesets/$rulesetId/rules/$ruleId")
}
