// Worker 详情 hub（对照 iOS WorkerDetailView）：信息 + 指标 + 管理入口 + 调试入口 + 删除。
// 各子模块拆成独立页面（变量与密钥 / 触发器 / 部署历史 / 域名 / 实时日志），本页只做导航与概览。
//
// 闸门两层，缺一不可：
//   ① Pro 闸门（requirePro）——管理与调试类能力属付费层，非 Pro 推付费墙
//   ② scope 门控（workers-scripts.write）——写操作缺授权时拦截并提示重新授权
import {
  WorkerScript,
  WorkerScriptContent,
} from '../../models/WorkerModels';
import {
  AnalyticsRange,
  WorkerMetrics as _WM,
  WorkerSeriesPoint,
  WorkerStatusItem,
  workerErrorRate,
  workerStatusColor,
  workerStatusLabel,
} from '../../models/AnalyticsModels';
import { NameParam, Routes } from '../../models/Routes';
import { WorkerService } from '../../services/WorkerService';
import { AnalyticsService } from '../../services/AnalyticsService';
import { AccountAnalyticsUnauthorizedError } from '../../services/UsageService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { formatCount, formatDateTime, formatTimeAgo } from '../../core/util/Format';
import {
  BRAND_ORANGE,
  BRAND_ORANGE_BG,
  DANGER_RED,
  InfoRow,
  NavRow,
  OCLoading,
} from '../common/Components';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';
import { OCLayout, StatIsland, RevealBox } from '../common/Daybreak';
import { MetricsChart, MetricsPoint } from '../common/MetricsChart';
import { entitlement, EntitlementStore } from '../../core/purchase/EntitlementStore';
import { requirePro } from '../paywall/ProGate';

const METRIC_RANGES: AnalyticsRange[] = ['24h', '7d', '30d'];

/// 时间窗 → 分组标题后缀（对照 iOS range.periodLabel）
function rangeLabel(range: AnalyticsRange): string {
  if (range === '24h') {
    return '过去 24 小时';
  }
  return range === '7d' ? '过去 7 天' : '过去 30 天';
}

/// 管理入口（全部为 Pro 能力，对照 iOS 的 ProGatedNavigationLink）
interface ManageEntry {
  symbol: Resource;
  title: string;
  subtitle: string;
  route: string;
  /// 付费墙上展示的场景名
  feature: string;
}

const MANAGE_ENTRIES: ManageEntry[] = [
  {
    symbol: $r('sys.symbol.key'), title: '变量与密钥', subtitle: '环境变量 / 密钥 / 资源绑定',
    route: Routes.WORKER_SECRETS, feature: 'Worker 变量与密钥',
  },
  {
    symbol: $r('sys.symbol.clock'), title: '触发器', subtitle: 'Cron 定时执行',
    route: Routes.WORKER_TRIGGERS, feature: 'Worker 触发器',
  },
  {
    symbol: $r('sys.symbol.clock_arrow_2_circlepath'), title: '部署历史', subtitle: '历次部署记录',
    route: Routes.WORKER_DEPLOYMENTS, feature: 'Worker 部署历史',
  },
  {
    symbol: $r('sys.symbol.checkmark_circle'), title: '构建', subtitle: 'CI 构建记录与日志',
    route: Routes.WORKER_BUILDS, feature: 'Workers 构建',
  },
  {
    symbol: $r('sys.symbol.globe_and_keyboard'), title: '域名', subtitle: 'workers.dev 子域 / 自定义域 / 路由',
    route: Routes.WORKER_DOMAINS, feature: 'Worker 域名与路由',
  },
];

@ObservedV2
class WorkerDetailVM {
  @Trace metrics: _WM | null = null;
  /// 指标时间窗（对齐 iOS 的 24h / 7d / 30d 分段）
  @Trace range: AnalyticsRange = '24h';
  @Trace series: WorkerSeriesPoint[] = [];
  @Trace metricsLoading: boolean = false;
  /// 账户级分析未授权（免费账号常态）：走中性提示而非报错重试
  @Trace metricsUnauthorized: boolean = false;
  @Trace metricsError: string = '';
  /// 脚本元信息（Usage Model / Handlers / Logpush / 时间），列表端点取
  @Trace script: WorkerScript | null = null;
  @Trace subdomainOn: boolean = false;
  @Trace isLoading: boolean = false;
  @Trace content: WorkerScriptContent | null = null;
  @Trace contentLoading: boolean = false;
  @Trace isDeployingCode: boolean = false;

  private service: WorkerService = new WorkerService();
  private analytics: AnalyticsService = new AnalyticsService();

