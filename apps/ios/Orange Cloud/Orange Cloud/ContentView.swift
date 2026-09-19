//
//  ContentView.swift
//  Orange Cloud
//
//  根视图：按登录态路由到欢迎页或主界面。
//

import SwiftUI
import SwiftData

struct ContentView: View {

    @Environment(AuthManager.self) private var auth
    @AppStorage(AppMotion.storageKey) private var reduceAnimations = false

    var body: some View {
        @Bindable var router = AppRouter.shared
        return Group {
            if auth.isLoggedIn {
                // 按身份重建会话子树：切换/新增登录身份时 SessionStore（含 token 客户端）全新创建
                SessionRootView(auth: auth)
                    .id(auth.currentSessionId)
            } else {
                LoginView()
            }
        }
        .animation(.smooth, value: auth.isLoggedIn)
        // App「减少动画」开关下注全树：Zoom 导航转场 / 玻璃岛浮现 / 骨架闪烁统一读它
        .environment(\.appReduceMotion, reduceAnimations)
        // 「免登录工具箱」挂在 auth 闸门之上（不随 .id 会话重建销毁），
        // 登录前后、通知点按统一从这里弹出。
        .fullScreenCover(isPresented: $router.presentToolbox) {
            ToolboxHubView()
        }
        // 启动自愈：清掉「文件」App 里不属于当前存活身份的孤儿挂载 domain（重装/登出残留，
        // 表现为侧边栏同名重复且删不掉、每重装一次多一个）。一次性，登录态与否都跑。
        .task {
            await FileProviderMountManager.reconcile(
                liveSessionIds: Set(auth.sessions.map(\.id.uuidString))
            )
        }
    }
}

/// 登录后才存在的子树：持有本次会话的 SessionStore（API Client + Services）
private struct SessionRootView: View {

    @State private var session: SessionStore

    init(auth: AuthManager) {
        _session = State(initialValue: SessionStore(authManager: auth))
    }

    var body: some View {
        MainTabView()
            .environment(session)
            .whatsNewSheet()
            .telemetryConsentPrompt()
            .ratingPrompt()
            .testFlightSunsetNotice()
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
        .modelContainer(for: [CachedZone.self, CachedDNSRecord.self], inMemory: true)
}
