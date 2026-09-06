// 总览 Tab：身份/账户切换 + 域名概况 + 账号级模块入口（对齐 Android DashboardScreen）。
import { Account, Zone, DNSRecord } from '../../models/Models';
import { tabBarScroll } from '../common/PlatformCompat';
import { Routes, ZoneRouteParam, IdNameParam, NameParam } from '../../models/Routes';
import { AccountStore, accountStore } from '../../core/store/AccountStore';
import { authManager, AuthManager, AuthSessionMeta } from '../../core/auth/AuthManager';
import { ZoneService } from '../../services/ZoneService';
import { AnalyticsService } from '../../services/AnalyticsService';
import { WorkerService } from '../../services/WorkerService';
import { StorageService } from '../../services/StorageService';
import { DNSService } from '../../services/DNSService';
import { WorkerScript } from '../../models/WorkerModels';
import { R2Bucket, D1Database } from '../../models/StorageModels';
import { UsageService, AccountAnalyticsUnauthorizedError } from '../../services/UsageService';
import { AccountUsage } from '../../models/UsageModels';
import { Scopes } from '../../core/auth/Scopes';
import { TrafficDataPoint } from '../../models/AnalyticsModels';
import { formatBytes } from '../../core/util/Format';
import { WidgetSnapshot, WidgetSnapshotData } from '../../core/system/WidgetSnapshot';
import { GlobalContext } from '../../core/system/GlobalContext';
import { SkyPhaseColors } from '../../core/design/SkyPhase';
import { formatCount } from '../../core/util/Format';
import { BRAND_ORANGE, DANGER_RED, NavRow } from '../common/Components';
import { RidgeChart } from '../common/RidgeChart';
import { OCLayout, DaybreakHeader, StatIsland, SectionTitle, GlassIsland, RevealBox } from '../common/Daybreak';
import { entitlement, EntitlementStore } from '../../core/purchase/EntitlementStore';
import { requirePro } from '../paywall/ProGate';
import { ocSheet, ocSheetCompact } from '../common/Sheets';
import { ReauthBanner } from '../common/ReauthBanner';
import { ZoneAvatar, StatusDot, statusLabel } from '../common/ZoneComponents';
import { pinnedZones, PinnedZonesStore, pinnedResources, PinnedResourcesStore } from '../../core/system/AppPrefs';
import { KVNamespace } from '../../models/StorageModels';
import { Tunnel } from '../../models/AccountModels';
import { AccountModuleService } from '../../services/AccountModuleService';
import {
  buildAlerts, buildResourceItems, resourceMatches, resKindLabel, resKindSymbol,
  alertColor, DashAlert, ResKind, ResourceItem,
} from './DashboardResources';

interface DashEntry {
  symbol: Resource;
  title: string;
  subtitle: string;
  route: string;
  /// Pro 闸门场景名（空 = 免费可用）
  proFeature?: string;
}

/// 用量瓦片候选指标（含消耗比例，用于挑瓶颈指标）
interface UsageMetric {
  context: string;
  valueText: string;
  quotaText: string;
  ratio: number;
}

/// 用量瓦片展示模型（服务名 + 瓶颈指标）
interface UsageTile {
  title: string;
  context: string;
  valueText: string;
  quotaText: string;
  ratio: number;
}

/// 用量明细 sheet 的一行：指标名 + 已用/额度文本 + 消耗比例（ratio < 0 = 无额度指标，不画进度条）
interface UsageDetailRow {
  title: string;
  valueText: string;
  ratio: number;
}

const ACCOUNT_ENTRIES: DashEntry[] = [
  { symbol: $r('sys.symbol.wifi_router'), title: 'Tunnel', subtitle: 'Cloudflare Tunnel 连接状态', route: Routes.TUNNELS, proFeature: 'Cloudflare Tunnel' },
  { symbol: $r('sys.symbol.checkmark_circle'), title: '域名注册', subtitle: '到期日与自动续费', route: Routes.REGISTRAR },
  { symbol: $r('sys.symbol.discover'), title: '请求追踪', subtitle: '看请求命中了哪些规则', route: Routes.REQUEST_TRACER },
  { symbol: $r('sys.symbol.checkmark_shield'), title: 'URL 扫描', subtitle: '提交链接做安全扫描', route: Routes.URL_SCANNER },
  { symbol: $r('sys.symbol.lock_shield'), title: 'Zero Trust', subtitle: 'Access 应用与 Gateway 规则', route: Routes.ZERO_TRUST },
  { symbol: $r('sys.symbol.checkmark_shield_fill'), title: 'Turnstile', subtitle: '人机验证组件与密钥轮换', route: Routes.TURNSTILE, proFeature: 'Turnstile' },
  { symbol: $r('sys.symbol.arrow_right'), title: '批量重定向', subtitle: 'Bulk Redirects 列表与条目', route: Routes.REDIRECTS },
];

@ComponentV2
export struct DashboardView {
  @Require @Param pathStack: NavPathStack;
  @Local store: AccountStore = accountStore;
  /// 观察 authManager（重授权横幅显隐随 sessionsNeedingReauth 联动）
  @Local auth: AuthManager = authManager;
  /// 固定域名（共享可观察实例，详情页 toggle 后此处即时联动）
  @Local pins: PinnedZonesStore = pinnedZones;
  /// 观察权益：购买后 Pro 徽章即时消失
  @Local entitlements: EntitlementStore = entitlement;
  @Local zoneCount: number = -1;
  @Local activeZoneCount: number = 0;
  @Local requests24h: string = '—';
  /// 资产计数（对照 iOS statIslands）：-1=加载中/未取到
  @Local workersCount: number = -1;
  @Local dnsTotal: number = -1;
  @Local bucketCount: number = -1;
  @Local dbCount: number = -1;
  /// 全账号 24h 请求按钟点合计（24 点，供概览山脊 sparkline）
  @Local requestSeries: number[] = [];
  /// 当前账号域名列表（域名卡区数据源）
  @Local zones: Zone[] = [];
  /// 每 zone 的 24h 请求序列（复用山脊合并前的逐 zone 拉取结果，不多打接口）
  @Local zoneSeries: Map<string, number[]> = new Map();
  /// 每 zone 的 24h 请求合计
  @Local zoneTotals: Map<string, number> = new Map();
  /// 下拉刷新进行中
  @Local refreshing: boolean = false;
  /// 账号用量（用量宫格）：null=加载中，authz/失败态分别置位
  @Local usage: AccountUsage | null = null;
  @Local usageUnavailable: boolean = false;
  @Local usageFailed: boolean = false;
  /// 用量明细 sheet：点开的服务 key（'workers' | 'r2' | 'd1' | 'kv'）与显隐
  @Local usageSheetService: string = '';
  @Local usageSheetVisible: boolean = false;
  /// 跨类型置顶（Workers / R2 / D1 / KV / Tunnel；域名走 pinnedZones）
  @Local pinnedRes: PinnedResourcesStore = pinnedResources;
  /// 命令搜索：面板显隐与关键词
  @Local showSearch: boolean = false;
  @Local searchQuery: string = '';
  /// 可搜索 / 可固定的资源清单（域名与 Workers 随资产计数一起到手，
  /// KV 与 Tunnel 另行惰性补拉——它们不在指标岛里，否则白发两个请求）
  @Local workers: WorkerScript[] = [];
  @Local buckets: R2Bucket[] = [];
  @Local databases: D1Database[] = [];
  @Local namespaces: KVNamespace[] = [];
  @Local tunnels: Tunnel[] = [];
  private lastLoadedAccountId: string = '';
  private zoneService: ZoneService = new ZoneService();
  private analyticsService: AnalyticsService = new AnalyticsService();
  private usageService: UsageService = new UsageService();
  private workerService: WorkerService = new WorkerService();
  private storageService: StorageService = new StorageService();
  private dnsService: DNSService = new DNSService();
  private accountModuleService: AccountModuleService = new AccountModuleService();

