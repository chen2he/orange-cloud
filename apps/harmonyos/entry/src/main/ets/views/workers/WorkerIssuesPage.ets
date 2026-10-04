import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// Workers 问题（Observability Issues，公开测试）：账号级问题列表 + 问题详情。
// Cloudflare 把未捕获异常、5xx 响应与错误日志自动归类成问题；列表按「活跃 / 已解决 / 已忽略」分段，
// 详情里看最近发生（错误、请求、状态码、堆栈）并改状态。
// Pro 闸门与历史日志同一个（入口处 requirePro）；读 workers-observability.read，改状态需 .write。
import { Routes, WorkerIssueParam, WorkerIssuesParam } from '../../models/Routes';
import {
  IssueOccurrence,
  IssueOccurrencePage,
  WorkerIssue,
  WorkerIssuePage,
  WorkerIssueSummary,
  WorkerIssuesService,
  issueEpochMs,
  issueNumber,
} from '../../services/WorkerIssuesService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { formatCount, formatTimeAgo } from '../../core/util/Format';
import { DANGER_RED, InfoRow, OCEmpty, OCError, OCLoading } from '../common/Components';
import { OCLayout } from '../common/Daybreak';
import { OCSkyBackground } from '../common/OCSky';
import { pasteboard } from '@kit.BasicServicesKit';

interface IssueStatusTab {
  value: string;
  label: string;
}

const STATUS_TABS: IssueStatusTab[] = [
  { value: 'active', label: '活跃' },
  { value: 'resolved', label: '已解决' },
  { value: 'ignored', label: '已忽略' },
];

const PAGE_SIZE = 50;

export function issueStatusLabel(status: string): string {
  if (status === 'active') {
    return '活跃';
  }
  if (status === 'resolved') {
    return '已解决';
  }
  if (status === 'ignored') {
    return '已忽略';
  }
  return status !== '' ? status : '未知';
}

