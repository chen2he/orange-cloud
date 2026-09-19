//
//  MainTabView.swift
//  Orange Cloud
//
//  iPhone 底部 Tab，iPad 自动侧边栏（sidebarAdaptable，iOS 18+）；iOS 17 回退经典 TabView。
//  iOS 26 自动 Liquid Glass TabBar。
//

import SwiftUI

struct MainTabView: View {

    @Environment(SessionStore.self) private var session
    @Environment(AuthManager.self) private var auth
    @State private var selectedTab: AppTab = AppTab.initialTab
    private let router = AppRouter.shared

    var body: some View {
        tabContainer
            // 向下滚动收起 Tab 栏（iOS 26+）：Duo 外屏又宽又矮，Tab 栏又和工具栏挤在同一条竖轴上，
            // 长列表滚动时把这块空间让给内容。
            .ocTabBarMinimizeOnScroll()
            .task {
                consumePendingRoute()
                await session.ensureAccounts()
            }
            .onChange(of: router.pendingModule) {
                consumePendingRoute()
            }
    }

    @ViewBuilder
    private var tabContainer: some View {
        if #available(iOS 18.0, *) {
            // iOS 18+：值式 Tab + 侧边栏自适应（iPad 自动侧边栏）
            TabView(selection: $selectedTab) {
                Tab("概览", systemImage: "square.grid.2x2", value: AppTab.dashboard) {
                    dashboardTab
                }
                Tab("域名", systemImage: "globe", value: AppTab.zones) {
                    zonesTab
                }
                Tab("开发者", systemImage: "chevron.left.forwardslash.chevron.right", value: AppTab.developer) {
                    developerTab
                }
                Tab("存储", systemImage: "externaldrive", value: AppTab.storage) {
                    storageTab
                }
                Tab("设置", systemImage: "gear", value: AppTab.settings) {
                    settingsTab
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            // iOS 17：经典 TabView（底部 Tab；iPad 不走侧边栏自适应）
            TabView(selection: $selectedTab) {
                dashboardTab
                    .tabItem { Label("概览", systemImage: "square.grid.2x2") }
                    .tag(AppTab.dashboard)
                zonesTab
                    .tabItem { Label("域名", systemImage: "globe") }
                    .tag(AppTab.zones)
                developerTab
                    .tabItem { Label("开发者", systemImage: "chevron.left.forwardslash.chevron.right") }
                    .tag(AppTab.developer)
                storageTab
                    .tabItem { Label("存储", systemImage: "externaldrive") }
                    .tag(AppTab.storage)
                settingsTab
                    .tabItem { Label("设置", systemImage: "gear") }
                    .tag(AppTab.settings)
            }
        }
    }

    // MARK: - Tab 内容（两套 TabView 写法共用）

    // 账号维度的重建（.id(selectedAccount)）一律在各 Tab 视图内部、导航容器之内完成，
    // **这里不允许出现任何 .id**：ensureAccounts 可能在任意 Tab 可见时才完成或重试成功
    // （启动拉取失败后各页 load 都会重试），selectedAccount nil→账号翻转若重建可见
    // NavigationStack，iOS 17.0.x 导航栏硬断言必崩——1.8.2(24) 复发的根因就是
    // zones/developer/storage 三个 Tab 在此处残留的外层 .id（详见 DashboardView 注释）。

    @ViewBuilder private var dashboardTab: some View {
        DashboardView(session: session)
    }

    @ViewBuilder private var zonesTab: some View {
        ZoneListView(session: session)
    }

    @ViewBuilder private var developerTab: some View {
        // 开发者平台聚合入口：Workers / Queues / Durable Objects / Hyperdrive / Workers AI / AI Gateway
        DeveloperHubView(session: session)
    }

    @ViewBuilder private var storageTab: some View {
        StorageView(session: session)
    }

    @ViewBuilder private var settingsTab: some View {
        SettingsView()
    }

    /// App Intent（Siri/快捷指令/Spotlight）发起的跳转
    private func consumePendingRoute() {
        guard let module = router.pendingModule else { return }
        router.pendingModule = nil
        selectedTab = switch module {
        case .dashboard: .dashboard
        case .zones:     .zones
        case .workers:   .developer    // Workers 现归入「开发者」聚合 Tab
        case .storage:   .storage
        case .settings:  .settings
        }
    }

    enum AppTab: Hashable {
        case dashboard, zones, developer, storage, settings

        /// 启动落哪个 Tab。平时恒为概览；仅 DEBUG 下认启动参数
        /// `-ORANGE_START_TAB zones|developer|storage|settings`，
        /// 供模拟器自动化（宽幅布局巡检等）直接落到目标页——simctl 没有点按能力，
        /// 靠它免去 GUI 自动化。Release 构建里这段不参与编译。
        static var initialTab: AppTab {
            #if DEBUG
            switch ProcessInfo.processInfo.environment["ORANGE_START_TAB"]
                ?? UserDefaults.standard.string(forKey: "ORANGE_START_TAB") {
            case "zones":     return .zones
            case "developer": return .developer
            case "storage":   return .storage
            case "settings":  return .settings
            default:          return .dashboard
            }
            #else
            return .dashboard
            #endif
        }
    }
}