  aboutToAppear(): void {
    this.reload();
  }

  @Monitor('store.selectedId')
  onAccountChange(): void {
    this.reload();
  }

  /// 拉取总览数据；返回的 Promise 在域名列表落地后 resolve（供下拉刷新收尾），
  /// 请求汇总 / 资产计数 / 用量继续在后台加载，永不 reject。
  private reload(): Promise<void> {
    return accountStore.loadIfNeeded().then((): Promise<void> => {
      const accountId = accountStore.selectedId;
      if (accountId === '') {
        return Promise.resolve();
      }
      this.zoneCount = -1;
      this.requests24h = '—';
      this.workersCount = -1;
      this.dnsTotal = -1;
      this.bucketCount = -1;
      this.dbCount = -1;
      // 切换账号时清空上一账号的域名卡数据，避免串号展示（同账号刷新保留旧数据防闪烁）
      if (this.lastLoadedAccountId !== accountId) {
        this.zones = [];
        this.zoneSeries = new Map();
        this.zoneTotals = new Map();
        this.lastLoadedAccountId = accountId;
      }
      // 固定域名 / 固定资源列表（按账号隔离）——独立加载
      pinnedZones.loadFor(accountId).catch(() => {
      });
      pinnedResources.loadFor(accountId).catch(() => {
      });
      // 搜索 / 置顶用的资源清单（切账号时先清空防串号）
      this.workers = [];
      this.buckets = [];
      this.databases = [];
      this.namespaces = [];
      this.tunnels = [];
      this.loadInventory(accountId);
      // 账号用量（账号级 GraphQL）——独立加载，不阻塞域名/请求汇总
      this.loadUsage(accountId);
      return this.zoneService.fetchZones(accountId).then((zones: Zone[]) => {
        this.zones = zones;
        this.zoneCount = zones.length;
        this.activeZoneCount = zones.filter((z: Zone) => z.status === 'active').length;
        this.writeWidgetSnapshot();
        // 后台跨 zone 汇总 24h 请求（不阻塞 UI），完成后回写卡片快照
        this.sumTodayRequests(zones);
        // 资产计数（Workers / DNS 记录 / R2 / D1，供指标岛，均不阻塞 UI）
        this.loadAssetCounts(accountId, zones);
      }).catch(() => {
        this.zoneCount = -2;
      });
    }).catch(() => {
    });
  }

  /// 跨全部 zone 汇总 24h 请求（并发，容错单 zone 失败）+ 按钟点合并出山脊序列；
  /// 同一批拉取结果按 zone 拆开留存（域名卡 sparkline 复用，不多打接口）
  private sumTodayRequests(zones: Zone[]): void {
    if (zones.length === 0) {
      this.requests24h = '0';
      this.requestSeries = [];
      this.zoneSeries = new Map();
      this.zoneTotals = new Map();
      this.writeWidgetSnapshot();
      return;
    }
    const jobs: Promise<TrafficDataPoint[]>[] = zones.map((z: Zone) =>
      this.analyticsService.zoneTraffic(z.id, '24h').catch(() => [] as TrafficDataPoint[]));
    Promise.all(jobs).then((all: TrafficDataPoint[][]) => {
      // 按 label（钟点）合并各 zone 的请求；同时按 zone 拆出各自序列与合计
      const byHour: Map<string, number> = new Map();
      const seriesByZone: Map<string, number[]> = new Map();
      const totalByZone: Map<string, number> = new Map();
      let total = 0;
      for (let i = 0; i < all.length; i++) {
        const points = all[i];
        const sorted = points.slice().sort((a: TrafficDataPoint, b: TrafficDataPoint) =>
          a.label.localeCompare(b.label));
        const zoneLine: number[] = [];
        let zoneTotal = 0;
        for (const p of sorted) {
          byHour.set(p.label, (byHour.get(p.label) ?? 0) + p.requests);
          total += p.requests;
          zoneLine.push(p.requests);
          zoneTotal += p.requests;
        }
        if (i < zones.length) {
          seriesByZone.set(zones[i].id, zoneLine);
          totalByZone.set(zones[i].id, zoneTotal);
        }
      }
      const labels = Array.from(byHour.keys()).sort();
      const series: number[] = [];
      for (const l of labels) {
        series.push(byHour.get(l) ?? 0);
      }
      this.requestSeries = series;
      this.zoneSeries = seriesByZone;
      this.zoneTotals = totalByZone;
      this.requests24h = formatCount(total);
      this.writeWidgetSnapshot();
    }).catch(() => {
    });
  }

