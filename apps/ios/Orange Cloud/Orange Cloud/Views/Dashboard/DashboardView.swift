//
//  DashboardView.swift
//  Orange Cloud
//
//  账号概览：问候区 + 2×2 指标卡 + 每个域名的信息卡（24h 请求迷你图，点击进详情）+ 网络入口。
//

import SwiftUI
import SwiftData
import TipKit
import WidgetKit

/// 概览页外壳：NavigationStack 常驻，账号切换只重建栈内内容。
///
/// **不要把 `.id(账号)` 加回 NavigationStack 外层**（也别在 MainTabView 的 tab 上加）：
/// 重建整个 NavigationStack 会连正在显示的导航栏一起换掉，iOS 17.0.x 的 UIKit 在
/// `-[UINavigationBar layoutSubviews]` 对此硬断言（"top item belongs to a different
/// navigation bar"）——冷启动账号加载完成时 id 从 nil 翻转，概览页必崩（17.1 起系统才修复）。
/// 1.5.1 曾误诊为 TipKit popover。账号维度的 @Query 谓词刷新由栈内的 `.id` 完成。
///
/// **`.navigationDestination` 必须挂在这里（栈根直接子级）、且写在 `.id(账号)` 的内侧**：
/// ① navdest 注册在栈内容的嵌套子视图（DashboardHomeView 内层）时，iOS 17.0 push 会陷入
///   AttributeGraph 无限更新循环，主线程 100% 整 App 冻结（tab bar 都不响应）；26.5 无恙。
///   与 `.id(账号)` 无关（实测二分，详见 ZoneListView 外壳注释）。
/// ② 但 navdest 也不能写在 `.id()` 之后（`content.id(...).navigationDestination(...)`）：
///   账号切换 id 翻转时 iOS 17.0 在 `-[UINavigationBar layoutSubviews]` 硬断言必崩（实测）。
/// 唯一两全的形态 = 外壳栈根 + `.id` 内侧：`content.navigationDestination(...).id(...)`。
struct DashboardView: View {

    @Environment(AuthManager.self) private var auth
    @Environment(EntitlementStore.self) private var entitlements

    private let session: SessionStore

    /// 命令搜索 / 告警中心选中的资源目的地：栈根用 `.navigationDestination(item:)` 承接。
    /// 用 item 版而非 NavigationPath：本工程没有一处 `NavigationStack(path:)`，
    /// 而 item 版同样能程序化 push（TunnelCreateView 已在用），改动面与风险都最小。
    @State private var resourceRoute: DashboardResourceRoute?

    init(session: SessionStore) {
        self.session = session
    }

    private var currentAccountId: String {
        session.selectedAccount?.id ?? ""
    }

    var body: some View {
        NavigationStack {
            DashboardHomeView(session: session, resourceRoute: $resourceRoute)
                .navigationDestination(for: CachedZone.self) { zone in
                    ZoneDetailView(zone: zone, session: session)
                }
                // Tunnel 全链路（列表 → 详情 → 连接信息）都挂在栈根：单一栈、不嵌套，
                // 逐级 push 才在 iOS 17.0 正常（同 DeveloperHubView 的 DevHubRoute 做法）
                .navigationDestination(for: DashboardRoute.self) { route in
                    switch route {
                    case .registrar:
                        RegistrarView(session: session)
                    case .urlScanner:
                        URLScannerView(session: session)
                    case .requestTracer:
                        RequestTracerView(session: session)
                    case .tunnels:
                        TunnelListView(session: session)
                    case .tunnelConnect(let tunnel):
                        TunnelConnectView(tunnel: tunnel, accountId: currentAccountId, session: session)
                    case .turnstile:
                        TurnstileListView(session: session)
                    case .accessApps:
                        AccessAppsView(session: session)
                    case .gatewayRules:
                        GatewayRulesView(session: session)
                    case .bulkRedirects:
                        BulkRedirectListsView(session: session)
                    }
                }
                .navigationDestination(for: Tunnel.self) { tunnel in
                    TunnelDetailView(
                        tunnel: tunnel,
                        accountId: currentAccountId,
                        session: session,
                        canWrite: auth.hasScope("argotunnel.write"),
                        canWriteDNS: auth.hasScope("dns.write")
                    )
                }
                // Turnstile 详情同 Tunnel：列表行值式 push，目的页挂栈根
                .navigationDestination(for: TurnstileWidget.self) { widget in
                    TurnstileDetailView(widget: widget, session: session)
                }
                // 命令搜索 / 告警中心 / 跨类型置顶的跳转（Worker 详情、R2 对象、D1 控制台、
                // KV 键列表内部都还要继续 push）同样只挂栈根，值式
                .navigationDestination(item: $resourceRoute) { route in
                    resourceDestination(route)
                }
                // 域名详情子树（规则 hub / 负载均衡 / Snippets / Bulk Redirects）从本栈
                // push 的域名卡进入，其路由也要挂在本栈根
                .zoneRouteDestinations(session: session)
                .id(session.selectedAccount?.id)
        }
        // 账号切换后旧账号的资源目的地不应留在栈上
        .onChange(of: session.selectedAccount?.id) {
            resourceRoute = nil
        }
    }

    /// 免费层的 Pro 资源正常做法是在**派发前**就弹付费墙（DashboardHomeView.openResource），
    /// 根本走不到这里；这层只是兜底，防止将来新加的入口漏挂闸门直接把详情页放进来。
    @ViewBuilder
    private func resourceDestination(_ route: DashboardResourceRoute) -> some View {
        if let feature = route.proFeature, !entitlements.isPro {
            ProLockedView(feature: feature)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            unlockedResourceDestination(route)
        }
    }

    @ViewBuilder
    private func unlockedResourceDestination(_ route: DashboardResourceRoute) -> some View {
        switch route {
        case .zone(let zone):
            ZoneDetailView(zone: zone, session: session)
        case .worker(let script):
            WorkerDetailView(script: script, session: session)
        case .bucket(let bucket):
            R2ObjectListView(bucket: bucket, session: session)
        case .database(let database):
            D1QueryView(database: database, session: session)
        case .namespace(let namespace):
            KVKeyListView(namespace: namespace, session: session)
        case .tunnel(let tunnel):
            TunnelDetailView(
                tunnel: tunnel,
                accountId: currentAccountId,
                session: session,
                canWrite: auth.hasScope("argotunnel.write"),
                canWriteDNS: auth.hasScope("dns.write")
            )
        }
    }
}

/// 概览页内容（原 DashboardView 本体）：@Query 谓词在 init 按当前账号构建，
/// 外壳用 `.id(selectedAccount)` 在账号切换时重建本视图以刷新谓词。
private struct DashboardHomeView: View {

