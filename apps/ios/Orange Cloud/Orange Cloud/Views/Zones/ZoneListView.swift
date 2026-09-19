//
//  ZoneListView.swift
//  Orange Cloud
//
//  Zones 列表：
//  - iPhone（compact）：NavigationStack + 卡片 + zoom 过渡
//  - iPad（regular）：NavigationSplitView 双栏（P5）
//

import SwiftUI
import SwiftData
import TipKit

/// 域名 Tab 外壳：导航容器（Stack / Split）常驻，账号切换只重建容器内内容。
/// **不要把 `.id(账号)` 挪回容器外层或 MainTabView**：ensureAccounts 可能在本 Tab
/// 可见时才完成或重试成功，selectedAccount nil→账号翻转若整体重建可见 NavigationStack，
/// iOS 17.0.x 导航栏硬断言必崩（1.8.2(24) 复发根因，详见 DashboardView 注释）。
///
/// **`.navigationDestination` 必须挂在这里（栈根直接子级）、且写在 `.id(账号)` 的内侧**：
/// ① navdest 注册在栈内容的嵌套子视图（ZoneListContent 内层）时，iOS 17.0 push CachedZone
///   会陷入 AttributeGraph 无限更新循环（目的地解析与子视图更新相互失效），主线程 100%
///   整 App 冻结、连 tab bar 都不响应；26.5 无恙。与 `.id(账号)` 无关（去掉 .id 仍冻结，实测二分）。
/// ② 但 navdest 也不能写在 `.id()` 之后：账号切换 id 翻转时 iOS 17.0 导航栏硬断言必崩
///   （实测，同 DashboardView 外壳注释）。
/// 唯一两全的形态 = 外壳栈根 + `.id` 内侧：`content.navigationDestination(...).id(...)`。
/// 同 DeveloperHubView 的 DevHubRoute navdest 铁律：navdest 只挂栈根。
struct ZoneListView: View {

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedZone: CachedZone?
    /// 分栏的边栏可见性。**必须显式给 `.doubleColumn`**：`.automatic` 下系统会按宽高组合
    /// 自行决定，实测 744×1133（iPad mini 竖屏 / 折叠机内屏一档）会把边栏整个折起来，
    /// 整屏只剩「选择一个域名」占位——域名页开屏即空。956×440（iPhone 横屏，同为 regular）
    /// 却正常展开，所以这是宽高组合相关、默认值靠不住。用 @State 而非常量绑定，
    /// 用户仍可手动收起边栏。
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    /// zoom 转场源（列表行）在 ZoneListContent 里标记，namespace 由外壳持有传入，
    /// 让栈根 navdest 的目的页能引用同一命名空间。
    @Namespace private var zoomNamespace

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
    }

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                ZoneListContent(session: session, isSplit: true, selectedZone: $selectedZone, zoomNamespace: zoomNamespace)
                    .id(session.selectedAccount?.id)
                    // 选中态住在外壳，账号切换时手动清空，否则 detail 栏残留旧账号的域名
                    .onChange(of: session.selectedAccount?.id) {
                        selectedZone = nil
                    }
            } detail: {
                if let zone = selectedZone {
                    NavigationStack {
                        // split 模式下详情栏自成一栈，域名子树路由挂在这个栈根
                        ZoneDetailView(zone: zone, session: session)
                            .zoneRouteDestinations(session: session)
                    }
                } else {
                    ContentUnavailableView("选择一个域名", systemImage: "globe", description: Text("从左侧列表选择域名查看详情"))
                }
            }
            // 窄画布（744pt 这一档）下 .automatic 会偏向详情栏、把边栏挤没；balanced 让两栏平权
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack {
                ZoneListContent(session: session, isSplit: false, selectedZone: .constant(nil), zoomNamespace: zoomNamespace)
                    .navigationDestination(for: CachedZone.self) { zone in
                        ZoneDetailView(zone: zone, session: session)
                            .zoomNavigationTransition(sourceID: zone.id, in: zoomNamespace)
                    }
                    .zoneRouteDestinations(session: session)
                    .id(session.selectedAccount?.id)
            }
        }
    }
}

/// 域名列表内容（原 ZoneListView 本体）：@Query 谓词在 init 按当前账号构建，
/// 外壳用 `.id(selectedAccount)` 在账号切换时重建本视图以刷新谓词。
private struct ZoneListContent: View {

    @Environment(SessionStore.self) private var session
    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Query private var cachedZones: [CachedZone]

    @State private var viewModel: ZoneListViewModel
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var showAddDenied = false

    private let isSplit: Bool
    @Binding private var selectedZone: CachedZone?
    /// 外壳持有的 zoom 转场命名空间（目的页转场挂外壳栈根 navdest，源标记在本视图的行上）
    private let zoomNamespace: Namespace.ID

    init(session: SessionStore, isSplit: Bool, selectedZone: Binding<CachedZone?>, zoomNamespace: Namespace.ID) {
        let accountId = session.selectedAccount?.id ?? ""
        _cachedZones = Query(
            filter: #Predicate<CachedZone> { $0.accountId == accountId },
            sort: \CachedZone.name
        )
        _viewModel = State(initialValue: ZoneListViewModel(zoneService: session.zoneService))
        self.isSplit = isSplit
        _selectedZone = selectedZone
        self.zoomNamespace = zoomNamespace
    }

