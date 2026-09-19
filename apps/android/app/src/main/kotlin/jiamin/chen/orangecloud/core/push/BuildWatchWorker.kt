package jiamin.chen.orangecloud.core.push

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import jiamin.chen.orangecloud.R
import jiamin.chen.orangecloud.data.model.BuildDisplayState
import jiamin.chen.orangecloud.data.repository.AccountStore
import jiamin.chen.orangecloud.data.repository.WorkerBuildRepository
import java.util.concurrent.TimeUnit
import androidx.work.Constraints
import androidx.work.NetworkType

/**
 * 构建失败本地通知。
 *
 * Cloudflare **没有** Workers Builds 的告警类型（69 个 alert_type 里无对应项），
 * 走不了服务端 webhook，只能自己周期比对。已通知过的 build_uuid 落盘去重。
 *
 * 与「源站异常」不同：那个走 CF 原生 health_check_status_notification，服务端直推、
 * App 关着也收得到；这里是无告警可用时的退路，时机由 WorkManager 调度，可能延迟。
 *
 * 依赖用 EntryPoint 取而非 @HiltWorker —— 本工程没有引 androidx.hilt:hilt-work，
 * 为一个 Worker 加编译器依赖不划算。
 */
class BuildWatchWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    @EntryPoint
    @InstallIn(SingletonComponent::class)
    interface Deps {
        fun buildRepository(): WorkerBuildRepository
        fun accountStore(): AccountStore
        fun watchStore(): BuildWatchStore
        fun notifier(): PushNotifier
    }

    override suspend fun doWork(): Result {
        val deps = EntryPointAccessors.fromApplication(applicationContext, Deps::class.java)
        val watchStore = deps.watchStore()

        // 用户在构建页勾选要盯的脚本；没勾就不发任何请求
        val watched = watchStore.watchedNow()
        if (watched.isEmpty()) return Result.success()

        val accountStore = deps.accountStore()
        accountStore.ensureLoaded()
        val accountId = accountStore.selectedAccountId.value ?: return Result.success()

        val buildRepository = deps.buildRepository()
        val notified = watchStore.notifiedNow().toMutableSet()
        val failures = mutableListOf<String>()

        // 后台预算有限，最多盯 5 个脚本
        for (script in watched.take(5)) {
            val latest = runCatching { buildRepository.builds(accountId, script) }
                .getOrNull()?.firstOrNull() ?: continue
            if (latest.displayState != BuildDisplayState.FAILED) continue
            if (!notified.add(latest.buildUuid)) continue
            failures += script
        }

        if (failures.isNotEmpty()) {
            // 去重集合只保留最近 200 条，避免无限膨胀
            watchStore.setNotified(notified.toList().takeLast(200))
            deps.notifier().show(
                title = applicationContext.getString(R.string.builds_failed_title),
                body = applicationContext.getString(R.string.builds_failed_body, failures.joinToString("、")),
                url = null,
            )
        }
        return Result.success()
    }

    companion object {
        private const val NAME = "oc-build-watch"

        /** 勾选任一脚本后调用；WorkManager 保证唯一，重复调用不叠加。 */
        fun schedule(context: Context) {
            // 没网时别跑：离线状态下 validAccessToken 会去刷新并失败，白白消耗一次后台预算
            val request = PeriodicWorkRequestBuilder<BuildWatchWorker>(2, TimeUnit.HOURS)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(NAME)
        }
    }
}