    @Environment(SessionStore.self) private var session
    @Environment(AuthManager.self) private var auth
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.modelContext) private var modelContext
    /// 矮画布（折叠机外屏横放、iPhone 横屏、iPhone 镜像的扁窗口）：440pt 高度下
    /// 常规问候区要吃掉一半屏，页头必须换紧凑排法，见 daybreakHeader
    @Environment(\.verticalSizeClass) private var vSizeClass
    /// 宽画布下顶部是 Tab 胶囊，锚在工具栏头像上的 TipKit popover 会横着盖住它，
    /// 改走页内 TipView，见 accountSwitchTip 的两处用法
    @Environment(\.horizontalSizeClass) private var hSizeClass
    // 域名 / Workers 缓存只取当前账号（父视图 .id(selectedAccount) 切换账号时重建以刷新谓词）；
    // DNS 记录缓存无 accountId 字段，按当前账号下的缓存域名在内存里过滤计数。
    @Query private var cachedZones: [CachedZone]
    @Query private var cachedWorkers: [CachedWorkerScript]
    @Query private var cachedRecords: [CachedDNSRecord]

    @State private var viewModel: DashboardViewModel

    /// 命令搜索选中的目的地：先关 sheet、再在 onDismiss 里赋给栈根的 item navdest
    @Binding private var resourceRoute: DashboardResourceRoute?
    @State private var showSearch = false
    @State private var pendingRoute: DashboardResourceRoute?
    /// 免费层点 Pro 资源（R2 / D1 / KV / Tunnel）时弹的付费墙场景。
    /// 状态放 @Observable 而非本视图 @State：本视图 body 极重（问候区 TimelineView、
    /// 宫格、每个域名的迷你图、置顶清单的全量资源字典），@State 翻转会让整页在
    /// sheet 呈现动画的起帧同帧重算，iPhone 11 级设备上是可感知的顿挫（issue #69）；
    /// 隔离后只有 PaywallSheetHost 重算。
    @State private var paywallPresenter = DashboardPaywallPresenter()

    // 套餐预设与账单日按账户存储（AccountPrefsStore，开启 iCloud 同步后跨设备）
    private let prefsStore = AccountPrefsStore.shared
    // 跨类型置顶（域名 / Workers / R2 / D1 / KV / Tunnel），按账号隔离
    private let pinnedStore = PinnedResourceStore.shared

    private var currentAccountId: String {
        session.selectedAccount?.id ?? ""
    }

    private var accountPrefs: AccountPrefsStore.Prefs {
        prefsStore.prefs(for: currentAccountId)
    }

    private var workersPlanPaidBinding: Binding<Bool> {
        Binding(
            get: { prefsStore.prefs(for: currentAccountId).workersPlanPaid },
            set: { value in prefsStore.update(currentAccountId) { $0.workersPlanPaid = value } }
        )
    }

    private var r2PlanPaidBinding: Binding<Bool> {
        Binding(
            get: { prefsStore.prefs(for: currentAccountId).r2PlanPaid },
            set: { value in prefsStore.update(currentAccountId) { $0.r2PlanPaid = value } }
        )
    }

    private var billingCycleDayBinding: Binding<Int> {
        Binding(
            get: { prefsStore.prefs(for: currentAccountId).billingCycleDay },
            set: { value in prefsStore.update(currentAccountId) { $0.billingCycleDay = value } }
        )
    }

    private let accountSwitchTip = AccountSwitchTip()

    /// 用量宫格点开的服务明细（sheet）
    @State private var usageDetail: UsageService?

    /// 「今日」日界口径（设置页修改，App Group 与 Widget 共享）；变更后强制刷新用量
    @AppStorage(DayBoundary.storageKey, store: UserDefaults(suiteName: WidgetSnapshot.appGroupID))
    private var dayBoundaryRaw = DayBoundary.utc.rawValue

    init(session: SessionStore, resourceRoute: Binding<DashboardResourceRoute?>) {
        _resourceRoute = resourceRoute
        let accountId = session.selectedAccount?.id ?? ""
        _cachedZones = Query(
            filter: #Predicate<CachedZone> { $0.accountId == accountId },
            sort: \CachedZone.name
        )
        _cachedWorkers = Query(
            filter: #Predicate<CachedWorkerScript> { $0.accountId == accountId }
        )
        _viewModel = State(initialValue: DashboardViewModel(
            analyticsService: session.analyticsService,
            accountService: session.accountService,
            r2Service: session.r2Service,
            d1Service: session.d1Service,
            zoneService: session.zoneService,
            workerService: session.workerService,
            dnsService: session.dnsService,
            kvService: session.kvService,
            tunnelService: session.tunnelService
        ))
    }

    // 订阅接口可用时自动识别，否则用按账户的本地预设
    private var effectiveWorkersPaid: Bool { viewModel.billing?.workersPaid ?? accountPrefs.workersPlanPaid }
    private var effectiveR2Paid: Bool { viewModel.billing?.r2Paid ?? accountPrefs.r2PlanPaid }

    private var monthlyLabel: String {
        (viewModel.billing?.periodStart != nil || accountPrefs.billingCycleDay != 1) ? String(localized: "账期") : String(localized: "本月")
    }

    private var activeCount: Int {
        cachedZones.filter { $0.status == "active" }.count
    }

    /// DNS 记录数：接口汇总优先（viewModel.dnsRecordTotal），
    /// 回退时按当前账号下的缓存域名过滤本地记录，避免跨账号累加。
    private var dnsRecordCount: Int {
        if let total = viewModel.dnsRecordTotal { return total }
        let zoneIds = Set(cachedZones.map(\.id))
        return cachedRecords.filter { zoneIds.contains($0.zoneId) }.count
    }

    // MARK: - 跨类型置顶 / 搜索 / 告警的数据

    private var zonesById: [String: CachedZone] {
        Dictionary(cachedZones.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 当前账号固定的域名 id（统一置顶 store 为准；旧的 CachedZone.pinned 已一次性迁移进来）
    private var pinnedZoneIds: [String] {
        pinnedStore.pins(for: currentAccountId, type: .zone).map(\.resourceId)
    }

    /// 首页展示的域名：用户 pin 过的优先（按固定顺序）；一个没 pin 时兜底展示前 3 个
    private var displayZones: [CachedZone] {
        let byId = zonesById
        let pinned = pinnedZoneIds.compactMap { byId[$0] }
        return pinned.isEmpty ? Array(cachedZones.prefix(3)) : pinned
    }

    /// 全账号可搜索资源（域名 / Workers 走 SwiftData 缓存，其余四类来自 VM 惰性补拉的清单）
    private var resourceItems: [DashboardResourceItem] {
        DashboardResourceCatalog.items(
            zones: cachedZones,
            workers: cachedWorkers,
            buckets: viewModel.r2Buckets,
            databases: viewModel.d1Databases,
            namespaces: viewModel.kvNamespaces,
            tunnels: viewModel.tunnels
        )
    }

    /// 域名以外的固定项（域名仍在「域名」段展示，避免同一张卡出现两次）
    private var pinnedNonZoneResources: [PinnedResource] {
        pinnedStore.pins(for: currentAccountId).filter { $0.type != .zone }
    }

    private var alerts: [DashboardAlert] {
        DashboardAlerts.build(
            zones: cachedZones,
            tunnels: viewModel.tunnels,
            // 资产仍在加载时不下「一个 Worker 都没有」的结论（缓存此刻本来就是空的）
            workerCount: (auth.hasScope("workers-scripts.read") && !viewModel.isLoadingAssets && !cachedZones.isEmpty)
                ? cachedWorkers.count
                : nil
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                daybreakHeader
                    .islandReveal(0)
                if usesInlineTip {
                    TipView(accountSwitchTip)
                }
                if let sid = auth.currentSessionId, auth.sessionsNeedingReauth.contains(sid) {
                    // token 缺 refresh token（无从续期）：给「重新授权」引导而非泛化的刷新失败——
                    // 一键重授权对同一身份原地换新令牌，成功后自动摘标并重拉数据
                    reauthBanner(sessionId: sid)
                } else if session.error != nil || viewModel.loadFailed {
                    RefreshFailedBanner { Task { await refreshAll() } }
                }
                Group {
                    if cachedZones.isEmpty && viewModel.isLoadingAssets {
                        statSkeleton
                    } else {
                        statIslands
                    }
                }
                .islandReveal(1)
                // 首屏还没有任何缓存、资产仍在加载时先不出告警卡（免得空数据被当成「一切正常」）
                if !(cachedZones.isEmpty && viewModel.isLoadingAssets) {
                    AlertCenterCard(alerts: alerts) { route in
                        openResource(route)
                    }
                    .islandReveal(2)
                }
                usageSection
                    .islandReveal(3)
                zonesSection
                    .islandReveal(4)
                // 无固定项时整段不出现（islandReveal 挂在段内，避免空段占掉 VStack 间距）
                pinnedResourcesSection
                networkSection
                    .islandReveal(6)
                bulkRedirectsSection
                    .islandReveal(7)
            }
            .padding(OCLayout.pagePadding)
            // 宽画布下收进可读宽度并居中；天空仍由外层 ScrollView 的 background 出血铺满
            .ocReadableWidth()
        }
        .background { SkyBackground() }
        .navigationBarTitleDisplayMode(.inline)
        // CachedZone / DashboardRoute / Tunnel 的 .navigationDestination 全部挂在外壳
        // DashboardView 的栈根，不能挂回这里：iOS 17.0 上 navdest 注册在栈内容的嵌套
        // 子视图会在 push 时触发 AttributeGraph 无限循环整 App 冻结（见外壳注释）。
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("搜索资源", systemImage: "magnifyingglass") {
                    showSearch = true
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                accountMenu
            }
        }
        // 搜索面板里选中资源后：先关 sheet，关闭完成再派发给栈根 navdest（不在 sheet 内 push）
        .sheet(isPresented: $showSearch, onDismiss: dispatchPendingRoute) {
            ResourceSearchView(
                items: resourceItems,
                accountId: currentAccountId,
                onSelect: { route in
                    pendingRoute = route
                    showSearch = false
                }
            )
        }
        .task(id: session.accounts.count) {
            AccountSwitchTip.hasMultipleAccounts = session.accounts.count > 1 || auth.sessions.count > 1
        }
        .task(id: displayZones.map(\.id)) {
            await loadTraffic()
        }
        // 账号维度的重跑由外壳 `.id(selectedAccount?.id)` 重建本视图完成，这两个 task
        // **不能再用 id: 键在同一个账号值上**：冷启动 selectedAccount 从 nil 翻转到账号时，
        // 旧实例的 .task(id:) 会先于父级换代重启一次，把加载跑进 VM 的非结构化 Task（拆视图
        // 也取消不掉），新实例又带全新 VM 再跑一遍 → 概览页全部请求成对翻倍（logs-3 已坐实）。
        .task {
            await loadAssets()
        }
        .task {
            await loadUsage()
        }
        .task {
            await loadInventory()
        }
        // 旧的 CachedZone.pinned → 统一置顶 store 的一次性迁移：域名缓存到位后才迁（store 内按账号只做一次）
        .task(id: cachedZones.count) {
            pinnedStore.migrateZonePinsIfNeeded(
                accountId: currentAccountId,
                pinnedZoneIds: cachedZones.filter(\.pinned).map(\.id),
                hasZoneData: !cachedZones.isEmpty
            )
        }
        .onChange(of: accountPrefs.billingCycleDay) {
            Task { await loadUsage(force: true) }
        }
        .onChange(of: dayBoundaryRaw) {
            Task { await loadUsage(force: true) }
        }
        .onChange(of: auth.sessionsNeedingReauth) { old, new in
            // 重新授权成功（当前身份的「需重授权」标记被摘除）→ 立刻重拉全部数据
            if let sid = auth.currentSessionId, old.contains(sid), !new.contains(sid) {
                Task { await refreshAll() }
            }
        }
        .refreshable {
            await refreshAll()
        }
        .sheet(item: $usageDetail) { service in
            usageDetailSheet(service)
        }
        // 免费层点 Pro 资源（搜索结果 / 告警 / 已固定）的付费墙：
        // sheet 挂在透明宿主上，触发 / 收起都不重算本视图 body（见 paywallPresenter 注释）
        .background { PaywallSheetHost(presenter: paywallPresenter) }
    }

    /// 「需重新授权」引导：说明 + 一键重授权（同身份原地换令牌），成功摘标后自动重拉
    private func reauthBanner(sessionId: UUID) -> some View {
        VStack(spacing: 10) {
            Label("登录授权已失效，无法自动续期", systemImage: "key.slash")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)
            ReauthorizeButton(sessionId: sessionId, scopes: [])
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassIsland(cornerRadius: OCLayout.chipRadius)
    }

    /// 下拉刷新 / 顶部失败提示重试：强制重拉账号、资产、流量、用量、资源清单
    private func refreshAll() async {
        await session.ensureAccounts()
        await loadAssets(force: true)
        await loadTraffic(force: true)
        await loadUsage(force: true)
        await loadInventory(force: true)
    }

    /// sheet 关闭后再 push，避免「关面板」与「入栈」同帧打架
    private func dispatchPendingRoute() {
        guard let route = pendingRoute else { return }
        pendingRoute = nil
        openResource(route)
    }

    /// 打开一个资源（命令搜索 / 告警中心 / 已固定区共用的唯一出口）。
    ///
    /// 与 Android `OrangeCloudRoot.openResource` 同口径：**能搜到，点进去撞付费墙**——
    /// 免费层点 R2 / D1 / KV / Tunnel 不入栈，改弹 PaywallView（复用 ProFeature 的场景文案，
    /// 与存储 Tab 整页闸门、Tunnel 入口闸门是同一套）。域名 / Workers 免费，照常 push。
    ///
    /// 闸门只在「赋值 route 之前」判断，不动栈根的值式 navdest 结构（导航铁律）。
    private func openResource(_ route: DashboardResourceRoute) {
        if let feature = route.proFeature, !entitlements.isPro {
            paywallPresenter.feature = feature
        } else {
            resourceRoute = route
        }
    }

    /// 资源清单（R2 / D1 / KV / Tunnel）惰性补拉：**免费层也拉**，让搜索结果与告警覆盖全部资源
    /// （点进去才撞付费墙，见 openResource）；各类仍按 scope 分别门控，缺权限就跳过该类。
    private func loadInventory(force: Bool = false) async {
        guard let accountId = session.selectedAccount?.id else { return }
        await viewModel.loadInventory(
            accountId: accountId,
            canReadR2: auth.hasScope("workers-r2.read"),
            canReadD1: auth.hasScope("d1.read"),
            canReadKV: auth.hasScope("workers-kv-storage.read"),
            canReadTunnel: auth.hasScope("argotunnel.read"),
            force: force
        )
    }

    /// 首屏资产统计：域名 / Workers / DNS 数量不等用户进入对应页面，进 Dashboard 就拉
    private func loadAssets(force: Bool = false) async {
        guard let account = session.selectedAccount else { return }
        await viewModel.loadAssets(
            accountId: account.id,
            accountName: account.name,
            canReadWorkers: auth.hasScope("workers-scripts.read"),
            canReadDNS: auth.hasScope("dns.read"),
            context: modelContext,
            force: force
        )
    }

    private func loadTraffic(force: Bool = false) async {
        guard auth.hasScope("analytics.read") else { return }
        await viewModel.loadTraffic(
            zones: displayZones.map { (id: $0.id, name: $0.name) },
            accountId: session.selectedAccount?.id,
            force: force
        )
    }

    private func loadUsage(force: Bool = false) async {
        guard auth.hasScope("account-analytics.read"),
              let accountId = session.selectedAccount?.id else { return }
        await viewModel.loadUsage(
            accountId: accountId,
            fallbackPeriodStart: BillingCycle.periodStart(billingDay: prefsStore.prefs(for: accountId).billingCycleDay),
            force: force
        )
        writeUsageWidgetSnapshot()
    }

    /// 用量快照 → App Group（用量 Widget 数据源；按服务分组，额度口径与页面一致）
    private func writeUsageWidgetSnapshot() {
        guard let usage = viewModel.usage else { return }
        let workersPaid = effectiveWorkersPaid
        let label = workersPaid ? monthlyLabel : String(localized: "今日")

        func compact(_ value: Int) -> String {
            value.formatted(.number.notation(.compactName))
        }
        func bytes(_ value: Int) -> String {
            Int64(value).ocBytes
        }

        var services: [WidgetUsageService] = []

        var workersRows = [
            WidgetUsageRow(
                title: String(localized: "请求 · \(label)"),
                used: workersPaid ? usage.workersRequestsMonth : usage.workersRequestsToday,
                quota: workersPaid ? 10_000_000 : 100_000,
                valueText: compact(workersPaid ? usage.workersRequestsMonth : usage.workersRequestsToday)
            ),
        ]
        if workersPaid, let monthUs = usage.cpuTimeMonthUs {
            workersRows.append(WidgetUsageRow(
                title: "CPU · \(label)",
                used: Int(monthUs / 1000), quota: 30_000_000,
                valueText: compact(Int(monthUs / 1000)) + " ms"
            ))
        }
        services.append(WidgetUsageService(id: "workers", name: "Workers", rows: workersRows))

        // R2：付费档无硬上限，但仍以"包含额度"为参考画条
        services.append(WidgetUsageService(id: "r2", name: "R2", rows: [
            WidgetUsageRow(title: String(localized: "存储"), used: usage.r2StorageBytes, quota: 10_000_000_000,
                           valueText: bytes(usage.r2StorageBytes)),
            WidgetUsageRow(title: String(localized: "A 类操作 · \(monthlyLabel)"), used: usage.r2ClassAMonth, quota: 1_000_000,
                           valueText: compact(usage.r2ClassAMonth)),
            WidgetUsageRow(title: String(localized: "B 类操作 · \(monthlyLabel)"), used: usage.r2ClassBMonth, quota: 10_000_000,
                           valueText: compact(usage.r2ClassBMonth)),
        ]))

        if let d1 = usage.d1Usage {
            var rows = [
                WidgetUsageRow(title: String(localized: "行读取 · \(label)"),
                               used: workersPaid ? d1.rowsReadPeriod : d1.rowsReadToday,
                               quota: workersPaid ? 25_000_000_000 : 5_000_000,
                               valueText: compact(workersPaid ? d1.rowsReadPeriod : d1.rowsReadToday)),
                WidgetUsageRow(title: String(localized: "行写入 · \(label)"),
                               used: workersPaid ? d1.rowsWrittenPeriod : d1.rowsWrittenToday,
                               quota: workersPaid ? 50_000_000 : 100_000,
                               valueText: compact(workersPaid ? d1.rowsWrittenPeriod : d1.rowsWrittenToday)),
            ]
            if let storage = usage.d1StorageBytes {
                rows.append(WidgetUsageRow(title: String(localized: "存储"), used: storage, quota: 5_000_000_000,
                                           valueText: bytes(storage)))
            }
            services.append(WidgetUsageService(id: "d1", name: "D1", rows: rows))
        }

        if let kv = usage.kvUsage {
            var rows = [
                WidgetUsageRow(title: String(localized: "读取 · \(label)"),
                               used: workersPaid ? kv.readsPeriod : kv.readsToday,
                               quota: workersPaid ? 10_000_000 : 100_000,
                               valueText: compact(workersPaid ? kv.readsPeriod : kv.readsToday)),
                WidgetUsageRow(title: String(localized: "写入 · \(label)"),
                               used: workersPaid ? kv.writesPeriod : kv.writesToday,
                               quota: workersPaid ? 1_000_000 : 1_000,
                               valueText: compact(workersPaid ? kv.writesPeriod : kv.writesToday)),
            ]
            if let storage = usage.kvStorageBytes {
                rows.append(WidgetUsageRow(title: String(localized: "存储"), used: storage, quota: 1_000_000_000,
                                           valueText: bytes(storage)))
            }
            services.append(WidgetUsageService(id: "kv", name: "KV", rows: rows))
        }

        WidgetDataStore.saveUsage(WidgetUsageData(services: services, updatedAt: Date()), accountId: currentAccountId)
        WidgetCenter.shared.reloadTimelines(ofKind: "UsageWidget")
    }

    // MARK: - 问候区（晨昏头部：日期 + 时段问候 + 健康一句话 + 地平线弧，每分钟自走）

    private func timeGreeting(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 0..<5:   String(localized: "夜深了")
        case 5..<11:  String(localized: "早上好")
        case 11..<13: String(localized: "中午好")
        case 13..<18: String(localized: "下午好")
        default:      String(localized: "晚上好")
        }
    }

    private var healthLine: String {
        guard !cachedZones.isEmpty else {
            return viewModel.isLoadingAssets
                ? String(localized: "正在同步域名与资产…")
                : String(localized: "当前账号还没有域名")
        }
        if activeCount == cachedZones.count {
            return String(localized: "\(cachedZones.count) 个域名全部正常")
        }
        return String(localized: "\(activeCount)/\(cachedZones.count) 个域名已启用")
    }

    private var daybreakHeader: some View {
        TimelineView(.everyMinute) { context in
            if vSizeClass == .compact {
                compactHeader(at: context.date)
            } else {
                regularHeader(at: context.date)
            }
        }
        .padding(.top, vSizeClass == .compact ? 0 : 4)
    }

    private func regularHeader(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(date, format: .dateTime.month().day().weekday(.wide))
                .font(.footnote)
                .foregroundStyle(.secondary)
            greeting(at: date, font: .system(.largeTitle, design: .rounded, weight: .bold))
            if session.selectedAccount != nil {
                Text(healthLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HorizonArc(date: date)
                .frame(height: 44)
                .padding(.top, 2)
        }
    }

    /// 矮画布排法：日期整行省掉（状态栏本来就有），健康摘要挪到问候语同行的尾部，
    /// 地平线弧压到 20pt——常规排法在 440pt 高度下要吃掉半屏，只剩一行宫格露出来。
    private func compactHeader(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                greeting(at: date, font: .system(.title2, design: .rounded, weight: .bold))
                if session.selectedAccount != nil {
                    Text(healthLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HorizonArc(date: date)
                .frame(height: 20)
        }
    }

    @ViewBuilder
    private func greeting(at date: Date, font: Font) -> some View {
        if let account = session.selectedAccount {
            Text("\(timeGreeting(at: date))，\(account.name)")
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else if session.isLoadingAccounts {
            Text("加载账号中…")
                .font(font)
                .redacted(reason: .placeholder)
        } else {
            Text("未选择账号")
                .font(font)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 右上角账号头像菜单

    private var accountMenu: some View {
        Menu {
            // 登录身份（在设置里「添加账号」加的，多个时点这里直接切换）
            Section {
                ForEach(auth.sessions) { identity in
                    Button {
                        if identity.id != auth.currentSessionId {
                            auth.switchSession(identity.id)
                        }
                    } label: {
                        if identity.id == auth.currentSessionId {
                            Label(identity.label, systemImage: "checkmark")
                        } else {
                            Text(identity.label)
                        }
                    }
                }
            }
            // 当前身份下的多个 Cloudflare 账号
            if session.accounts.count > 1 {
                Section("Cloudflare 账号") {
                    ForEach(session.accounts) { account in
                        Button {
                            session.selectedAccount = account
                        } label: {
                            if account.id == session.selectedAccount?.id {
                                Label(account.name, systemImage: "checkmark")
                            } else {
                                Text(account.name)
                            }
                        }
                    }
                }
            }
        } label: {
            Text(String(session.selectedAccount?.name.first ?? "?").uppercased())
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1, green: 0.65, blue: 0.31), .ocOrangePressed],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .symbolEffect(.bounce, value: session.selectedAccount?.id)
        }
        .safePopoverTip(accountSwitchTip, enabled: !usesInlineTip)
        .accessibilityLabel("切换账号")
        .accessibilityValue(session.selectedAccount?.name ?? "")
    }

    // MARK: - 资产指标格（2×2）

    /// 账号切换提示走页内 `TipView` 还是锚在工具栏头像上的 popover。
    /// 只有「宽且高」的画布（iPad 一档）才换页内：那种形态顶部是 Tab 胶囊，
    /// popover 会横着压住它。横屏矮画布（956×440）的 Tab 栏在底部、不存在遮挡，
    /// 而 440pt 高度里再插一张提示卡要吃掉近四分之一屏，那里继续用 popover 更划算。
    private var usesInlineTip: Bool {
        hSizeClass == .regular && vSizeClass != .compact
    }

    /// 资产指标格的列数：窄画布 2 列（2×2，原样），宽画布 4 列拉成一行。
    /// 卡片是内容高、宽度随格子摊开——2 列摆在 672pt 可读宽里每张 314pt、长宽比 3.5:1，
    /// 数字孤零零漂在横条里；4 列每张 151pt，比例回到 iPhone 上 1.9:1 的样子。
    private var statColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: OCLayout.islandGap),
            count: hSizeClass == .regular ? 4 : 2
        )
    }

    private var statIslands: some View {
        LazyVGrid(columns: statColumns, spacing: OCLayout.islandGap) {
            StatIsland(
                label: String(localized: "域名"),
                value: cachedZones.count,
                sub: String(localized: "\(activeCount) 已启用")
            )
            StatIsland(
                label: "Workers",
                value: cachedWorkers.count,
                sub: String(localized: "已部署脚本")
            )
            StatIsland(
                label: String(localized: "DNS 记录"),
                value: dnsRecordCount,
                sub: viewModel.dnsRecordTotal != nil
                    ? String(localized: "全部域名")
                    : String(localized: "已同步域名")
            )
            fourthStatIsland
        }
    }

    /// 指标格骨架：首屏缓存为空且资产统计进行中时展示
    private var statSkeleton: some View {
        // 列数跟 statIslands 走同一个 statColumns，否则加载完会从 2×2 跳成一行、闪一下
        LazyVGrid(columns: statColumns, spacing: OCLayout.islandGap) {
            ForEach(0..<4, id: \.self) { index in
                VStack(alignment: .leading, spacing: 7) {
                    SkeletonBlock(width: 40 + CGFloat((index * 17) % 26), height: 10)
                    SkeletonBlock(width: 46, height: 24, cornerRadius: 7)
                    SkeletonBlock(width: 64, height: 9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OCLayout.islandPadding)
                .glassIsland(cornerRadius: OCLayout.chipRadius)
            }
        }
        .skeletonPulse()
    }

    /// 第四格：优先 R2 存储桶数，其次 D1 数据库数，都不可用时回退已启用域名数
    @ViewBuilder
    private var fourthStatIsland: some View {
        if let buckets = viewModel.r2BucketCount {
            StatIsland(label: "R2", value: buckets, sub: String(localized: "存储桶"))
        } else if let databases = viewModel.d1DatabaseCount {
            StatIsland(label: "D1", value: databases, sub: String(localized: "数据库"))
        } else {
            StatIsland(label: String(localized: "已启用"), value: activeCount, sub: String(localized: "活跃域名"))
        }
    }

    // MARK: - 用量

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("用量")
                    .font(.title3.bold())
                Spacer()
                if viewModel.billing != nil {
                    // 订阅接口可用：套餐与周期自动识别，无需手动设置
                    Label(planSummary, systemImage: "checkmark.seal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    // 手动设置（OAuth 无 billing scope 时的兜底）
                    Menu {
                        Section("Workers 套餐") {
                            Picker("Workers 套餐", selection: workersPlanPaidBinding) {
                                Text("Free").tag(false)
                                Text("Paid").tag(true)
                            }
                        }
                        Section("R2 套餐") {
                            Picker("R2 套餐", selection: r2PlanPaidBinding) {
                                Text("Free").tag(false)
                                Text("Paid").tag(true)
                            }
                        }
                        Section("账单日（用量周期起点）") {
                            Picker("账单日", selection: billingCycleDayBinding) {
                                ForEach(1...28, id: \.self) { day in
                                    Text(day == 1 ? String(localized: "1 日（自然月）") : String(localized: "\(day) 日")).tag(day)
                                }
                            }
                        }
                    } label: {
                        Label(planSummary, systemImage: "slider.horizontal.3")
                            .font(.subheadline)
                            .foregroundStyle(Color.ocOrangeText)
                    }
                }
            }

            if !auth.hasScope("account-analytics.read") {
                Label("需要「流量分析」权限才能展示账号用量", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                    .glassIsland(cornerRadius: OCLayout.chipRadius)
            } else if let usage = viewModel.usage {
                if viewModel.accountAnalyticsPartial {
                    // 部分时间窗被 authz 挡（免费账号常见）：数据照常显示，
                    // 只说明缺的那部分为 0 是权限所致，不是加载失败
                    Label("部分周期数据需付费版 Cloudflare 账号，显示为 0 的项非加载失败", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                usageGrid(usage)
            } else if viewModel.accountAnalyticsUnavailable {
                accountAnalyticsUnavailableCard
            } else if viewModel.usageLoadFailed {
                Label("用量加载失败，下拉刷新重试", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                    .glassIsland(cornerRadius: OCLayout.chipRadius)
            } else {
                usageSkeleton
            }
        }
    }

    /// 账户级数据无权限（免费账号常态）——中性提示 + 付费说明，区别于「加载失败可重试」
    private var accountAnalyticsUnavailableCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("此账号暂无账户级数据查询权限")
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
            Text("Workers / R2 / D1 / KV 用量通常需要付费版 Cloudflare 账号；域名流量分析不受影响。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .glassIsland(cornerRadius: OCLayout.chipRadius)
    }

    /// 用量宫格骨架：与真实瓦片同形状的 2×2 占位
    private var usageSkeleton: some View {
        let columns = [
            GridItem(.flexible(), spacing: OCLayout.islandGap),
            GridItem(.flexible(), spacing: OCLayout.islandGap),
        ]
        return LazyVGrid(columns: columns, spacing: OCLayout.islandGap) {
            ForEach(0..<4, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBlock(width: 80 + CGFloat((index * 23) % 30), height: 10)
                    HStack(spacing: 9) {
                        Circle()
                            .stroke(.quaternary, lineWidth: 4)
                            .frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 5) {
                            SkeletonBlock(width: 56, height: 13)
                            SkeletonBlock(width: 40, height: 9)
                        }
                    }
                    .frame(minHeight: 36, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .glassIsland(cornerRadius: OCLayout.chipRadius)
            }
        }
        .skeletonPulse()
    }

    private var planSummary: String {
        "W \(effectiveWorkersPaid ? "Paid" : "Free") · R2 \(effectiveR2Paid ? "Paid" : "Free")"
    }

    // MARK: - 用量宫格（每个服务一格环形仪表，点击看明细）

    private func usageGrid(_ usage: AccountUsage) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: OCLayout.islandGap),
            GridItem(.flexible(), spacing: OCLayout.islandGap),
        ]
        return LazyVGrid(columns: columns, spacing: OCLayout.islandGap) {
            Button { usageDetail = .workers } label: { workersTile(usage) }
                .buttonStyle(.plain)
            Button { usageDetail = .r2 } label: { r2Tile(usage) }
                .buttonStyle(.plain)
            if usage.d1Usage != nil || usage.d1StorageBytes != nil {
                Button { usageDetail = .d1 } label: { d1Tile(usage) }
                    .buttonStyle(.plain)
            }
            if usage.kvUsage != nil || usage.kvStorageBytes != nil {
                Button { usageDetail = .kv } label: { kvTile(usage) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func compactText(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }

    /// 一个服务有多个额度指标时，瓦片展示消耗比例最高的那个（瓶颈指标）
    private func tile(_ title: String, from candidates: [GaugedMetric]) -> UsageServiceTile {
        guard let top = candidates.max(by: { $0.ratio < $1.ratio }) else {
            return UsageServiceTile(title: title, context: "—", valueText: "—", quotaText: nil, ratio: nil)
        }
        return UsageServiceTile(
            title: title,
            context: top.context,
            valueText: top.valueText,
            quotaText: top.quotaText,
            ratio: top.ratio
        )
    }

    private func workersTile(_ usage: AccountUsage) -> UsageServiceTile {
        let label = effectiveWorkersPaid ? monthlyLabel : String(localized: "今日")
        let requests = effectiveWorkersPaid ? usage.workersRequestsMonth : usage.workersRequestsToday
        let requestQuota = effectiveWorkersPaid ? 10_000_000 : 100_000
        var candidates = [
            GaugedMetric(
                context: String(localized: "请求 · \(label)"),
                valueText: compactText(requests),
                quotaText: "/ \(compactText(requestQuota))",
                ratio: Double(requests) / Double(requestQuota)
            ),
        ]
        if effectiveWorkersPaid, let cpuUs = usage.cpuTimeMonthUs {
            let cpuMs = Int(cpuUs / 1000)
            candidates.append(GaugedMetric(
                context: "CPU · \(label)",
                valueText: compactText(cpuMs) + " ms",
                quotaText: "/ 30M ms",
                ratio: Double(cpuMs) / 30_000_000
            ))
        }
        return tile("Workers", from: candidates)
    }

    private func r2Tile(_ usage: AccountUsage) -> UsageServiceTile {
        // A/B 类操作额度两档都有：免费档是免费额度，付费档是账期包含额度（1M / 10M）
        var candidates = [
            GaugedMetric(
                context: String(localized: "A 类 · \(monthlyLabel)"),
                valueText: compactText(usage.r2ClassAMonth),
                quotaText: "/ 1M",
                ratio: Double(usage.r2ClassAMonth) / 1_000_000
            ),
            GaugedMetric(
                context: String(localized: "B 类 · \(monthlyLabel)"),
                valueText: compactText(usage.r2ClassBMonth),
                quotaText: "/ 10M",
                ratio: Double(usage.r2ClassBMonth) / 10_000_000
            ),
        ]
        if !effectiveR2Paid {
            candidates.append(GaugedMetric(
                context: String(localized: "存储"),
                valueText: Int64(usage.r2StorageBytes).ocBytes,
                quotaText: "/ 10 GB",
                ratio: Double(usage.r2StorageBytes) / 10_000_000_000
            ))
        }
        return tile("R2", from: candidates)
    }

    private func d1Tile(_ usage: AccountUsage) -> UsageServiceTile {
        let label = effectiveWorkersPaid ? monthlyLabel : String(localized: "今日")
        var candidates: [GaugedMetric] = []
        if let d1 = usage.d1Usage {
            let reads = effectiveWorkersPaid ? d1.rowsReadPeriod : d1.rowsReadToday
            let readQuota = effectiveWorkersPaid ? 25_000_000_000 : 5_000_000
            let writes = effectiveWorkersPaid ? d1.rowsWrittenPeriod : d1.rowsWrittenToday
            let writeQuota = effectiveWorkersPaid ? 50_000_000 : 100_000
            candidates.append(GaugedMetric(
                context: String(localized: "行读取 · \(label)"),
                valueText: compactText(reads),
                quotaText: "/ \(compactText(readQuota))",
                ratio: Double(reads) / Double(readQuota)
            ))
            candidates.append(GaugedMetric(
                context: String(localized: "行写入 · \(label)"),
                valueText: compactText(writes),
                quotaText: "/ \(compactText(writeQuota))",
                ratio: Double(writes) / Double(writeQuota)
            ))
        }
        if let storage = usage.d1StorageBytes {
            candidates.append(GaugedMetric(
                context: String(localized: "存储"),
                valueText: Int64(storage).ocBytes,
                quotaText: "/ 5 GB",
                ratio: Double(storage) / 5_000_000_000
            ))
        }
        return tile("D1", from: candidates)
    }

    private func kvTile(_ usage: AccountUsage) -> UsageServiceTile {
        let label = effectiveWorkersPaid ? monthlyLabel : String(localized: "今日")
        var candidates: [GaugedMetric] = []
        if let kv = usage.kvUsage {
            let reads = effectiveWorkersPaid ? kv.readsPeriod : kv.readsToday
            let readQuota = effectiveWorkersPaid ? 10_000_000 : 100_000
            let writes = effectiveWorkersPaid ? kv.writesPeriod : kv.writesToday
            let writeQuota = effectiveWorkersPaid ? 1_000_000 : 1_000
            candidates.append(GaugedMetric(
                context: String(localized: "读取 · \(label)"),
                valueText: compactText(reads),
                quotaText: "/ \(compactText(readQuota))",
                ratio: Double(reads) / Double(readQuota)
            ))
            candidates.append(GaugedMetric(
                context: String(localized: "写入 · \(label)"),
                valueText: compactText(writes),
                quotaText: "/ \(compactText(writeQuota))",
                ratio: Double(writes) / Double(writeQuota)
            ))
        }
        if let storage = usage.kvStorageBytes {
            candidates.append(GaugedMetric(
                context: String(localized: "存储"),
                valueText: Int64(storage).ocBytes,
                quotaText: "/ 1 GB",
                ratio: Double(storage) / 1_000_000_000
            ))
        }
        return tile("KV", from: candidates)
    }

    // MARK: - 用量明细 sheet

    private func usageDetailSheet(_ service: UsageService) -> some View {
        NavigationStack {
            ScrollView {
                if let usage = viewModel.usage {
                    VStack(spacing: 14) {
                        switch service {
                        case .workers: workersRows(usage)
                        case .r2:      r2Rows(usage)
                        case .d1:      d1Rows(usage)
                        case .kv:      kvRows(usage)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(service.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 分组内容行

    @ViewBuilder
    private func workersRows(_ usage: AccountUsage) -> some View {
            if effectiveWorkersPaid {
                UsageRow(
                    icon: "bolt",
                    title: String(localized: "Workers 请求 · \(monthlyLabel)"),
                    used: usage.workersRequestsMonth,
                    quota: 10_000_000
                )
            } else {
                UsageRow(
                    icon: "bolt",
                    title: String(localized: "Workers 请求 · 今日"),
                    used: usage.workersRequestsToday,
                    quota: 100_000
                )
            }

            if effectiveWorkersPaid, let monthUs = usage.cpuTimeMonthUs {
                // Workers Standard 含 30M CPU-ms / 计费周期
                UsageRow(
                    icon: "cpu",
                    title: "Workers CPU · \(monthlyLabel)",
                    valueText: "\(Int(monthUs / 1000).formatted(.number.notation(.compactName))) / 30M ms",
                    used: Int(monthUs / 1000),
                    quota: 30_000_000
                )
            } else if let todayUs = usage.cpuTimeTodayUs {
                // Free 无 CPU 月度额度（单次 10ms 上限），展示今日合计
                UsageRow(
                    icon: "cpu",
                    title: String(localized: "Workers CPU · 今日"),
                    valueText: Int(todayUs / 1000).formatted(.number.notation(.compactName)) + " ms",
                    used: nil, quota: nil
                )
            } else {
                // CPU 总量字段不可用时回退单次分位
                UsageRow(
                    icon: "cpu",
                    title: String(localized: "Workers CPU · 单次"),
                    valueText: cpuText(usage),
                    used: nil, quota: nil
                )
            }
    }

    @ViewBuilder
    private func r2Rows(_ usage: AccountUsage) -> some View {
            UsageRow(
                icon: "externaldrive",
                title: String(localized: "R2 存储"),
                valueText: Int64(usage.r2StorageBytes).ocBytes
                    + (effectiveR2Paid ? "" : " / 10 GB"),
                used: effectiveR2Paid ? nil : usage.r2StorageBytes,
                quota: effectiveR2Paid ? nil : 10_000_000_000
            )

            // 操作额度两档都有：免费档是免费额度，付费档是账期包含额度
            UsageRow(
                icon: "arrow.up.circle",
                title: String(localized: "R2 A 类操作 · \(monthlyLabel)"),
                used: usage.r2ClassAMonth,
                quota: 1_000_000
            )

            UsageRow(
                icon: "arrow.down.circle",
                title: String(localized: "R2 B 类操作 · \(monthlyLabel)"),
                used: usage.r2ClassBMonth,
                quota: 10_000_000
            )
    }

    @ViewBuilder
    private func d1Rows(_ usage: AccountUsage) -> some View {
            // D1（额度跟随 Workers 套餐：Free 按日，Paid 按计费周期）
            if let d1 = usage.d1Usage {
                if effectiveWorkersPaid {
                    UsageRow(
                        icon: "eye",
                        title: String(localized: "D1 行读取 · \(monthlyLabel)"),
                        used: d1.rowsReadPeriod,
                        quota: 25_000_000_000
                    )
                    UsageRow(
                        icon: "pencil",
                        title: String(localized: "D1 行写入 · \(monthlyLabel)"),
                        used: d1.rowsWrittenPeriod,
                        quota: 50_000_000
                    )
                } else {
                    UsageRow(
                        icon: "eye",
                        title: String(localized: "D1 行读取 · 今日"),
                        used: d1.rowsReadToday,
                        quota: 5_000_000
                    )
                    UsageRow(
                        icon: "pencil",
                        title: String(localized: "D1 行写入 · 今日"),
                        used: d1.rowsWrittenToday,
                        quota: 100_000
                    )
                }
            }

            if let d1Storage = usage.d1StorageBytes {
                UsageRow(
                    icon: "cylinder",
                    title: String(localized: "D1 存储"),
                    valueText: Int64(d1Storage).ocBytes + " / 5 GB",
                    used: d1Storage,
                    quota: 5_000_000_000
                )
            }
    }

    @ViewBuilder
    private func kvRows(_ usage: AccountUsage) -> some View {
            // KV（额度跟随 Workers 套餐：Free 按日，Paid 按计费周期）
            if let kv = usage.kvUsage {
                if effectiveWorkersPaid {
                    UsageRow(
                        icon: "key",
                        title: String(localized: "KV 读取 · \(monthlyLabel)"),
                        used: kv.readsPeriod,
                        quota: 10_000_000
                    )
                    UsageRow(
                        icon: "key.fill",
                        title: String(localized: "KV 写入 · \(monthlyLabel)"),
                        used: kv.writesPeriod,
                        quota: 1_000_000
                    )
                } else {
                    UsageRow(
                        icon: "key",
                        title: String(localized: "KV 读取 · 今日"),
                        used: kv.readsToday,
                        quota: 100_000
                    )
                    UsageRow(
                        icon: "key.fill",
                        title: String(localized: "KV 写入 · 今日"),
                        used: kv.writesToday,
                        quota: 1_000
                    )
                }
            }

            if let kvStorage = usage.kvStorageBytes {
                UsageRow(
                    icon: "square.grid.2x2",
                    title: String(localized: "KV 存储"),
                    valueText: Int64(kvStorage).ocBytes + " / 1 GB",
                    used: kvStorage,
                    quota: 1_000_000_000
                )
            }
    }

    private func cpuText(_ usage: AccountUsage) -> String {
        guard let p50 = usage.cpuP50Us else { return "—" }
        let p50ms = p50 / 1000
        if let p99 = usage.cpuP99Us {
            return String(format: "P50 %.1f ms · P99 %.1f ms", p50ms, p99 / 1000)
        }
        return String(format: "P50 %.1f ms", p50ms)
    }

    // MARK: - 域名卡片

    private var zonesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("域名")
                    .font(.title3.bold())
                Spacer()
                Button("全部") {
                    AppRouter.shared.pendingModule = .zones
                }
                .font(.subheadline)
                .foregroundStyle(Color.ocOrangeText)
            }

            if cachedZones.isEmpty && viewModel.isLoadingAssets {
                SkeletonIslandRows(rows: 3, icon: .circle(32))
            } else if cachedZones.isEmpty {
                Text("下拉刷新后，这里会展示域名概览")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                    .glassIsland(cornerRadius: OCLayout.chipRadius)
            } else {
                VStack(spacing: 0) {
                    ForEach(displayZones) { zone in
                        NavigationLink(value: zone) {
                            DashboardZoneCard(
                                zone: zone,
                                points: viewModel.trafficByZone[zone.id]?.points
                            )
                        }
                        .buttonStyle(.plain)

                        if zone.id != displayZones.last?.id {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .glassIsland()

                if pinnedZoneIds.isEmpty {
                    Label("在域名详情页点图钉，可固定想在首页看到的域名", systemImage: "pin")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    // MARK: - 已固定（域名以外：Workers / R2 / D1 / KV / Tunnel）

    @ViewBuilder
    private var pinnedResourcesSection: some View {
        let pins = pinnedNonZoneResources
        if !pins.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("已固定")
                        .font(.title3.bold())
                    Spacer()
                    Button("搜索") { showSearch = true }
                        .font(.subheadline)
                        .foregroundStyle(Color.ocOrangeText)
                }
                pinnedIsland(pins)
            }
            .islandReveal(5)
        }
    }

    private func pinnedIsland(_ pins: [PinnedResource]) -> some View {
        // 标题 / 副标题一律现查（持久化里只有 type + id），资源改名后固定依然有效
        let itemsById = Dictionary(resourceItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return VStack(spacing: 0) {
            ForEach(pins) { pin in
                pinnedRow(pin, item: itemsById[pin.id])
                if pin.id != pins.last?.id {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .glassIsland()
    }

    @ViewBuilder
    private func pinnedRow(_ pin: PinnedResource, item: DashboardResourceItem?) -> some View {
        if let item {
            Button {
                openResource(item.route)
            } label: {
                PinnedResourceRow(
                    type: item.type,
                    title: item.title,
                    subtitle: "\(item.type.label) · \(item.subtitle)",
                    resolved: true
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("取消固定", systemImage: "star.slash", role: .destructive) {
                    pinnedStore.unpin(pin, accountId: currentAccountId)
                }
            }
        } else {
            // 资源查不到（已删除 / 该类清单未加载 / 缺权限）：显示标识本身，并给取消固定的出口
            HStack(spacing: 0) {
                PinnedResourceRow(
                    type: pin.type,
                    title: pin.resourceId,
                    subtitle: String(localized: "\(pin.type.label) · 未找到该资源"),
                    resolved: false
                )
                Button {
                    pinnedStore.unpin(pin, accountId: currentAccountId)
                } label: {
                    Image(systemName: "star.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消固定")
            }
            .padding(.trailing, 4)
        }
    }

    // MARK: - 网络（单行服务，胶囊形态，不配段落标题）

    private var networkSection: some View {
        VStack(spacing: 10) {
            // Tunnel 列表点行还要继续 push 详情/连接页：必须走值式 + 栈根 navdest，
            // eager NavigationLink(destination:) 的目的页内部再 push 在 iOS 17.0 会卡死。
            PermissionGatedValueLink(
                label: String(localized: "URL 扫描"),
                systemImage: "magnifyingglass.circle",
                requiredScope: "url-scanner.read",
                tint: .cyan,
                showsChevron: true,
                value: DashboardRoute.urlScanner
            )

            PermissionGatedValueLink(
                label: String(localized: "请求追踪"),
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                requiredScope: "request-tracer.read",
                tint: .indigo,
                showsChevron: true,
                value: DashboardRoute.requestTracer
            )

            PermissionGatedValueLink(
                label: String(localized: "域名注册"),
                systemImage: "checkmark.seal",
                requiredScope: "registrar-domains.read",
                tint: .orange,
                showsChevron: true,
                value: DashboardRoute.registrar
            )

            ProGatedValueLink(
                label: "Cloudflare Tunnel",
                systemImage: "arrow.triangle.2.circlepath",
                requiredScope: "argotunnel.read",
                feature: .tunnel,
                showsChevron: true,
                value: DashboardRoute.tunnels
            )
            Divider().padding(.leading, 44)
            // Turnstile 列表点行还要 push 详情：同 Tunnel，必须值式 + 栈根 navdest
            ProGatedValueLink(
                label: "Turnstile",
                systemImage: "checkmark.shield",
                requiredScope: "challenge-widgets.read",
                feature: .turnstile,
                showsChevron: true,
                value: DashboardRoute.turnstile
            )
            Divider().padding(.leading, 44)
            // Access / Gateway 同样必须值式：本岛（非 List 容器）里 eager 构造的目的页
            // 在 iOS 17.0 点击即整 App 冻结/看门狗杀（TF 用户实测，与 Tunnel 当年同症）。
            ProGatedValueLink(
                label: "Access 应用",
                systemImage: "lock.shield",
                requiredScope: "access.read",
                feature: .zeroTrust,
                showsChevron: true,
                value: DashboardRoute.accessApps
            )
            Divider().padding(.leading, 44)
            ProGatedValueLink(
                label: "Gateway 策略",
                systemImage: "shield.lefthalf.filled",
                requiredScope: "teams.read",
                feature: .zeroTrust,
                showsChevron: true,
                value: DashboardRoute.gatewayRules
            )
        }
        .padding(.horizontal, OCLayout.islandPadding + 2)
        .padding(.vertical, 12)
        .glassIsland(cornerRadius: 24)
    }

    // MARK: - Bulk Redirects（account 级）

    private var bulkRedirectsSection: some View {
        // 列表页内部还要 push 条目详情，且带 .searchable：eager 形态在 iOS 17.0 点击必卡死，走值式
        ProGatedValueLink(
            label: "Bulk Redirects",
            systemImage: "arrowshape.turn.up.right",
            requiredScope: "account-rule-lists.read",
            feature: .bulkRedirects,
            showsChevron: true,
            value: DashboardRoute.bulkRedirects
        )
        .padding(.horizontal, OCLayout.islandPadding + 2)
        .padding(.vertical, 12)
        .glassIsland(cornerRadius: 24)
    }

}

/// 概览页玻璃岛入口路由（走栈根 navdest，同 DevHubRoute）。本岛为非 List 容器，
/// eager `NavigationLink(destination:)` 在 iOS 17.0 点击即冻结（叶子目的页也一样），一律值式。
enum DashboardRoute: Hashable {
    case registrar
    case urlScanner
    case requestTracer
    case tunnels
    case tunnelConnect(Tunnel)
    case turnstile
    case accessApps
    case gatewayRules
    case bulkRedirects
}

// MARK: - 用量宫格的服务与瓦片

/// 单个有额度的指标（瓦片从中挑消耗比例最高者展示）
private nonisolated struct GaugedMetric {
    let context: String
    let valueText: String
    let quotaText: String
    let ratio: Double
}

/// 用量宫格里可点开明细的服务
private nonisolated enum UsageService: String, Identifiable {
    case workers, r2, d1, kv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workers: "Workers"
        case .r2:      "R2"
        case .d1:      "D1"
        case .kv:      "KV"
        }
    }
}

/// 服务瓦片：环形仪表对着额度，数值用主文本色
private struct UsageServiceTile: View {

    let title: String
    let context: String
    let valueText: String
    let quotaText: String?
    let ratio: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(title) · \(context)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 9) {
                if let ratio {
                    UsageRing(ratio: ratio)
                        .frame(width: 34, height: 34)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(valueText)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let quotaText {
                        Text(quotaText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            // 无环的瓦片（按量计费档）也保持同一指标区高度，四格等高
            .frame(minHeight: 36, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .contentShape(Rectangle())
        .glassIsland(cornerRadius: OCLayout.chipRadius)
    }
}

/// 额度环：随消耗比例从品牌橙渐变到警示红
private struct UsageRing: View {

    let ratio: Double

    private var color: Color {
        if ratio >= 0.9 { return .red }
        if ratio >= 0.7 { return .orange }
        return .ocOrange
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(max(ratio, 0.02), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 用量行（值 + 可选额度进度条）

private struct UsageRow: View {

    let icon: String
    let title: String
    var valueText: String? = nil
    let used: Int?
    let quota: Int?

    private var ratio: Double? {
        guard let used, let quota, quota > 0 else { return nil }
        return min(Double(used) / Double(quota), 1.0)
    }

    private var barColor: Color {
        guard let ratio else { return .ocOrange }
        if ratio >= 0.9 { return .red }
        if ratio >= 0.7 { return .orange }
        return .ocOrange
    }

    private var displayValue: String {
        if let valueText { return valueText }
        guard let used else { return "—" }
        let usedText = used.formatted(.number.notation(.compactName))
        if let quota {
            return "\(usedText) / \(quota.formatted(.number.notation(.compactName)))"
        }
        return usedText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(displayValue)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let ratio {
                ProgressView(value: ratio)
                    .tint(barColor)
                    .padding(.leading, 34)
            }
        }
    }
}

// MARK: - 域名信息卡（基础信息 + 24h 请求迷你图）

private struct DashboardZoneCard: View {

    let zone: CachedZone
    let points: [TrafficDataPoint]?

    private var statusText: String {
        switch zone.displayStatus {
        case "active":                  String(localized: "已启用")
        case "pending", "initializing": String(localized: "待激活")
        default:                        String(localized: "已暂停")
        }
    }

    private var totalRequests: Int? {
        guard let points, !points.isEmpty else { return nil }
        return points.reduce(0) { $0 + $1.requests }
    }

    /// 套餐取首词（"Free Website" → "Free"），与状态并进副标题
    private var planShort: String {
        zone.planName.components(separatedBy: " ").first ?? zone.planName
    }

    var body: some View {
        HStack(spacing: 10) {
            ZoneAvatar(domain: zone.name, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(zone.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(planShort) · \(statusText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            if let points, let total = totalRequests {
                VStack(alignment: .trailing, spacing: 2) {
                    Sparkline(values: points.map { Double($0.requests) }, color: .ocOrange)
                        .frame(width: 56, height: 16)
                        .accessibilityHidden(true)
                    Text(total.formatted(.number.notation(.compactName)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityLabel("24 小时请求")
                }
            }
            StatusDot(status: zone.displayStatus, size: 7)
                .accessibilityHidden(true)   // 状态已在副标题文字中
        }
        .padding(.horizontal, OCLayout.islandPadding)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - 已固定资源行（跨类型：Workers / R2 / D1 / KV / Tunnel）

private struct PinnedResourceRow: View {

    let type: PinnedResourceType
    let title: String
    let subtitle: String
    /// 能否在当前数据源里解析到该资源（否则弱化显示，不给跳转）
    let resolved: Bool

    var body: some View {
        HStack(spacing: 10) {
            TintIcon(systemImage: type.symbolName, color: type.tint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(resolved ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if resolved {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, OCLayout.islandPadding)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - 指标小岛（数字用主文本色，橙色只留给可交互元素）

private struct StatIsland: View {

    let label: String
    let value: Int
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let sub {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OCLayout.islandPadding)
        .glassIsland(cornerRadius: OCLayout.chipRadius)
    }
}

// MARK: - 付费墙弹层隔离宿主（issue #69）

/// 付费墙场景的独立状态载体：@Observable 按属性追踪，DashboardHomeView 只写不读，
/// 触发 / 收起弹层都不会牵连整个概览页 body 重算（那是弹层起帧顿挫的来源）。
@Observable
private final class DashboardPaywallPresenter {
    var feature: ProFeature?
}

/// 透明叶子视图，唯一读取 presenter.feature 的地方——sheet 起落只重算它自己
private struct PaywallSheetHost: View {

    @Bindable var presenter: DashboardPaywallPresenter

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .sheet(item: $presenter.feature) { feature in
                PaywallView(feature: feature)
            }
    }
}