  /// 资产计数（对照 iOS statIslands）：Workers 脚本数、全账号 DNS 记录数、R2 桶数、D1 库数。
  /// 每项独立并发、单项失败静默（保持 -1），均按 scope 门控，都不阻塞域名/请求汇总。
  private loadAssetCounts(accountId: string, zones: Zone[]): void {
    // Workers 脚本数
    if (authManager.hasScope(Scopes.WORKERS_READ)) {
      this.workerService.listScripts(accountId).then((scripts: WorkerScript[]) => {
        this.workersCount = scripts.length;
        this.workers = scripts;
      }).catch(() => {
      });
    }
    // R2 桶数
    if (authManager.hasScope(Scopes.R2_READ)) {
      this.storageService.listBuckets(accountId).then((buckets: R2Bucket[]) => {
        this.bucketCount = buckets.length;
        this.buckets = buckets;
      }).catch(() => {
      });
    }
    // D1 库数
    if (authManager.hasScope(Scopes.D1_READ)) {
      this.storageService.listDatabases(accountId).then((dbs: D1Database[]) => {
        this.dbCount = dbs.length;
        this.databases = dbs;
      }).catch(() => {
      });
    }
    // 全账号 DNS 记录数：逐 zone 轻量取记录数后求和（域名特别多时只统计前 50 个，对齐 iOS）
    if (authManager.hasScope(Scopes.DNS_READ) && zones.length > 0) {
      const sample = zones.length > 50 ? zones.slice(0, 50) : zones;
      const jobs: Promise<number>[] = sample.map((z: Zone) =>
        this.dnsService.fetchRecords(z.id).then((recs: DNSRecord[]) => recs.length).catch(() => 0));
      Promise.all(jobs).then((counts: number[]) => {
        let total = 0;
        for (const c of counts) {
          total += c;
        }
        this.dnsTotal = total;
      }).catch(() => {
      });
    } else if (zones.length === 0) {
      this.dnsTotal = 0;
    }
  }

  /// 搜索 / 置顶 / 告警要用、但指标岛不需要的清单：KV 命名空间与 Tunnel。
  /// 均按 scope 门控、失败静默——搜索面板本来就允许「暂无可搜索的资源」。
  private loadInventory(accountId: string): void {
    if (authManager.hasScope(Scopes.KV_READ)) {
      this.storageService.listNamespaces(accountId).then((list: KVNamespace[]) => {
        this.namespaces = list;
      }).catch(() => {
      });
    }
    if (authManager.hasScope(Scopes.TUNNEL_READ)) {
      this.accountModuleService.listTunnels(accountId).then((list: Tunnel[]) => {
        this.tunnels = list;
      }).catch(() => {
      });
    }
  }

  /// 全账号可搜索资源（域名 / Workers / R2 / D1 / KV / Tunnel）
  private resourceItems(): ResourceItem[] {
    return buildResourceItems(this.zones, this.workers, this.buckets, this.databases,
      this.namespaces, this.tunnels);
  }

  /// 搜索结果：空查询给前 30 条（已固定的排最前），有查询最多 50 条
  private searchResults(): ResourceItem[] {
    const items = this.resourceItems();
    const q = this.searchQuery.trim();
    if (q === '') {
      const pinnedFirst = items.filter((i: ResourceItem) => this.isPinnedItem(i))
        .concat(items.filter((i: ResourceItem) => !this.isPinnedItem(i)));
      return pinnedFirst.slice(0, 30);
    }
    return items.filter((i: ResourceItem) => resourceMatches(i, q)).slice(0, 50);
  }

  private isPinnedItem(item: ResourceItem): boolean {
    return item.kind === ResKind.ZONE
      ? this.pins.isPinned(item.id)
      : this.pinnedRes.isPinned(item.kind, item.id);
  }

  /// 星标切换：域名进 pinnedZones，其余五类进 pinnedResources
  private togglePinItem(item: ResourceItem): void {
    const accountId = accountStore.selectedId;
    if (accountId === '') {
      return;
    }
    const done = item.kind === ResKind.ZONE
      ? pinnedZones.toggle(accountId, item.id)
      : pinnedResources.toggle(accountId, item.kind, item.id);
    done.then((nowPinned: boolean) => {
      this.getUIContext().getPromptAction().showToast({
        message: nowPinned ? '已固定到首页' : '已取消固定',
      });
    }).catch(() => {
    });
  }

  /// 跨类型跳转派发。免费层**能搜到**全部资源（清单照拉、告警照出），
  /// 只在「点进去」这一步撞付费墙——闸门挂在这里，不挂在结果行上（口径对齐 iOS）。
  private openResource(kind: string, resourceId: string): void {
    if (kind === ResKind.ZONE) {
      const zone = this.zones.find((z: Zone) => z.id === resourceId);
      const param: ZoneRouteParam = { zoneId: resourceId, zoneName: zone?.name ?? resourceId };
      this.pathStack.pushPathByName(Routes.ZONE_DETAIL, param);
      return;
    }
    if (kind === ResKind.WORKER) {
      const nameParam: NameParam = { name: resourceId };
      this.pathStack.pushPathByName(Routes.WORKER_DETAIL, nameParam);
      return;
    }
    if (kind === ResKind.R2) {
      if (!requirePro(this.pathStack, 'R2 对象存储')) {
        return;
      }
      const nameParam: NameParam = { name: resourceId };
      this.pathStack.pushPathByName(Routes.R2_OBJECTS, nameParam);
      return;
    }
    if (kind === ResKind.D1) {
      if (!requirePro(this.pathStack, 'D1 数据库')) {
        return;
      }
      const db = this.databases.find((d: D1Database) => d.uuid === resourceId);
      const idName: IdNameParam = { id: resourceId, name: db?.name ?? resourceId };
      this.pathStack.pushPathByName(Routes.D1_QUERY, idName);
      return;
    }
    if (kind === ResKind.KV) {
      if (!requirePro(this.pathStack, 'KV 存储')) {
        return;
      }
      const ns = this.namespaces.find((n: KVNamespace) => n.id === resourceId);
      const idName: IdNameParam = { id: resourceId, name: ns?.title ?? resourceId };
      this.pathStack.pushPathByName(Routes.KV_KEYS, idName);
      return;
    }
    if (kind === ResKind.TUNNEL) {
      if (!requirePro(this.pathStack, 'Cloudflare Tunnel')) {
        return;
      }
      const tunnel = this.tunnels.find((t: Tunnel) => t.id === resourceId);
      const idName: IdNameParam = { id: resourceId, name: tunnel?.name ?? resourceId };
      this.pathStack.pushPathByName(Routes.TUNNEL_DETAIL, idName);
    }
  }

