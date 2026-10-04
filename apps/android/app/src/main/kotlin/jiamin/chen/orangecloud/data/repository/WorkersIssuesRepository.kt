package jiamin.chen.orangecloud.data.repository

import jiamin.chen.orangecloud.core.network.CfApiClient
import jiamin.chen.orangecloud.core.network.Paged
import jiamin.chen.orangecloud.data.model.WorkerIssue
import jiamin.chen.orangecloud.data.model.WorkerIssueEnvelope
import jiamin.chen.orangecloud.data.model.WorkerIssueOccurrence
import jiamin.chen.orangecloud.data.model.WorkerIssueOccurrencePage
import jiamin.chen.orangecloud.data.model.WorkerIssueStatusUpdate
import jiamin.chen.orangecloud.data.model.WorkerIssuesSummary
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Workers Issues（公开测试，2026-09-30 起）。读走 workers-observability.read，
 * 改状态走 workers-observability.write（2026 秋季新增 scope，老用户需重新授权）。
 */
@Singleton
class WorkersIssuesRepository @Inject constructor(
    private val api: CfApiClient,
) {
    private fun base(accountId: String) = "accounts/$accountId/workers/observability/issues"

    /** 任一问题改状态成功后发一次，列表 / Worker 详情的计数据此刷新（不必经导航回传结果）。 */
    private val _changes = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val changes: SharedFlow<Unit> = _changes.asSharedFlow()

    /**
     * 问题列表一页。status = active / resolved / ignored；service 为空表示全账户。
     * 按最近发生倒序；perPage 上限 100。
     */
    suspend fun issues(
        accountId: String,
        status: String,
        service: String?,
        page: Int,
        perPage: Int = PAGE_SIZE,
    ): Paged<WorkerIssue> {
        val query = buildList {
            add("status" to status)
            service?.takeIf { it.isNotBlank() }?.let { add("service" to it) }
            add("page" to page.toString())
            add("perPage" to perPage.coerceIn(1, 100).toString())
            add("orderBy" to "lastObserved")
            add("order" to "desc")
        }
        return api.getList(base(accountId), query)
    }

    /** 汇总：活跃问题数 / 活跃发生次数 / 已解决数。service 非空时只统计该 Worker。 */
    suspend fun summary(accountId: String, service: String? = null): WorkerIssuesSummary =
        api.get(
            "${base(accountId)}/summary",
            service?.takeIf { it.isNotBlank() }?.let { listOf("service" to it) }.orEmpty(),
        )

    suspend fun issue(accountId: String, issueId: String): WorkerIssue? =
        api.get<WorkerIssueEnvelope>("${base(accountId)}/$issueId").issue

    /**
     * 改状态（resolved / ignored / active）。回包形态（是否包一层 issue）文档未写死，
     * 这里只校验 success，再重读一次详情作为最新值；重读失败返回 null，由调用方本地更新状态。
     */
    suspend fun updateStatus(accountId: String, issueId: String, status: String): WorkerIssue? {
        api.patchChecked("${base(accountId)}/$issueId", WorkerIssueStatusUpdate(status))
        _changes.tryEmit(Unit)
        return runCatching { issue(accountId, issueId) }.getOrNull()
    }

    /** 最近发生记录一页（游标分页：result_info.cursors.after）。 */
    suspend fun occurrences(accountId: String, issueId: String, cursor: String?): WorkerIssueOccurrencePage {
        val query = buildList {
            add("per_page" to OCCURRENCE_PAGE_SIZE.toString())
            cursor?.let { add("cursor" to it) }
        }
        val paged = api.getList<WorkerIssueOccurrence>("${base(accountId)}/$issueId/occurrences", query)
        // 游标没变或本页为空即视为到底，防止服务端回同一游标导致死循环翻页
        val next = paged.info?.cursorAfter?.takeIf { it != cursor && paged.items.isNotEmpty() }
        return WorkerIssueOccurrencePage(paged.items, next)
    }

    companion object {
        const val PAGE_SIZE = 50
        const val OCCURRENCE_PAGE_SIZE = 20
    }
}