/// epoch 毫秒 → 相对时间（复用 ISO 口径的 formatTimeAgo）
function relativeTime(ms: number): string {
  if (ms <= 0) {
    return '';
  }
  return formatTimeAgo(new Date(ms).toISOString());
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/// epoch 毫秒 → yyyy-MM-dd HH:mm:ss
function stampText(ms: number): string {
  if (ms <= 0) {
    return '';
  }
  const d = new Date(ms);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
}

/// 汇总一行：「活跃问题 N · 共发生 M 次」
export function issueSummaryLine(summary: WorkerIssueSummary): string {
  return `活跃问题 ${formatCount(issueNumber(summary.activeIssues))} · 共发生 ${formatCount(issueNumber(summary.activeOccurrences))} 次`;
}

// ---- 列表 ----

@ObservedV2
class WorkerIssuesVM {
  @Trace issues: WorkerIssue[] = [];
  @Trace statusIndex: number = 0;
  @Trace summaryText: string = '';
  @Trace isLoading: boolean = false;
  @Trace isLoadingMore: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  @Trace page: number = 1;
  @Trace totalPages: number = 1;
  private service: WorkerIssuesService = new WorkerIssuesService();
  /// 切分段后晚到的旧结果一律丢弃
  private generation: number = 0;

  async load(serviceName: string): Promise<void> {
    this.generation++;
    const gen = this.generation;
    this.isLoading = true;
    this.error = '';
    try {
      await accountStore.loadIfNeeded();
      const accountId = accountStore.selectedId;
      // 汇总 best-effort：失败不挡列表
      this.service.summary(accountId, serviceName).then((summary: WorkerIssueSummary) => {
        this.summaryText = issueSummaryLine(summary);
      }).catch(() => {
      });
      const result: WorkerIssuePage = await this.service.list(accountId, STATUS_TABS[this.statusIndex].value,
        serviceName, 1, PAGE_SIZE);
      if (gen !== this.generation) {
        return;
      }
      this.issues = result.issues;
      this.page = result.page;
      this.totalPages = result.totalPages;
      this.loaded = true;
    } catch (e) {
      if (gen === this.generation) {
        this.error = (e as Error).message ?? '加载失败';
      }
    } finally {
      if (gen === this.generation) {
        this.isLoading = false;
      }
    }
  }

  async loadMore(serviceName: string): Promise<void> {
    if (this.isLoading || this.isLoadingMore || this.page >= this.totalPages) {
      return;
    }
    const gen = this.generation;
    this.isLoadingMore = true;
    try {
      const result: WorkerIssuePage = await this.service.list(accountStore.selectedId,
        STATUS_TABS[this.statusIndex].value, serviceName, this.page + 1, PAGE_SIZE);
      if (gen !== this.generation) {
        return;
      }
      const known = new Set<string>(this.issues.map((i: WorkerIssue) => i.id));
      this.issues = this.issues.concat(result.issues.filter((i: WorkerIssue) => !known.has(i.id)));
      this.page = result.page;
      this.totalPages = result.totalPages;
    } catch (e) {
    } finally {
      this.isLoadingMore = false;
    }
  }
}

@ComponentV2
export struct WorkerIssuesPage {
  @Local vm: WorkerIssuesVM = new WorkerIssuesVM();
  /// 过滤的 Worker 名；空 = 全账号
  @Local serviceName: string = '';
  @Local refreshing: boolean = false;
  private pathStack: NavPathStack | null = null;
  private appeared: boolean = false;

  private reload(): void {
    this.vm.load(this.serviceName).catch(() => {
    });
  }

  @Builder
  statusBar() {
    Row({ space: 6 }) {
      ForEach(STATUS_TABS, (tab: IssueStatusTab, index: number) => {
        Text(tab.label)
          .fontSize(13)
          .fontWeight(this.vm.statusIndex === index ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.vm.statusIndex === index ? $r('app.color.oc_brand_text') : $r('sys.color.font_secondary'))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(32)
          .borderRadius(16)
          .backgroundColor(this.vm.statusIndex === index ? $r('app.color.oc_brand_bg') : $r('sys.color.comp_background_list_card'))
          .onClick(() => {
            if (this.vm.statusIndex !== index) {
              this.vm.statusIndex = index;
              this.reload();
            }
          })
      }, (tab: IssueStatusTab) => tab.value)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 6 })
  }

  @Builder
  issueRow(issue: WorkerIssue) {
    Column({ space: 4 }) {
      Text(issue.title ?? issue.id)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily('monospace')
        .fontColor($r('sys.color.font_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row({ space: 8 }) {
        Text(issue.service ?? '')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
        Blank()
        Text(`${formatCount(issueNumber(issue.count))} 次`)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
        Text(relativeTime(issueEpochMs(issue.lastObserved)))
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(14)
    .onClick(() => {
      const param: WorkerIssueParam = { issueId: issue.id, title: issue.title ?? issue.id };
      this.pathStack?.pushPathByName(Routes.WORKER_ISSUE_DETAIL, param);
    })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        Column() {
          this.statusBar()
          if (this.vm.summaryText !== '') {
            Text(this.vm.summaryText)
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
              .padding({ left: 20, right: 20, bottom: 6 })
          }
          if (this.vm.isLoading && !this.vm.loaded) {
            Column() {
              OCLoading({ text: '正在加载问题…' })
            }
            .width('100%')
            .layoutWeight(1)
          } else if (this.vm.error !== '') {
            Column() {
              OCError({
                message: this.vm.error,
                onRetry: () => {
                  this.reload();
                },
              })
            }
            .width('100%')
            .layoutWeight(1)
          } else if (this.vm.issues.length === 0) {
            Column() {
              OCEmpty({
                symbol: $r('sys.symbol.checkmark_circle'),
                title: '没有检测到问题',
                subtitle: 'Cloudflare 会自动把 Worker 的未捕获异常、5xx 响应和错误日志归类成问题（公开测试中）',
              })
            }
            .width('100%')
            .layoutWeight(1)
          } else {
            Refresh({ refreshing: this.refreshing }) {
              List({ space: 8 }) {
                ForEach(this.vm.issues, (issue: WorkerIssue) => {
                  ListItem() {
                    this.issueRow(issue)
                  }
                }, (issue: WorkerIssue) => `${issue.id}-${issue.status ?? ''}`)
                if (this.vm.page < this.vm.totalPages) {
                  ListItem() {
                    Text(this.vm.isLoadingMore ? '正在加载…' : '加载更多')
                      .fontSize(13)
                      .fontColor($r('app.color.oc_brand_text'))
                      .width('100%')
                      .textAlign(TextAlign.Center)
                      .padding(12)
                      .onClick(() => {
                        this.vm.loadMore(this.serviceName).catch(() => {
                        });
                      })
                  }
                }
              }
              .width('100%')
              .height('100%')
              .padding({ left: 16, right: 16, bottom: 24 })
              .scrollBar(BarState.Off)
              .onReachEnd(() => {
                this.vm.loadMore(this.serviceName).catch(() => {
                });
              })
            }
            .onRefreshing(() => {
              this.refreshing = true;
              this.vm.load(this.serviceName).then(() => {
                this.refreshing = false;
              }).catch(() => {
                this.refreshing = false;
              });
            })
            .layoutWeight(1)
          }
        }
        .width('100%')
        .height('100%')
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({
      style: { systemMaterialEffect: systemMaterial() },
      content: { title: { mainTitle: '问题', subTitle: this.serviceName !== '' ? this.serviceName : '全部 Worker' } },
    })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as WorkerIssuesParam;
      this.serviceName = param?.service ?? '';
      this.reload();
    })
    .onShown(() => {
      // 从详情改完状态回来时刷新（首次显示已由 onReady 加载）
      if (this.appeared && !this.vm.isLoading) {
        this.reload();
      }
      this.appeared = true;
    })
  }
}

// ---- 详情 ----

@ObservedV2
class WorkerIssueDetailVM {
  @Trace issue: WorkerIssue | null = null;
  /// 当前状态单独追踪：issue 是普通对象，改它的字段不会刷新界面
  @Trace status: string = '';
  @Trace occurrences: IssueOccurrence[] = [];
  @Trace cursor: string = '';
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  @Trace occurrencesLoading: boolean = false;
  @Trace occurrencesError: string = '';
  @Trace isSaving: boolean = false;
  private service: WorkerIssuesService = new WorkerIssuesService();

  async load(issueId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      await accountStore.loadIfNeeded();
      const issue = await this.service.detail(accountStore.selectedId, issueId);
      this.issue = issue;
      this.status = issue.status ?? '';
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
    await this.loadOccurrences(issueId, false);
  }

  async loadOccurrences(issueId: string, more: boolean): Promise<void> {
    if (this.occurrencesLoading || (more && this.cursor === '')) {
      return;
    }
    this.occurrencesLoading = true;
    this.occurrencesError = '';
    try {
      const page: IssueOccurrencePage = await this.service.occurrences(accountStore.selectedId, issueId,
        more ? this.cursor : '');
      this.occurrences = more ? this.occurrences.concat(page.occurrences) : page.occurrences;
      // 游标不前进（服务端异常）时停止翻页，防止重复追加
      this.cursor = page.cursor !== this.cursor || !more ? page.cursor : '';
    } catch (e) {
      this.occurrencesError = (e as Error).message ?? '加载失败';
    } finally {
      this.occurrencesLoading = false;
    }
  }

  /// 改状态后重新拉详情（PATCH 回包形态不定）
  async setStatus(issueId: string, status: string): Promise<string> {
    this.isSaving = true;
    try {
      await this.service.setStatus(accountStore.selectedId, issueId, status);
      this.status = status;
      try {
        const issue = await this.service.detail(accountStore.selectedId, issueId);
        this.issue = issue;
        this.status = issue.status ?? status;
      } catch (e) {
        // 回读失败沿用刚写入的状态
      }
      return '';
    } catch (e) {
      return (e as Error).message ?? '操作失败';
    } finally {
      this.isSaving = false;
    }
  }
}

/// 一次发生的标题行：「错误名: 消息」
function occurrenceHeadline(o: IssueOccurrence): string {
  const name = o.error?.name ?? '';
  const message = o.error?.message ?? '';
  if (name !== '' && message !== '') {
    return `${name}: ${message}`;
  }
  const single = name !== '' ? name : message;
  return single !== '' ? single : '（无错误信息）';
}

/// 请求行：「方法 路径」，无 HTTP 请求时退到 cron / queue / 调用类型
function occurrenceRequest(o: IssueOccurrence): string {
  const inv = o.invocation;
  if (inv === undefined || inv === null) {
    return '';
  }
  const method = inv.method ?? '';
  let path = inv.path ?? '';
  if (path === '') {
    path = inv.url ?? '';
  }
  if (method !== '' || path !== '') {
    return `${method} ${path}`.trim();
  }
  if ((inv.cron ?? '') !== '') {
    return `Cron ${inv.cron}`;
  }
  if ((inv.queue ?? '') !== '') {
    return `Queue ${inv.queue}`;
  }
  return inv.type ?? '';
}

function statusCodeColor(code: number): string {
  if (code >= 500) {
    return DANGER_RED;
  }
  if (code >= 400) {
    return '#EA580C';
  }
  return '#22C55E';
}

@ComponentV2
export struct WorkerIssueDetailPage {
  @Local vm: WorkerIssueDetailVM = new WorkerIssueDetailVM();
  @Local issueId: string = '';
  @Local title: string = '';
  /// 已展开堆栈的发生记录（按列表下标）
  @Local expanded: number[] = [];

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  private canWrite(): boolean {
    return authManager.hasScope(Scopes.WORKERS_OBSERVABILITY_WRITE);
  }

  private changeStatus(status: string): void {
    if (this.vm.isSaving) {
      return;
    }
    this.vm.setStatus(this.issueId, status).then((err: string) => {
      if (err !== '') {
        this.toast(err);
        return;
      }
      this.toast(status === 'resolved' ? '已标记为已解决' : (status === 'ignored' ? '已忽略' : '已重新打开'));
    });
  }

  private toggleStack(index: number): void {
    if (this.expanded.includes(index)) {
      this.expanded = this.expanded.filter((i: number) => i !== index);
    } else {
      this.expanded = this.expanded.concat([index]);
    }
  }

  private copyText(text: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.toast('已复制');
    }).catch(() => {
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

  @Builder
  infoSection() {
    Column({ space: 8 }) {
      Text(this.vm.issue?.title ?? this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontFamily('monospace')
        .fontColor($r('sys.color.font_primary'))
        .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
        .width('100%')
        .padding({ left: 4, right: 4 })
      Column() {
        InfoRow({ label: 'Worker', value: this.vm.issue?.service ?? '' })
        InfoRow({ label: '状态', value: issueStatusLabel(this.vm.status) })
        if ((this.vm.issue?.type ?? '') !== '') {
          InfoRow({ label: '类型', value: this.vm.issue?.type ?? '' })
        }
        InfoRow({ label: '发生次数', value: formatCount(issueNumber(this.vm.issue?.count)) })
        if (issueEpochMs(this.vm.issue?.firstObserved) > 0) {
          InfoRow({ label: '首次发生', value: stampText(issueEpochMs(this.vm.issue?.firstObserved)) })
        }
        if (issueEpochMs(this.vm.issue?.lastObserved) > 0) {
          InfoRow({ label: '最近发生', value: stampText(issueEpochMs(this.vm.issue?.lastObserved)) })
        }
        if (issueEpochMs(this.vm.issue?.statusUpdated) > 0) {
          InfoRow({ label: '状态更新', value: relativeTime(issueEpochMs(this.vm.issue?.statusUpdated)) })
        }
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .borderRadius(OCLayout.chipRadius)
      .clip(true)
    }
    .width('100%')
  }

  /// 状态操作：活跃 → 标记为已解决 / 忽略；已解决 / 已忽略 → 重新打开。缺写权限只给提示
  @Builder
  actionSection() {
    Column({ space: 8 }) {
      if (!this.canWrite()) {
        Text('更改状态需要 Workers 可观测性写入权限（workers-observability.write），可在「设置 → 身份」中补齐授权')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 4, right: 4 })
      } else if (this.vm.status === 'active') {
        Row({ space: 10 }) {
          Button('标记为已解决')
            .layoutWeight(1)
            .height(42)
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.oc_brand_cta'))
            .enabled(!this.vm.isSaving)
            .onClick(() => {
              this.changeStatus('resolved');
            })
          Button('忽略')
            .layoutWeight(1)
            .height(42)
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
            .backgroundColor($r('sys.color.comp_background_list_card'))
            .enabled(!this.vm.isSaving)
            .onClick(() => {
              this.changeStatus('ignored');
            })
        }
        .width('100%')
      } else {
        Button('重新打开')
          .width('100%')
          .height(42)
          .fontSize(14)
          .fontColor($r('app.color.oc_brand_text'))
          .backgroundColor($r('sys.color.comp_background_list_card'))
          .enabled(!this.vm.isSaving)
          .onClick(() => {
            this.changeStatus('active');
          })
      }
    }
    .width('100%')
  }

  @Builder
  occurrenceRow(o: IssueOccurrence, index: number) {
    Column({ space: 4 }) {
      Text(occurrenceHeadline(o))
        .fontSize(13)
        .fontFamily('monospace')
        .fontColor($r('sys.color.font_primary'))
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row({ space: 8 }) {
        if (occurrenceRequest(o) !== '') {
          Text(occurrenceRequest(o))
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
        }
        if (issueNumber(o.invocation?.statusCode) > 0) {
          Text(String(issueNumber(o.invocation?.statusCode)))
            .fontSize(11)
            .fontColor(statusCodeColor(issueNumber(o.invocation?.statusCode)))
        }
        Blank()
        Text(stampText(issueEpochMs(o.timestamp)))
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      if ((o.error?.stack ?? '') !== '') {
        Text(this.expanded.includes(index) ? '收起堆栈' : '展开堆栈')
          .fontSize(12)
          .fontColor($r('app.color.oc_brand_text'))
          .padding({ top: 2, bottom: 2 })
          .onClick(() => {
            this.toggleStack(index);
          })
        if (this.expanded.includes(index)) {
          Text(o.error?.stack ?? '')
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor($r('sys.color.font_secondary'))
            .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
            .width('100%')
            .onClick(() => {
              this.copyText(o.error?.stack ?? '');
            })
        }
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(12)
  }

  @Builder
  occurrencesSection() {
    Column({ space: 8 }) {
      this.groupHeader('最近发生')
      if (this.vm.occurrencesLoading && this.vm.occurrences.length === 0) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(16)
            .height(16)
          Text('正在加载…')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .padding(12)
      } else if (this.vm.occurrencesError !== '' && this.vm.occurrences.length === 0) {
        Text(this.vm.occurrencesError)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 4, right: 4 })
      } else if (this.vm.occurrences.length === 0) {
        Text('暂无发生记录')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 4, right: 4 })
      } else {
        ForEach(this.vm.occurrences, (o: IssueOccurrence, index: number) => {
          this.occurrenceRow(o, index)
        }, (o: IssueOccurrence, index: number) => `${index}-${o.id ?? ''}`)
        if (this.vm.cursor !== '') {
          Text(this.vm.occurrencesLoading ? '正在加载…' : '加载更多')
            .fontSize(13)
            .fontColor($r('app.color.oc_brand_text'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding(12)
            .onClick(() => {
              this.vm.loadOccurrences(this.issueId, true).catch(() => {
              });
            })
        }
      }
    }
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading && this.vm.issue === null) {
          Column() {
            OCLoading({ text: '正在加载问题…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '' && this.vm.issue === null) {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load(this.issueId).catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else {
          Scroll() {
            Column({ space: 18 }) {
              this.infoSection()
              this.actionSection()
              this.occurrencesSection()
            }
            .width('100%')
            .padding(OCLayout.pagePadding)
          }
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .width('100%')
          .height('100%')
        }
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({
      style: { systemMaterialEffect: systemMaterial() },
      content: { title: { mainTitle: '问题详情', subTitle: this.vm.issue?.service ?? '' } },
    })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as WorkerIssueParam;
      this.issueId = param.issueId;
      this.title = param.title;
      this.vm.load(param.issueId).catch(() => {
      });
    })
  }
}