  /// 账号用量加载：scope 缺失直接停发；authz → 不可用卡片；其余失败 → 重试卡片。
  private loadUsage(accountId: string): void {
    this.usage = null;
    this.usageUnavailable = false;
    this.usageFailed = false;
    if (!authManager.hasScope(Scopes.ACCOUNT_ANALYTICS_READ)) {
      return; // scope 门控由 build() 渲染锁定卡片
    }
    this.usageService.loadAccountUsage(accountId).then((usage: AccountUsage) => {
      this.usage = usage;
    }).catch((err: Error) => {
      if (err instanceof AccountAnalyticsUnauthorizedError) {
        this.usageUnavailable = true;
      } else {
        this.usageFailed = true;
      }
    });
  }

  /// 当前钟点在山脊序列中的下标（末端对齐现在）
  private currentHourIndex(): number {
    return this.requestSeries.length > 0 ? this.requestSeries.length - 1 : -1;
  }

  /// 把账号总览写入服务卡片共享快照（天色随本地时刻）
  private writeWidgetSnapshot(): void {
    const phaseNum: number = SkyPhaseColors.current(false, new Date().getHours()) as number;
    const label = accountStore.selectedName !== '' ? accountStore.selectedName : authManager.currentLabel();
    const data: WidgetSnapshotData = {
      label: label,
      requests: this.requests24h,
      zones: this.zoneCount >= 0 ? `${this.zoneCount}` : '—',
      active: `${this.activeZoneCount}`,
      series: this.requestSeries.join(','),
      phase: phaseNum,
      updatedAt: new Date().toISOString(),
    };
    try {
      WidgetSnapshot.write(GlobalContext.get(), data).catch(() => {
      });
    } catch (e) {
    }
  }

  private healthLine(): string {
    if (this.zoneCount < 0) {
      return this.zoneCount === -2 ? '域名同步失败，下拉重试' : '正在同步域名与资产…';
    }
    if (this.zoneCount === 0) {
      return '当前账号还没有域名';
    }
    if (this.activeZoneCount === this.zoneCount) {
      return `${this.zoneCount} 个域名全部正常`;
    }
    return `${this.activeZoneCount}/${this.zoneCount} 个域名已启用`;
  }

  /// 右上角账号头像（点开切换身份/账户，对照 iOS accountMenu）
  @Builder
  accountAvatar() {
    Text(this.store.selectedName !== '' ? this.store.selectedName.substring(0, 1).toUpperCase() : '?')
      .width(32)
      .height(32)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .textAlign(TextAlign.Center)
      .borderRadius(16)
      .linearGradient({
        angle: 135,
        colors: [['#FFA64F', 0.0], ['#E5661A', 1.0]],
      })
      .bindMenu(this.switchMenu())
  }

  @Builder
  switchMenu() {
    Menu() {
      // 同身份下的多个账户
      ForEach(this.store.accounts, (account: Account) => {
        MenuItem({ content: account.name })
          .selected(account.id === this.store.selectedId)
          .onChange(() => {
            accountStore.select(account).then(() => {
              this.reload();
            });
          })
      }, (account: Account) => account.id)
      // 多身份切换
      if (authManager.sessions.length > 1) {
        MenuItemGroup({ header: '切换身份' }) {
          ForEach(authManager.sessions, (session: AuthSessionMeta) => {
            MenuItem({ content: session.label })
              .selected(session.id === authManager.currentSessionId)
              .onChange(() => {
                authManager.switchSession(session.id).then(() => {
                  accountStore.reload().then(() => {
                    this.reload();
                  });
                });
              })
          }, (session: AuthSessionMeta) => session.id)
        }
      }
    }
  }

  private zoneCountText(): string {
    return this.zoneCount >= 0 ? `${this.zoneCount}` : (this.zoneCount === -2 ? '—' : '…');
  }

  /// 资产计数展示：-1（加载中/未取到）→ '…'，否则数值
  private countText(n: number): string {
    return n >= 0 ? `${n}` : '…';
  }

  /// 第四格：优先 R2 桶数，其次 D1 库数，都不可用时回退活跃域名数（对照 iOS fourthStatIsland）
  @Builder
  fourthStatIsland() {
    if (this.bucketCount >= 0) {
      StatIsland({ label: 'R2', value: `${this.bucketCount}`, sub: '存储桶' })
    } else if (this.dbCount >= 0) {
      StatIsland({ label: 'D1', value: `${this.dbCount}`, sub: '数据库' })
    } else {
      StatIsland({
        label: '已启用',
        value: this.zoneCount >= 0 ? `${this.activeZoneCount}` : '…',
        sub: '活跃域名',
      })
    }
  }

  // MARK: - 用量宫格（每服务一格：名称 + 瓶颈指标 + 额度副行，对照 iOS usageGrid）

  /// 一个服务多指标时取消耗比例最高的（瓶颈指标）。免费额度口径（对齐 iOS Free 档）。
  private topMetric(candidates: UsageMetric[]): UsageMetric {
    let best: UsageMetric = candidates[0];
    for (const m of candidates) {
      if (m.ratio > best.ratio) {
        best = m;
      }
    }
    return best;
  }

  private workersTile(usage: AccountUsage): UsageTile {
    const candidates: UsageMetric[] = [
      {
        context: '请求 · 今日',
        valueText: formatCount(usage.workersRequestsToday),
        quotaText: `/ ${formatCount(100000)}`,
        ratio: usage.workersRequestsToday / 100000,
      },
    ];
    const top = this.topMetric(candidates);
    return { title: 'Workers', context: top.context, valueText: top.valueText, quotaText: top.quotaText, ratio: top.ratio };
  }

  private r2Tile(usage: AccountUsage): UsageTile {
    const candidates: UsageMetric[] = [
      {
        context: 'A 类 · 本月',
        valueText: formatCount(usage.r2ClassAMonth),
        quotaText: '/ 1M',
        ratio: usage.r2ClassAMonth / 1000000,
      },
      {
        context: 'B 类 · 本月',
        valueText: formatCount(usage.r2ClassBMonth),
        quotaText: '/ 10M',
        ratio: usage.r2ClassBMonth / 10000000,
      },
      {
        context: '存储',
        valueText: formatBytes(usage.r2StorageBytes),
        quotaText: '/ 10 GB',
        ratio: usage.r2StorageBytes / 10000000000,
      },
    ];
    const top = this.topMetric(candidates);
    return { title: 'R2', context: top.context, valueText: top.valueText, quotaText: top.quotaText, ratio: top.ratio };
  }