  async load(accountId: string, scriptName: string): Promise<void> {
    this.isLoading = true;
    try {
      this.loadMetrics(accountId, scriptName).catch(() => {
      });
      try {
        this.script = await this.service.findScript(accountId, scriptName);
      } catch (e) {
      }
      this.subdomainOn = await this.service.subdomain(accountId, scriptName);
    } finally {
      this.isLoading = false;
    }
  }

  /// 指标三查询：摘要+状态分解为主，CPU 合计与时间序列各自 best-effort
  ///（较新的 GraphQL 字段在部分账号上不可用，不能把主摘要一起拖垮，对齐 iOS 的拆分）。
  async loadMetrics(accountId: string, scriptName: string): Promise<void> {
    this.metricsLoading = true;
    this.metricsError = '';
    const range = this.range;
    try {
      const summary = await this.analytics.workerMetrics(accountId, scriptName, range);
      this.metrics = summary;
      this.metricsUnauthorized = false;
      try {
        const total = await this.analytics.workerCpuTotal(accountId, scriptName, range);
        if (total >= 0 && this.metrics !== null) {
          this.metrics!.cpuTotalUs = total;
        }
      } catch (e) {
      }
      try {
        this.series = await this.analytics.workerSeries(accountId, scriptName, range);
      } catch (e) {
        this.series = [];
      }
    } catch (e) {
      this.metrics = null;
      this.series = [];
      if (e instanceof AccountAnalyticsUnauthorizedError) {
        this.metricsUnauthorized = true;
      } else {
        this.metricsError = (e as Error).message ?? '指标加载失败';
      }
    } finally {
      this.metricsLoading = false;
    }
  }

  /// 切换时间窗并重新拉指标（同窗口重复点击忽略）
  async switchRange(accountId: string, scriptName: string, range: AnalyticsRange): Promise<void> {
    if (this.range === range) {
      return;
    }
    this.range = range;
    await this.loadMetrics(accountId, scriptName);
  }

  /// 拉取当前源码（content/v2）供代码编辑 sheet 预填
  async loadContent(accountId: string, scriptName: string): Promise<string> {
    this.contentLoading = true;
    try {
      this.content = await this.service.content(accountId, scriptName);
      return '';
    } catch (e) {
      return (e as Error).message ?? '拉取源码失败';
    } finally {
      this.contentLoading = false;
    }
  }

  /// 部署新代码：先取 settings 以便按名 inherit 保住绑定
  async deployCode(accountId: string, scriptName: string, code: string): Promise<string> {
    if (this.content === null) {
      return '源码未就绪';
    }
    this.isDeployingCode = true;
    try {
      const scriptSettings = await this.service.scriptSettings(accountId, scriptName);
      await this.service.updateCode(accountId, scriptName, this.content!, code, scriptSettings);
      return '';
    } catch (e) {
      return (e as Error).message ?? '部署失败';
    } finally {
      this.isDeployingCode = false;
    }
  }

