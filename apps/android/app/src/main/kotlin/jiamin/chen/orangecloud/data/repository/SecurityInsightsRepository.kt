package jiamin.chen.orangecloud.data.repository

import jiamin.chen.orangecloud.core.network.CfApiClient
import jiamin.chen.orangecloud.data.model.SecurityInsight
import jiamin.chen.orangecloud.data.model.SecurityInsightDismissRequest
import jiamin.chen.orangecloud.data.model.SecurityInsightScanRequest
import jiamin.chen.orangecloud.data.model.SecurityInsightsPage
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 安全洞察（Security Center Insights）。全套餐可用，权限走 zone-settings.read / .write。
 * 扫描按需发起：每个账户每 24 小时最多 5 次（全账户共享），超限时透出 CF 的报错原文。
 */
@Singleton
class SecurityInsightsRepository @Inject constructor(
    private val api: CfApiClient,
) {
    /** 未忽略的全部洞察。分页信息在 result 里，按 count 翻页，设页数上限防失控。 */
    suspend fun insights(zoneId: String): List<SecurityInsight> {
        val all = mutableListOf<SecurityInsight>()
        var page = 1
        while (page <= MAX_PAGES) {
            val result = api.get<SecurityInsightsPage>(
                "zones/$zoneId/security-center/insights",
                listOf("dismissed" to "false", "page" to page.toString(), "per_page" to PER_PAGE.toString()),
            )
            val issues = result.issues.orEmpty()
            all += issues
            val total = result.count ?: break
            if (issues.isEmpty() || all.size >= total) break
            page++
        }
        return all.distinctBy { it.id }
    }

    /** 发起一次全量扫描（空 body = 扫描全部）。结果异步产出，稍后刷新列表可见。 */
    suspend fun scan(zoneId: String) {
        api.postChecked("zones/$zoneId/security-center/insights/scans", SecurityInsightScanRequest())
    }

    /** 忽略一条洞察（之后 dismissed=false 的列表里不再出现）。 */
    suspend fun dismiss(zoneId: String, issueId: String) {
        api.putChecked("zones/$zoneId/security-center/insights/$issueId/dismiss", SecurityInsightDismissRequest(true))
    }

    private companion object {
        const val PER_PAGE = 100
        const val MAX_PAGES = 10
    }
}