  private d1Tile(usage: AccountUsage): UsageTile {
    const candidates: UsageMetric[] = [];
    const d1 = usage.d1Usage;
    if (d1 !== undefined) {
      candidates.push({
        context: '行读取 · 今日',
        valueText: formatCount(d1.rowsReadToday),
        quotaText: `/ ${formatCount(5000000)}`,
        ratio: d1.rowsReadToday / 5000000,
      });
      candidates.push({
        context: '行写入 · 今日',
        valueText: formatCount(d1.rowsWrittenToday),
        quotaText: `/ ${formatCount(100000)}`,
        ratio: d1.rowsWrittenToday / 100000,
      });
    }
    if (candidates.length === 0) {
      return { title: 'D1', context: '—', valueText: '—', quotaText: '', ratio: 0 };
    }
    const top = this.topMetric(candidates);
    return { title: 'D1', context: top.context, valueText: top.valueText, quotaText: top.quotaText, ratio: top.ratio };
  }

  private kvTile(usage: AccountUsage): UsageTile {
    const candidates: UsageMetric[] = [];
    const kv = usage.kvUsage;
    if (kv !== undefined) {
      candidates.push({
        context: '读取 · 今日',
        valueText: formatCount(kv.readsToday),
        quotaText: `/ ${formatCount(100000)}`,
        ratio: kv.readsToday / 100000,
      });
      candidates.push({
        context: '写入 · 今日',
        valueText: formatCount(kv.writesToday),
        quotaText: `/ ${formatCount(1000)}`,
        ratio: kv.writesToday / 1000,
      });
    }
    const kvBytes = usage.kvStorageBytes;
    if (kvBytes !== undefined) {
      candidates.push({
        context: '存储',
        valueText: formatBytes(kvBytes),
        quotaText: '/ 1 GB',
        ratio: kvBytes / 1000000000,
      });
    }
    if (candidates.length === 0) {
      return { title: 'KV', context: '—', valueText: '—', quotaText: '', ratio: 0 };
    }
    const top = this.topMetric(candidates);
    return { title: 'KV', context: top.context, valueText: top.valueText, quotaText: top.quotaText, ratio: top.ratio };
  }

  // MARK: - 用量明细 sheet（点格弹出：该服务全部指标行 + 进度条，对照 iOS usageDetailSheet）

  private usageSheetTitle(): string {
    if (this.usageSheetService === 'workers') {
      return 'Workers';
    }
    if (this.usageSheetService === 'r2') {
      return 'R2';
    }
    if (this.usageSheetService === 'd1') {
      return 'D1';
    }
    if (this.usageSheetService === 'kv') {
      return 'KV';
    }
    return '';
  }

  /// 有额度指标行：已用/额度 + 消耗比例
  private quotaRow(title: string, used: number, quota: number): UsageDetailRow {
    return {
      title: title,
      valueText: `${formatCount(used)} / ${formatCount(quota)}`,
      ratio: quota > 0 ? Math.min(used / quota, 1) : -1,
    } as UsageDetailRow;
  }

  /// 字节口径的有额度指标行（额度文案用固定单位串，如 '10 GB'）
  private bytesRow(title: string, usedBytes: number, quotaBytes: number, quotaLabel: string): UsageDetailRow {
    return {
      title: title,
      valueText: `${formatBytes(usedBytes)} / ${quotaLabel}`,
      ratio: quotaBytes > 0 ? Math.min(usedBytes / quotaBytes, 1) : -1,
    } as UsageDetailRow;
  }

  /// 无额度指标行：只显示已用值
  private plainRow(title: string, valueText: string): UsageDetailRow {
    return { title: title, valueText: valueText, ratio: -1 } as UsageDetailRow;
  }

  /// 当前点开服务的全部指标明细行（免费档额度口径，与宫格瓦片一致）
  private usageDetailRows(): UsageDetailRow[] {
    const usage = this.usage;
    if (usage === null) {
      return [];
    }
    const rows: UsageDetailRow[] = [];
    if (this.usageSheetService === 'workers') {
      rows.push(this.quotaRow('请求 · 今日', usage.workersRequestsToday, 100000));
      const cpuUs = usage.cpuTimeTodayUs;
      if (cpuUs !== undefined) {
        // Free 档无 CPU 月度额度（单次 10ms 上限），只展示今日合计
        rows.push(this.plainRow('CPU 耗时 · 今日', `${formatCount(Math.round(cpuUs / 1000))} ms`));
      }
    } else if (this.usageSheetService === 'r2') {
      rows.push(this.bytesRow('存储', usage.r2StorageBytes, 10000000000, '10 GB'));
      rows.push(this.quotaRow('A 类操作 · 本月', usage.r2ClassAMonth, 1000000));
      rows.push(this.quotaRow('B 类操作 · 本月', usage.r2ClassBMonth, 10000000));
      if (usage.r2ObjectCount > 0) {
        rows.push(this.plainRow('对象数', formatCount(usage.r2ObjectCount)));
      }
    } else if (this.usageSheetService === 'd1') {
      const d1 = usage.d1Usage;
      if (d1 !== undefined) {
        rows.push(this.quotaRow('行读取 · 今日', d1.rowsReadToday, 5000000));
        rows.push(this.quotaRow('行写入 · 今日', d1.rowsWrittenToday, 100000));
      }
    } else if (this.usageSheetService === 'kv') {
      const kv = usage.kvUsage;
      if (kv !== undefined) {
        rows.push(this.quotaRow('读取 · 今日', kv.readsToday, 100000));
        rows.push(this.quotaRow('写入 · 今日', kv.writesToday, 1000));
      }
      const kvBytes = usage.kvStorageBytes;
      if (kvBytes !== undefined) {
        rows.push(this.bytesRow('存储', kvBytes, 1000000000, '1 GB'));
      }
    }
    return rows;
  }

  /// 进度条颜色随消耗比例橙 → 琥珀 → 红（对齐 iOS UsageRow.barColor）
  private ratioColor(ratio: number): ResourceColor {
    if (ratio >= 0.9) {
      return DANGER_RED;
    }
    if (ratio >= 0.7) {
      return '#F59E0B';
    }
    return BRAND_ORANGE;
  }

