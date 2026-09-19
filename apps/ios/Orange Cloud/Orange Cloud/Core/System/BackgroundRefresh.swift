//
//  BackgroundRefresh.swift
//  Orange Cloud
//
//  BGAppRefreshTask：后台静默刷新 OAuth Token，避免用户回到 App 时 Token 已过期。
//  标识符登记在 Info.plist 的 BGTaskSchedulerPermittedIdentifiers。
//

import Foundation
import BackgroundTasks
import SwiftData

@MainActor
enum BackgroundRefresh {

    static let taskIdentifier = "jiamin.chen.Orange-Cloud.refresh"

    /// 已注册标记：BGTaskScheduler 同一标识符重复注册会直接崩溃，注册必须幂等
    private static var didRegister = false

    /// 弱持有：注册发生在 App.init 最前（AuthManager 尚未构造），
    /// 且 enum 的静态闭包若强引用 AuthManager 会让它随进程永生。
    private static weak var authManager: AuthManager?

    /// App 启动时注册（必须在 didFinishLaunching 前，App.init 中调用）。
    /// 不依赖 AuthManager——注册只关心处理器登记成败，身份稍后用 `setAuthManager` 补上。
    static func register() {
        guard !didRegister else {
            AppLog.background.info("BGAppRefresh register skipped (already registered)")
            return
        }
        didRegister = true
        // 返回值必须记日志：注册失败（标识符未登记进 Info.plist / 调用时机过晚）
        // 是「后台刷新为何不跑」最常见的根因，丢弃它等于放弃排查
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task { @MainActor in
                await run(task: refreshTask)
            }
            refreshTask.expirationHandler = {
                // 系统按预算收回后台时间是常态，不是故障：记 notice 不进遥测
                AppLog.background.notice("BGAppRefresh expired (system cut off)")
                work.cancel()
                refreshTask.setTaskCompleted(success: false)
            }
        }
        AppLog.background.info("BGAppRefresh register(\(taskIdentifier)) -> \(registered)")
    }

    /// AuthManager 构造完成后回填（弱引用）
    static func setAuthManager(_ manager: AuthManager) {
        authManager = manager
        AppLog.background.info("BGAppRefresh auth manager attached")
    }

    /// 后台任务主体
    private static func run(task: BGAppRefreshTask) async {
        schedule()   // 链式排下一次
        guard let authManager else {
            // 理论不可达：App.init 里注册完立刻回填。真出现说明启动顺序被改坏了。
            AppLog.background.error("BGAppRefresh fired but no AuthManager attached")
            task.setTaskCompleted(success: false)
            return
        }
        AppLog.background.notice("BGAppRefresh fired, loggedIn=\(authManager.isLoggedIn)")
        if authManager.isLoggedIn {
            _ = try? await authManager.refreshAccessToken()
            // 系统收回预算时 expirationHandler 已 cancel 本 Task 并 setTaskCompleted(false)：
            // 后面的步骤不能再跑，也绝不能对同一个 BGTask 第二次 setTaskCompleted。
            if Task.isCancelled { return }
            // 预热当前账号域名快照，让用户切回前台 / 小组件刷新时直接见到最新数据
            await prewarmWidgetSnapshot(authManager: authManager)
            if Task.isCancelled { return }
            // 顺带做通知检测（Zone 状态变化 / Worker 错误）
            await AppNotifications.runBackgroundChecks(authManager: authManager)
            if Task.isCancelled { return }
        }
        task.setTaskCompleted(success: true)
        AppLog.background.info("BGAppRefresh completed")
    }

    /// 后台预热：刷新「当前账号」（Widget 默认展示的账号）的 Zone 列表进缓存 + Widget 总览快照，
    /// 并维护 Widget 账号目录。只刷一个账号，控制后台时间预算；任何失败静默忽略。
    private static func prewarmWidgetSnapshot(authManager: AuthManager) async {
        let client = CFAPIClient(authManager: authManager)
        guard let accounts = try? await AccountService(client: client).listAccounts(),
              !accounts.isEmpty else { return }
        // 优先预热 App Group 记录的当前账号，否则取第一个
        let targetId = WidgetSnapshot.currentAccountId()
        let account = accounts.first { $0.id == targetId } ?? accounts[0]
        guard let zones = try? await ZoneService(client: client).listZones(accountId: account.id) else { return }
        let context = ModelContext(CacheContainer.shared)
        CacheSync.syncZones(zones, accountId: account.id, accountName: account.name, context: context)
        // Widget 账号目录（选择账号 picker 数据源）后台也保持最新
        if let sessionId = authManager.currentSessionId {
            WidgetDataStore.mergeAccounts(
                accounts.map { WidgetAccount(id: $0.id, name: $0.name, sessionId: sessionId.uuidString) },
                sessionId: sessionId.uuidString
            )
        }
    }

    /// 进入后台时调度（系统决定实际执行时机）
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)   // 至少 4 小时后
        do {
            try BGTaskScheduler.shared.submit(request)
            AppLog.background.info("scheduled BGAppRefresh (earliest +4h)")
        } catch {
            AppLog.background.error("schedule BGAppRefresh failed: \(error.localizedDescription)")
        }
    }
}