  async removeScript(accountId: string, scriptName: string): Promise<string> {
    try {
      await this.service.deleteScript(accountId, scriptName);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct WorkerDetailPage {
  @Local vm: WorkerDetailVM = new WorkerDetailVM();
  @Local scriptName: string = '';
  @Local codeSheetVisible: boolean = false;
  @Local fCode: string = '';
  /// 观察权益：购买后各入口的 Pro 徽章即时消失
  @Local entitlements: EntitlementStore = entitlement;
  /// 下拉刷新进行中（对照 iOS 详情页的 .refreshable）
  @Local refreshing: boolean = false;
  @Local pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  /// 趋势图数据（只取绘图需要的两列）
  private chartPoints(): MetricsPoint[] {
    const out: MetricsPoint[] = [];
    for (const p of this.vm.series) {
      out.push({ requests: p.requests, errors: p.errors });
    }
    return out;
  }

  /// 错误率副标题：无错误就不显示
  private errorRateText(): string {
    const metrics = this.vm.metrics;
    if (metrics === null || metrics.errors <= 0) {
      return '';
    }
    const rate = workerErrorRate(metrics);
    return rate < 0 ? '' : `${rate.toFixed(2)}%`;
  }

  /// 写操作 scope 门控：缺 workers-scripts.write 时拦截并提示
  private canWrite(): boolean {
    if (!authManager.hasScope(Scopes.WORKERS_WRITE)) {
      this.toast('当前授权未包含 Workers 写权限（workers-scripts.write）');
      return false;
    }
    return true;
  }

  /// 更新代码：先 Pro 闸门，再 scope 门控（对齐 iOS 的先付费墙、后权限提示）
  private openCodeSheet(): void {
    if (!requirePro(this.pathStack, '更新 Worker 代码')) {
      return;
    }
    if (!this.canWrite()) {
      return;
    }
    this.codeSheetVisible = true;
    this.vm.loadContent(accountStore.selectedId, this.scriptName).then((err: string) => {
      if (err === '') {
        this.fCode = this.vm.content?.body ?? '';
      } else {
        this.codeSheetVisible = false;
        this.toast(err);
      }
    });
  }

  private confirmDeployCode(): void {
    this.getUIContext().showAlertDialog({
      title: '部署新代码',
      message: `确定将新代码部署到「${this.scriptName}」？保存后立即生效，现有变量与密钥绑定将保留。`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '部署',
        action: () => {
          this.vm.deployCode(accountStore.selectedId, this.scriptName, this.fCode).then((err: string) => {
            if (err === '') {
              this.codeSheetVisible = false;
              this.toast('已部署');
            } else {
              this.toast(err);
            }
          });
        },
      },
    });
  }

  private confirmDeleteScript(): void {
    this.getUIContext().showAlertDialog({
      title: '删除 Worker',
      message: `确定删除脚本「${this.scriptName}」？此操作不可撤销。`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '删除',
        fontColor: DANGER_RED,
        action: () => {
          this.vm.removeScript(accountStore.selectedId, this.scriptName).then((err: string) => {
            if (err === '') {
              this.pathStack?.pop();
            } else {
              this.toast(err);
            }
          });
        },
      },
    });
  }

  @Builder
  groupHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 4 })
  }

  /// Hero 卡：模块图标 + 脚本名大字 + 子域状态点 + 当前时间窗请求数
  @Builder
  heroCard() {
    Column({ space: 10 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.code_slash'))
          .fontSize(26)
          .fontColor([$r('app.color.oc_brand_text')])
      }
      .width(52)
      .height(52)
      .backgroundColor($r('app.color.oc_brand_bg'))
      .borderRadius(14)

      Text(this.scriptName)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 8 }) {
        Row({ space: 5 }) {
          Circle({ width: 7, height: 7 })
            .fill(this.vm.subdomainOn ? '#22C55E' : $r('sys.color.font_tertiary'))
          Text(this.vm.subdomainOn ? 'workers.dev 已开启' : '子域名已关闭')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.vm.subdomainOn ? '#22C55E' : $r('sys.color.font_secondary'))
        }
        if (this.vm.metrics !== null) {
          Text(`${rangeLabel(this.vm.range)} 请求 ${formatCount(this.vm.metrics!.requests)}`)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
      }
    }
    .width('100%')
    .padding(OCLayout.islandPadding)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(OCLayout.islandRadius)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
  }

  /// 信息分组（对照 iOS WorkerDetailView 的「信息」Section）
  @Builder
  infoSection() {
    Column({ space: 8 }) {
      this.groupHeader('信息')
      Column() {
        if ((this.vm.script?.usage_model ?? '') !== '') {
          InfoRow({ label: 'Usage Model', value: this.vm.script!.usage_model! })
        }
        if ((this.vm.script?.handlers ?? []).length > 0) {
          InfoRow({ label: 'Handlers', value: this.vm.script!.handlers!.join(', ') })
        }
        InfoRow({ label: 'Logpush', value: (this.vm.script?.logpush ?? false) ? '开启' : '关闭' })
        if ((this.vm.script?.compatibility_date ?? '') !== '') {
          InfoRow({ label: '兼容性日期', value: this.vm.script!.compatibility_date! })
        }
        if ((this.vm.script?.created_on ?? '') !== '') {
          InfoRow({ label: '创建时间', value: formatDateTime(this.vm.script!.created_on!) })
        }
        if ((this.vm.script?.modified_on ?? '') !== '') {
          InfoRow({ label: '最近部署', value: formatTimeAgo(this.vm.script!.modified_on!) })
        }
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .borderRadius(OCLayout.chipRadius)
      .border({ width: 0.5, color: $r('sys.color.comp_divider') })
      .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
      .clip(true)
    }
    .width('100%')
  }

  /// 时间窗分段（24h / 7d / 30d，对照 iOS 的 segmented Picker）
  @Builder
  rangePicker() {
    Row({ space: 8 }) {
      ForEach(METRIC_RANGES, (r: AnalyticsRange) => {
        Text(r)
          .fontSize(13)
          .fontWeight(this.vm.range === r ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.vm.range === r ? Color.White : $r('sys.color.font_secondary'))
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor(this.vm.range === r ? BRAND_ORANGE : $r('sys.color.comp_background_list_card'))
          .borderRadius(16)
          .onClick(() => {
            this.vm.switchRange(accountStore.selectedId, this.scriptName, r).catch(() => {
            });
          })
      }, (r: AnalyticsRange) => r)
      Blank()
      if (this.vm.metricsLoading) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(BRAND_ORANGE)
      }
    }
    .width('100%')
  }

  /// 中性提示行（无权限 / 不可用 / 出错共用）
  @Builder
  noticeRow(symbol: Resource, text: string) {
    Row({ space: 8 }) {
      SymbolGlyph(symbol)
        .fontSize(15)
        .fontColor([$r('sys.color.font_tertiary')])
      Text(text)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding(OCLayout.islandPadding)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(OCLayout.chipRadius)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
  }

  /// 指标区（对照 iOS metricsSection）：时间窗 + 趋势图 + 汇总 + CPU + 调用状态分解
  @Builder
  metricsSection() {
    Column({ space: 8 }) {
      this.groupHeader(`指标 · ${rangeLabel(this.vm.range)}`)
      Column({ space: 10 }) {
        if (!authManager.hasScope(Scopes.ACCOUNT_ANALYTICS_READ)) {
          this.noticeRow($r('sys.symbol.lock'), '需要「流量分析」权限才能展示调用指标')
        } else {
          this.rangePicker()
          if (this.vm.metricsUnauthorized) {
            this.noticeRow($r('sys.symbol.histogram'), '此账号暂无账户级数据查询权限')
          } else if (this.vm.metrics === null && this.vm.metricsError !== '') {
            this.noticeRow($r('sys.symbol.exclamationmark_triangle'), this.vm.metricsError)
          } else if (this.vm.metrics !== null) {
            if (this.vm.series.length > 0) {
              MetricsChart({ points: this.chartPoints() })
            }
            Row({ space: 10 }) {
              StatIsland({ label: '请求', value: formatCount(this.vm.metrics!.requests) })
              StatIsland({
                label: '错误',
                value: formatCount(this.vm.metrics!.errors),
                sub: this.errorRateText(),
              })
              StatIsland({ label: '子请求', value: formatCount(this.vm.metrics!.subrequests) })
            }
            .width('100%')
            if (this.vm.metrics!.cpuTotalUs >= 0 || this.vm.metrics!.cpuP50Us >= 0) {
              Column() {
                if (this.vm.metrics!.cpuTotalUs >= 0) {
                  InfoRow({
                    label: 'CPU 合计',
                    value: `${formatCount(Math.round(this.vm.metrics!.cpuTotalUs / 1000))} ms`,
                  })
                }
                if (this.vm.metrics!.cpuP50Us >= 0) {
                  InfoRow({
                    label: 'CPU 单次',
                    value: `P50 ${(this.vm.metrics!.cpuP50Us / 1000).toFixed(1)} ms · P99 ${(Math.max(this.vm.metrics!.cpuP99Us, 0) / 1000).toFixed(1)} ms`,
                  })
                }
              }
              .width('100%')
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(OCLayout.chipRadius)
              .border({ width: 0.5, color: $r('sys.color.comp_divider') })
              .clip(true)
            }
            if (this.vm.metrics!.statusBreakdown.length > 0) {
              Column({ space: 6 }) {
                Text('调用状态')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_secondary'))
                  .width('100%')
                ForEach(this.vm.metrics!.statusBreakdown, (item: WorkerStatusItem) => {
                  Row({ space: 8 }) {
                    Circle({ width: 8, height: 8 })
                      .fill(workerStatusColor(item.status))
                    Text(workerStatusLabel(item.status))
                      .fontSize(13)
                      .fontColor($r('sys.color.font_primary'))
                    Blank()
                    Text(formatCount(item.requests))
                      .fontSize(13)
                      .fontColor($r('sys.color.font_secondary'))
                  }
                  .width('100%')
                  .padding({ top: 4, bottom: 4 })
                }, (item: WorkerStatusItem) => item.status)
              }
              .width('100%')
              .padding(OCLayout.islandPadding)
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(OCLayout.chipRadius)
              .border({ width: 0.5, color: $r('sys.color.comp_divider') })
            }
          }
        }
      }
      .width('100%')
    }
    .width('100%')
  }

  /// 管理分组：更新代码 + 四个子页面入口，全部 Pro 闸门
  @Builder
  manageSection() {
    Column({ space: 8 }) {
      this.groupHeader('管理')
      Column() {
        NavRow({
          symbol: $r('sys.symbol.doc_text'),
          title: '更新代码',
          subtitle: '拉取源码原地编辑并部署',
          locked: !this.entitlements.isPro,
          onNav: () => {
            this.openCodeSheet();
          },
        })
        ForEach(MANAGE_ENTRIES, (entry: ManageEntry) => {
          Divider()
            .strokeWidth(0.5)
            .color($r('sys.color.comp_divider'))
            .margin({ left: 64 })
          NavRow({
            symbol: entry.symbol,
            title: entry.title,
            subtitle: entry.subtitle,
            locked: !this.entitlements.isPro,
            onNav: () => {
              if (!requirePro(this.pathStack, entry.feature)) {
                return;
              }
              const param: NameParam = { name: this.scriptName };
              this.pathStack?.pushPathByName(entry.route, param);
            },
          })
        }, (entry: ManageEntry) => entry.route)
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .borderRadius(OCLayout.chipRadius)
      .border({ width: 0.5, color: $r('sys.color.comp_divider') })
      .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
      .clip(true)
    }
    .width('100%')
  }

  /// 调试分组：实时日志（tail）
  @Builder
  debugSection() {
    Column({ space: 8 }) {
      this.groupHeader('调试')
      Column() {
        NavRow({
          symbol: $r('sys.symbol.dot_radiowaves_left_and_right'),
          title: '实时日志（tail）',
          subtitle: '边缘请求实时追踪',
          locked: !this.entitlements.isPro,
          onNav: () => {
            if (!requirePro(this.pathStack, '实时日志（tail）')) {
              return;
            }
            const param: NameParam = { name: this.scriptName };
            this.pathStack?.pushPathByName(Routes.TAIL, param);
          },
        })
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .borderRadius(OCLayout.chipRadius)
      .border({ width: 0.5, color: $r('sys.color.comp_divider') })
      .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
      .clip(true)
    }
    .width('100%')
  }

  @Builder
  codeSheet() {
    Column({ space: 12 }) {
      Text('更新代码')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      if (this.vm.contentLoading) {
        Text('正在拉取当前源码…')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ top: 40, bottom: 40 })
          .textAlign(TextAlign.Center)
      } else if (this.vm.content !== null) {
        if (!this.vm.content!.editable) {
          Text(`该脚本包含 ${this.vm.content!.moduleCount} 个模块（构建产物），不支持在设备上编辑`)
            .fontSize(12)
            .fontColor(DANGER_RED)
            .width('100%')
        }
        Text(`模块：${this.vm.content!.moduleName} · ${this.vm.content!.isModule ? 'ES Module' : 'Service Worker'}`)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
        TextArea({ text: this.fCode })
          .fontSize(12)
          .fontFamily('monospace')
          .width('100%')
          .height(300)
          .enabled(this.vm.content!.editable)
          .onChange((value: string) => {
            this.fCode = value;
          })
        Button(this.vm.isDeployingCode ? '正在部署…' : '部署')
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor(BRAND_ORANGE)
          .enabled(!this.vm.isDeployingCode && this.vm.content!.editable && this.fCode.trim() !== '')
          .onClick(() => {
            this.confirmDeployCode();
          })
      }
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载 Worker…' })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            Scroll() {
              Column({ space: 18 }) {
                RevealBox({ idx: 0 }) {
                  this.heroCard()
                }
                if (this.vm.script !== null) {
                  RevealBox({ idx: 1 }) {
                    this.infoSection()
                  }
                }
                RevealBox({ idx: 2 }) {
                  this.metricsSection()
                }
                RevealBox({ idx: 3 }) {
                  this.manageSection()
                }
                RevealBox({ idx: 4 }) {
                  this.debugSection()
                }

                Button('删除 Worker')
                  .width('100%')
                  .height(46)
                  .fontSize(15)
                  .fontColor(DANGER_RED)
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(OCLayout.chipRadius)
                  .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                  .margin({ top: 4, bottom: 8 })
                  .onClick(() => {
                    if (this.canWrite()) {
                      this.confirmDeleteScript();
                    }
                  })
              }
              .width('100%')
              .padding(OCLayout.pagePadding)
            }
            .align(Alignment.Top)
            .scrollBar(BarState.Off)
            .width('100%')
            .height('100%')
          }
          .onRefreshing(() => {
            this.refreshing = true;
            this.vm.load(accountStore.selectedId, this.scriptName).then(() => {
              this.refreshing = false;
            }).catch(() => {
              this.refreshing = false;
            });
          })
        }
      }
      .width('100%')
      .height('100%')
    }
    .title(this.scriptName)
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.codeSheetVisible, this.codeSheet(), ocSheet(() => {
      this.codeSheetVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as NameParam;
      this.scriptName = param.name;
      this.vm.load(accountStore.selectedId, param.name).catch(() => {
      });
    })
  }
}