  @Builder
  usageDetailRowView(row: UsageDetailRow) {
    Column({ space: 6 }) {
      Row() {
        Text(row.title)
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Text(row.valueText)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      if (row.ratio >= 0) {
        Progress({ value: Math.round(row.ratio * 100), total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(6)
          .color(this.ratioColor(row.ratio))
          .backgroundColor($r('sys.color.comp_divider'))
      }
    }
    .width('100%')
  }

  @Builder
  usageDetailSheet() {
    Column({ space: 14 }) {
      // 头部：服务名 + 套餐档位（宫格与明细均为免费档口径）
      Column({ space: 2 }) {
        Text(this.usageSheetTitle())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Text('免费档额度口径')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .margin({ top: 8 })

      GlassIsland({ cornerRadius: OCLayout.chipRadius }) {
        Column({ space: 12 }) {
          ForEach(this.usageDetailRows(), (row: UsageDetailRow) => {
            this.usageDetailRowView(row)
          }, (row: UsageDetailRow) => `${this.usageSheetService}_${row.title}_${row.valueText}`)
        }
        .width('100%')
      }

      Text('「今日」按 UTC 日界聚合，与 Cloudflare 免费额度重置时间一致')
        .fontSize(11)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
    }
    .padding({ left: OCLayout.pagePadding, right: OCLayout.pagePadding, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  /// 用量瓦片（serviceKey 非空时点按弹出该服务的明细 sheet；锁定/降级卡不走此 builder）
  @Builder
  usageTileCard(tile: UsageTile, serviceKey: string) {
    Column({ space: 4 }) {
      Text(tile.title)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
      Row({ space: 4 }) {
        Text(tile.valueText)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (tile.quotaText !== '') {
          Text(tile.quotaText)
            .fontSize(11)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
        }
      }
      .alignItems(VerticalAlign.Bottom)
      Text(tile.context)
        .fontSize(11)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(OCLayout.islandPadding)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(OCLayout.chipRadius)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
    .onClick(() => {
      if (serviceKey !== '') {
        this.usageSheetService = serviceKey;
        this.usageSheetVisible = true;
      }
    })
  }

  /// 中性提示卡（scope 锁定 / authz 不可用 / 加载失败共用形态）
  @Builder
  usageNoticeCard(symbol: Resource, title: string, detail: string) {
    Column({ space: 6 }) {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([$r('sys.color.font_secondary')])
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .textAlign(TextAlign.Center)
      if (detail !== '') {
        Text(detail)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 18, bottom: 18, left: 12, right: 12 })
  }

  @Builder
  usageSection() {
    Column({ space: 10 }) {
      SectionTitle({ title: '用量' })
      if (!authManager.hasScope(Scopes.ACCOUNT_ANALYTICS_READ)) {
        GlassIsland({ cornerRadius: OCLayout.chipRadius, pad: 0 }) {
          this.usageNoticeCard($r('sys.symbol.lock'), '需要「流量分析」权限才能展示账号用量', '')
        }
      } else if (this.usage !== null) {
        Column({ space: OCLayout.islandGap }) {
          Row({ space: OCLayout.islandGap }) {
            this.usageTileCard(this.workersTile(this.usage), 'workers')
            this.usageTileCard(this.r2Tile(this.usage), 'r2')
          }
          .width('100%')
          if (this.usage.d1Usage !== undefined || this.usage.kvUsage !== undefined || this.usage.kvStorageBytes !== undefined) {
            Row({ space: OCLayout.islandGap }) {
              if (this.usage.d1Usage !== undefined) {
                this.usageTileCard(this.d1Tile(this.usage), 'd1')
              }
              if (this.usage.kvUsage !== undefined || this.usage.kvStorageBytes !== undefined) {
                this.usageTileCard(this.kvTile(this.usage), 'kv')
              }
            }
            .width('100%')
          }
        }
        .width('100%')
      } else if (this.usageUnavailable) {
        GlassIsland({ cornerRadius: OCLayout.chipRadius, pad: 0 }) {
          this.usageNoticeCard(
            $r('sys.symbol.gauge_with_dots_needle_33percent'),
            '账号用量当前不可用（免费账号或权限受限）',
            'Workers / R2 / D1 / KV 用量通常需付费版账号；域名流量分析不受影响。'
          )
        }
      } else if (this.usageFailed) {
        GlassIsland({ cornerRadius: OCLayout.chipRadius, pad: 0 }) {
          this.usageNoticeCard($r('sys.symbol.exclamationmark_triangle'), '用量加载失败，下拉刷新重试', '')
        }
      } else {
        GlassIsland({ cornerRadius: OCLayout.chipRadius, pad: 0 }) {
          this.usageNoticeCard($r('sys.symbol.arrow_clockwise'), '正在加载账号用量…', '')
        }
      }
    }
    .width('100%')
  }

  // MARK: - 域名卡区（对齐 iOS zonesSection：pin 优先，否则前 3 个）

  /// 首页展示的域名：用户固定过的优先；一个没固定时兜底展示前 3 个
  private displayZones(): Zone[] {
    const pinned = this.zones.filter((z: Zone) => this.pins.ids.includes(z.id));
    return pinned.length > 0 ? pinned : this.zones.slice(0, 3);
  }

  /// 该 zone 的 24h 请求序列（无数据时空数组）
  private seriesFor(zoneId: string): number[] {
    return this.zoneSeries.get(zoneId) ?? [];
  }

  private totalFor(zoneId: string): number {
    return this.zoneTotals.get(zoneId) ?? 0;
  }

  /// 套餐取首词（"Free Website" → "Free"），与状态并进副标题（对齐 iOS planShort）
  private zoneSubtitle(zone: Zone): string {
    const plan = zone.plan?.name ?? '';
    const planShort = plan !== '' ? plan.split(' ')[0] : '';
    const status = statusLabel(zone.status);
    return planShort !== '' ? `${planShort} · ${status}` : status;
  }

  /// sparkline 折线点位（56×16 视口，纵向按序列峰值归一）
  private sparkPoints(series: number[]): number[][] {
    const w = 56;
    const h = 16;
    const pts: number[][] = [];
    if (series.length < 2) {
      return pts;
    }
    let max = 0;
    for (const v of series) {
      if (v > max) {
        max = v;
      }
    }
    if (max <= 0) {
      max = 1;
    }
    const stepX = w / (series.length - 1);
    for (let i = 0; i < series.length; i++) {
      const x = i * stepX;
      const y = h - 1 - (series[i] / max) * (h - 2);
      pts.push([x, y]);
    }
    return pts;
  }

  @Builder
  dashZoneCard(zone: Zone) {
    Row({ space: 10 }) {
      ZoneAvatar({ domain: zone.name, dim: 32 })
      Column({ space: 2 }) {
        Text(zone.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.zoneSubtitle(zone))
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.seriesFor(zone.id).length > 1) {
        Column({ space: 2 }) {
          Polyline({ width: 56, height: 16 })
            .points(this.sparkPoints(this.seriesFor(zone.id)))
            .fillOpacity(0)
            .stroke(BRAND_ORANGE)
            .strokeWidth(1.5)
          Text(formatCount(this.totalFor(zone.id)))
            .fontSize(10)
            .fontColor($r('sys.color.font_secondary'))
        }
        .alignItems(HorizontalAlign.End)
      }
      StatusDot({ status: zone.status, dim: 7 })
    }
    .width('100%')
    .padding({ left: OCLayout.islandPadding, right: OCLayout.islandPadding, top: 10, bottom: 10 })
    .onClick(() => {
      const param: ZoneRouteParam = { zoneId: zone.id, zoneName: zone.name };
      this.pathStack.pushPathByName(Routes.ZONE_DETAIL, param);
    })
  }

  @Builder
  zonesSection() {
    Column({ space: 10 }) {
      SectionTitle({ title: '域名' })
      GlassIsland({ pad: 0 }) {
        Column() {
          ForEach(this.displayZones(), (zone: Zone, index: number) => {
            this.dashZoneCard(zone)
            if (index < this.displayZones().length - 1) {
              Divider()
                .strokeWidth(0.5)
                .color($r('sys.color.comp_divider'))
                .margin({ left: 56 })
            }
          }, (zone: Zone) => zone.id)
        }
        .width('100%')
      }
      if (this.pins.ids.length === 0) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.pin'))
            .fontSize(12)
            .fontColor([$r('sys.color.font_tertiary')])
          Text('在域名详情页点图钉，可固定想在首页看到的域名')
            .fontSize(11)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .padding({ left: 4 })
      }
    }
    .width('100%')
  }

  @Builder
  networkList() {
    Column() {
      ForEach(ACCOUNT_ENTRIES, (entry: DashEntry, index: number) => {
        NavRow({
          symbol: entry.symbol,
          title: entry.title,
          subtitle: entry.subtitle,
          locked: entry.proFeature !== undefined && !this.entitlements.isPro,
          onNav: () => {
            const feature = entry.proFeature ?? '';
            if (feature !== '' && !requirePro(this.pathStack, feature)) {
              return;
            }
            this.pathStack.pushPathByName(entry.route, null);
          },
        })
        if (index < ACCOUNT_ENTRIES.length - 1) {
          Divider()
            .strokeWidth(0.5)
            .color($r('sys.color.comp_divider'))
            .margin({ left: 64 })
        }
      }, (entry: DashEntry) => entry.route)
    }
    .width('100%')
  }

  // MARK: - 命令搜索（对照 iOS ResourceSearchView）
  //
  // 走 sheet + 普通 TextInput 而非页面内搜索框：概览页是下拉刷新页，
  // 与列表搜索共存时下拉手势会打架（iOS 侧同因走的 sheet）。
  // 选中不在 sheet 内跳转：先关面板，再由概览页的栈派发路由。

  @Builder
  searchSheet() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(17)
          .fontColor([$r('sys.color.font_secondary')])
        TextInput({ text: this.searchQuery, placeholder: '搜索域名、Workers、存储桶…' })
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.searchQuery = value;
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .borderRadius(OCLayout.chipRadius)
      .border({ width: 0.5, color: $r('sys.color.comp_divider') })
      .margin({ top: 8 })

      if (this.resourceItems().length === 0) {
        Column({ space: 6 }) {
          Text('暂无可搜索的资源')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
          Text('下拉刷新概览页后，这里会列出当前账号的资源')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .padding(32)
      } else if (this.searchResults().length === 0) {
        Column({ space: 6 }) {
          Text('没有匹配的资源')
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
          Text('换个关键词试试')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .padding(32)
      } else {
        List({ space: 6 }) {
          ForEach(this.searchResults(), (item: ResourceItem) => {
            ListItem() {
              Row({ space: 12 }) {
                Stack() {
                  SymbolGlyph(resKindSymbol(item.kind))
                    .fontSize(19)
                    .fontColor([$r('app.color.oc_brand_text')])
                }
                .width(36)
                .height(36)
                .backgroundColor('#1AF48120')
                .borderRadius(10)

                Column({ space: 3 }) {
                  Text(item.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('sys.color.font_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${resKindLabel(item.kind)} · ${item.subtitle}`)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .onClick(() => {
                  this.showSearch = false;
                  this.openResource(item.kind, item.id);
                })

                SymbolGlyph(this.isPinnedItem(item) ? $r('sys.symbol.pin_fill') : $r('sys.symbol.pin'))
                  .fontSize(17)
                  .fontColor([this.isPinnedItem(item) ? BRAND_ORANGE : $r('sys.color.font_tertiary')])
                  .onClick(() => {
                    this.togglePinItem(item);
                  })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(OCLayout.chipRadius)
              .border({ width: 0.5, color: $r('sys.color.comp_divider') })
            }
          }, (item: ResourceItem) => `${item.kind}|${item.id}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: 16 })
  }

  // MARK: - 告警中心（规则在 DashboardResources.buildAlerts，纯函数不发请求）

  @Builder
  alertsSection() {
    Column({ space: 10 }) {
      Row() {
        SectionTitle({ title: '告警' })
        Blank()
        if (this.currentAlerts().length > 0) {
          Text(`${this.currentAlerts().length}`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_secondary'))
        }
      }
      .width('100%')

      if (this.currentAlerts().length === 0) {
        GlassIsland({ pad: 14 }) {
          Row({ space: 10 }) {
            Circle({ width: 8, height: 8 }).fill(alertColor(3))
            Text('暂无告警，一切正常')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
          }
          .width('100%')
        }
      } else {
        GlassIsland({ pad: 0 }) {
          Column() {
            ForEach(this.currentAlerts(), (alert: DashAlert, index: number) => {
              Row({ space: 10 }) {
                Circle({ width: 8, height: 8 }).fill(alertColor(alert.level))
                Column({ space: 3 }) {
                  Text(alert.title)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('sys.color.font_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(alert.detail)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_secondary'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                if (alert.kind !== '') {
                  Image($r('sys.media.ohos_ic_public_arrow_right'))
                    .width(14)
                    .height(14)
                    .fillColor($r('sys.color.font_tertiary'))
                }
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .onClick(() => {
                if (alert.kind !== '') {
                  this.openResource(alert.kind, alert.resourceId);
                }
              })
              if (index < this.currentAlerts().length - 1) {
                Divider()
                  .strokeWidth(0.5)
                  .color($r('sys.color.comp_divider'))
                  .margin({ left: 32 })
              }
            }, (alert: DashAlert) => alert.id)
          }
          .width('100%')
        }
      }
    }
    .width('100%')
  }

  private currentAlerts(): DashAlert[] {
    // 资产仍在加载时不下「一个 Worker 都没有」的结论（清单此刻本来就是空的）
    const workerCount = authManager.hasScope(Scopes.WORKERS_READ) ? this.workersCount : -1;
    return buildAlerts(this.zones, this.tunnels, workerCount);
  }

  // MARK: - 已固定（域名以外：Workers / R2 / D1 / KV / Tunnel）

  /// 固定项 → 当前清单里的条目；查不到的显示为「未找到」并允许一键取消固定
  private pinnedResourceRows(): ResourceItem[] {
    const items = this.resourceItems();
    const rows: ResourceItem[] = [];
    for (const key of this.pinnedRes.keys) {
      const sep = key.indexOf('|');
      if (sep <= 0) {
        continue;
      }
      const kind = key.substring(0, sep);
      const id = key.substring(sep + 1);
      const found = items.find((i: ResourceItem) => i.kind === kind && i.id === id);
      rows.push(found ?? { kind: kind, id: id, title: id, subtitle: '未找到（资源可能已删除）' });
    }
    return rows;
  }

  @Builder
  pinnedSection() {
    Column({ space: 10 }) {
      SectionTitle({ title: '已固定' })
      GlassIsland({ pad: 0 }) {
        Column() {
          ForEach(this.pinnedResourceRows(), (item: ResourceItem, index: number) => {
            Row({ space: 12 }) {
              Stack() {
                SymbolGlyph(resKindSymbol(item.kind))
                  .fontSize(19)
                  .fontColor([$r('app.color.oc_brand_text')])
              }
              .width(36)
              .height(36)
              .backgroundColor('#1AF48120')
              .borderRadius(10)
              Column({ space: 3 }) {
                Text(item.title)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${resKindLabel(item.kind)} · ${item.subtitle}`)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .onClick(() => {
                this.openResource(item.kind, item.id);
              })
              SymbolGlyph($r('sys.symbol.pin_fill'))
                .fontSize(17)
                .fontColor([$r('app.color.oc_brand_text')])
                .onClick(() => {
                  this.togglePinItem(item);
                })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            if (index < this.pinnedResourceRows().length - 1) {
              Divider()
                .strokeWidth(0.5)
                .color($r('sys.color.comp_divider'))
                .margin({ left: 62 })
            }
          }, (item: ResourceItem) => `${item.kind}|${item.id}`)
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  build() {
    Refresh({ refreshing: this.refreshing }) {
      Scroll() {
      Column({ space: 20 }) {
        // 晨昏问候头 + 右上角账号切换
        Stack({ alignContent: Alignment.TopEnd }) {
          DaybreakHeader({ accountName: this.store.selectedName, healthLine: this.healthLine() })
          Row({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(20)
              .fontColor([$r('sys.color.font_secondary')])
              .onClick(() => {
                this.searchQuery = '';
                this.showSearch = true;
              })
            this.accountAvatar()
          }
        }
        .width('100%')

        // 重授权横幅：当前身份缺 refresh token 时引导原地重授权（对齐 iOS reauthBanner）
        if (this.auth.sessionsNeedingReauth.includes(this.auth.currentSessionId)) {
          ReauthBanner()
        }

        // 2×2 指标岛（对照 iOS statIslands：域名 / Workers / DNS 记录 / R2·D1）——错峰浮现第 0 档
        RevealBox({ idx: 0 }) {
          Column({ space: OCLayout.islandGap }) {
            Row({ space: OCLayout.islandGap }) {
              StatIsland({ label: '域名', value: this.zoneCountText(), sub: `${this.activeZoneCount} 已启用` })
              StatIsland({ label: 'Workers', value: this.countText(this.workersCount), sub: '已部署脚本' })
            }
            .width('100%')
            Row({ space: OCLayout.islandGap }) {
              StatIsland({ label: 'DNS 记录', value: this.countText(this.dnsTotal), sub: '全部域名' })
              this.fourthStatIsland()
            }
            .width('100%')
          }
          .width('100%')
        }

        // 告警中心（未启用的域名 / 异常隧道 / 没有 Worker，点一下直达）
        if (this.zones.length > 0 || this.tunnels.length > 0) {
          RevealBox({ idx: 1 }) {
            this.alertsSection()
          }
        }

        // 用量宫格（账号级 GraphQL 各产品指标；scope 门控 + authz 降级）
        RevealBox({ idx: 2 }) {
          this.usageSection()
        }

        // 流量山脊（全账号 24h 请求长成地形，太阳落在当前时刻）
        if (this.requestSeries.length > 1) {
          RevealBox({ idx: 2 }) {
            Column({ space: 10 }) {
              SectionTitle({ title: '流量' })
              GlassIsland({ pad: 12 }) {
                RidgeChart({ data: this.requestSeries, sunIndex: this.currentHourIndex(), ridgeHeight: 110 })
              }
            }
            .width('100%')
          }
        }

        // 域名卡区（pin 优先否则前 3 个；点按进域名详情）
        if (this.zones.length > 0) {
          RevealBox({ idx: 3 }) {
            this.zonesSection()
          }
        }

        // 已固定（域名以外的五类；域名仍在上面的卡区，避免同一资源出现两次）
        if (this.pinnedRes.keys.length > 0) {
          this.pinnedSection()
        }

        // 网络与账号级模块
        RevealBox({ idx: 4 }) {
          Column({ space: 10 }) {
            SectionTitle({ title: '网络与账号' })
            GlassIsland({ pad: 0 }) {
              this.networkList()
            }
          }
          .width('100%')
        }
      }
      .padding(OCLayout.pagePadding)
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .onDidScroll((dx: number, dy: number) => { tabBarScroll.notifyScroll(dy); })
      .backgroundColor(Color.Transparent)
    }
    .onRefreshing(() => {
      // 加载逻辑保持在独立异步链路，手势回调只置状态，不同步 await
      this.refreshing = true;
      this.reload().then(() => {
        this.refreshing = false;
      }).catch(() => {
        this.refreshing = false;
      });
    })
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    // 用量宫格点开的服务明细半模态（单档中高，锁定/降级卡不触发）
    .bindSheet(this.usageSheetVisible, this.usageDetailSheet(), ocSheetCompact(() => {
      this.usageSheetVisible = false;
    }))
    // 命令搜索面板（大档半模态，结果列表要占满高度）
    .bindSheet(this.showSearch, this.searchSheet(), ocSheet(() => {
      this.showSearch = false;
    }))
  }
}