    private var filteredZones: [CachedZone] {
        guard !searchText.isEmpty else { return cachedZones }
        return cachedZones.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var activeCount: Int {
        cachedZones.filter { $0.status == "active" }.count
    }

    // MARK: - 添加域名（zone.write 门控）

    private var canWrite: Bool { auth.hasScope("zone.write") }

    /// 有 zone.write 才展示添加表单，否则弹权限提示（同 DNS 的处理）
    private func requireAddZone() {
        if canWrite { showAddSheet = true } else { showAddDenied = true }
    }

    var body: some View {
        Group {
            if isSplit {
                sidebarLayout
            } else {
                stackLayout
            }
        }
        .task {
            await refresh()
        }
        .sheet(isPresented: $showAddSheet) {
            if let account = session.selectedAccount {
                AddZoneView(
                    accountId: account.id,
                    accountName: account.name,
                    zoneService: session.zoneService
                )
            }
        }
        .alert("权限不足", isPresented: $showAddDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含域名编辑权限（zone.write）。\n请在设置中退出登录后重新授权「域名」并开启编辑权限。")
        }
    }

    private var addButton: some View {
        Button("添加域名", systemImage: "plus") {
            requireAddZone()
        }
    }

    // MARK: - iPad 侧栏（regular；NavigationSplitView 容器在外壳）

    private var sidebarLayout: some View {
        Group {
            if cachedZones.isEmpty && viewModel.isLoading {
                SkeletonList(rows: 8, icon: .circle(30), trailing: true)
            } else if cachedZones.isEmpty {
                emptyState
            } else if filteredZones.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(selection: $selectedZone) {
                    Section {
                        ForEach(filteredZones) { zone in
                            ZoneSidebarRow(zone: zone)
                                .tag(zone)
                        }
                    } header: {
                        Text("\(cachedZones.count) 个域名 · \(activeCount) 个已启用")
                    }
                }
                .refreshable { await refresh(force: true) }
            }
        }
        .navigationTitle("域名")
        .searchable(text: $searchText, prompt: "搜索域名")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                refreshButton
            }
            .ocPriority(.secondary)
            ToolbarItem(placement: .topBarTrailing) {
                addButton
            }
            .ocPriority(.primary)
        }
        .navigationSplitViewColumnWidth(min: 300, ideal: 340)
    }

    // MARK: - iPhone 单栏（compact；NavigationStack 容器在外壳）

    private var stackLayout: some View {
        Group {
            if cachedZones.isEmpty && viewModel.isLoading {
                SkeletonCardList()
            } else if cachedZones.isEmpty {
                emptyState
            } else if filteredZones.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                zoneList
            }
        }
        .background { SkyBackground() }
        .navigationTitle("域名")
        .searchable(text: $searchText, prompt: "搜索域名")
        // navigationDestination(for: CachedZone.self) 挂在外壳 ZoneListView 的栈根，
        // 不能挂回这里：iOS 17.0 上 navdest 注册在栈内容的嵌套子视图会在 push 时
        // 触发 AttributeGraph 无限循环整 App 冻结（见外壳注释）。
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                refreshButton
            }
            .ocPriority(.secondary)
            ToolbarItem(placement: .topBarTrailing) {
                addButton
            }
            .ocPriority(.primary)
        }
    }

    private var zoneList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: OCLayout.islandGap) {
                // 大标题下的统计副标题（设计稿 oc-subtitle）
                Text("\(cachedZones.count) 个域名 · \(activeCount) 个已启用")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                TipView(ZoneRefreshTip())
                ForEach(filteredZones) { zone in
                    NavigationLink(value: zone) {
                        ZoneCard(zone: zone, accountName: session.selectedAccount?.name ?? "")
                    }
                    .buttonStyle(.plain)
                    .zoomTransitionSource(id: zone.id, in: zoomNamespace)
                }
            }
            .padding(OCLayout.pagePadding)
        }
        .refreshable {
            await refresh(force: true)
        }
    }

    // MARK: - 共用

    private var refreshButton: some View {
        RefreshButton(
            isLoading: viewModel.isLoading,
            failed: viewModel.error != nil,
            action: { Task { await refresh(force: true) } }
        )
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("没有域名", systemImage: "globe.slash")
        } description: {
            Text(canWrite
                 ? String(localized: "当前账号下还没有域名，现在就添加第一个吧")
                 : String(localized: "当前账号下还没有域名"))
        } actions: {
            if canWrite {
                Button("添加域名") { showAddSheet = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ocOrangePressed)
                    .fontWeight(.bold)
                Button("刷新") { Task { await refresh(force: true) } }
                    .buttonStyle(.bordered)
            } else {
                Button("刷新") { Task { await refresh(force: true) } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ocOrangePressed)
                    .fontWeight(.bold)
            }
        }
    }

    private func refresh(force: Bool = false) async {
        await session.ensureAccounts()
        guard let account = session.selectedAccount else { return }
        await viewModel.refresh(accountId: account.id, accountName: account.name, context: modelContext, force: force)
    }
}

// MARK: - iPad 侧栏行

private struct ZoneSidebarRow: View {
    let zone: CachedZone

    var body: some View {
        HStack(spacing: 10) {
            ZoneAvatar(domain: zone.name, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(zone.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                PlanBadge(planName: zone.planName)
            }
            Spacer()
            StatusDot(status: zone.displayStatus, size: 7)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Zone 卡片（iPhone）

struct ZoneCard: View {
    let zone: CachedZone
    var accountName: String = ""

    var body: some View {
        HStack(spacing: 12) {
            ZoneAvatar(domain: zone.name, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(zone.name)
                        .font(.headline)
                        .lineLimit(1)
                    PlanBadge(planName: zone.planName)
                }
                if !accountName.isEmpty {
                    Text(accountName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            StatusDot(status: zone.displayStatus)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(OCLayout.islandPadding)
        .glassIsland()
    }
}
