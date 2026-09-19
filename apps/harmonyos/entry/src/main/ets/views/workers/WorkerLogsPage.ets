import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// Worker 历史日志（Workers Logs / Observability，对齐 iOS WorkerLogsView）。
// 与实时日志互补：tail 只播放连接期间的调用，这里按时间窗查已落库的事件，
// 级别与关键词都下推服务端过滤，翻页用上一页最后一条的 id 作游标。
import { NameParam } from '../../models/Routes';
import { WorkerLogEvent, WorkerLogsPage as LogsPage, WorkerLogsService } from '../../services/WorkerLogsService';
import { accountStore } from '../../core/store/AccountStore';
import { OCEmpty, OCError, OCLoading } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';
import { ocSheet } from '../common/Sheets';
import { pasteboard } from '@kit.BasicServicesKit';

interface TimeRange {
  label: string;
  seconds: number;
}

const RANGES: TimeRange[] = [
  { label: '30 分钟', seconds: 30 * 60 },
  { label: '3 小时', seconds: 3 * 3600 },
  { label: '24 小时', seconds: 24 * 3600 },
  { label: '3 天', seconds: 3 * 24 * 3600 },
];

/// 级别筛选，与实时日志口径一致；all 不下推
const LEVELS: string[] = ['all', 'log', 'debug', 'info', 'warn', 'error'];

const PAGE_SIZE = 100;

function levelTitle(level: string): string {
  return level === 'all' ? '全部级别' : level;
}

function levelColor(level: string): string {
  if (level === 'error' || level === 'exception') {
    return '#DC2626';
  }
  if (level === 'warn') {
    return '#EA580C';
  }
  if (level === 'event') {
    return '#9CA3AF';
  }
  return '#2563EB';
}

function statusColor(code: number): string {
  if (code >= 500) {
    return '#DC2626';
  }
  if (code >= 400) {
    return '#EA580C';
  }
  return '#22C55E';
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/// 毫秒 → MM-dd HH:mm:ss（跨天的时间窗要带日期）
function stampText(ms: number): string {
  if (ms <= 0) {
    return '';
  }
  const d = new Date(ms);
  return `${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
}

/// loadMore 失败文案由页面取走后弹出（VM 不持有 UIContext）
let ocSnackText: string = '';

@ObservedV2
class WorkerLogsVM {
  @Trace events: WorkerLogEvent[] = [];
  @Trace total: number = -1;
  @Trace canLoadMore: boolean = false;
  @Trace isLoading: boolean = false;
  @Trace isLoadingMore: boolean = false;
  @Trace error: string = '';
  @Trace rangeIndex: number = 2;   // 默认 24 小时
  @Trace levelIndex: number = 0;
  @Trace search: string = '';

  private service: WorkerLogsService = new WorkerLogsService();
  /// 时间窗在首页加载时定住，续页复用同一窗口，避免翻页时窗口随时间漂移
  private sinceMs: number = 0;
  private untilMs: number = 0;
  private cursor: string = '';
  /// 每次 load 递增；改范围 / 级别 / 搜索后，晚到的旧一代结果一律丢弃
  private generation: number = 0;

  async load(scriptName: string): Promise<void> {
    this.generation++;
    const gen = this.generation;
    this.isLoading = true;
    this.error = '';
    const until = Date.now();
    const since = until - RANGES[this.rangeIndex].seconds * 1000;
    this.untilMs = until;
    this.sinceMs = since;
    this.cursor = '';
    try {
      const page: LogsPage = await this.service.events(accountStore.selectedId, scriptName, since, until,
        LEVELS[this.levelIndex], this.search, '', PAGE_SIZE);
      if (gen !== this.generation) {
        return;
      }
      this.events = page.events;
      this.total = page.total;
      this.cursor = page.events.length > 0 ? page.events[page.events.length - 1].id : '';
      this.canLoadMore = page.events.length >= PAGE_SIZE && this.cursor !== '';
    } catch (e) {
      if (gen !== this.generation) {
        return;
      }
      this.error = (e as Error).message ?? '查询失败';
      this.events = [];
      this.total = -1;
      this.canLoadMore = false;
    } finally {
      if (gen === this.generation) {
        this.isLoading = false;
      }
    }
  }

  async loadMore(scriptName: string): Promise<void> {
    if (this.isLoading || this.isLoadingMore || !this.canLoadMore || this.cursor === '') {
      return;
    }
    const gen = this.generation;
    this.isLoadingMore = true;
    try {
      const page: LogsPage = await this.service.events(accountStore.selectedId, scriptName, this.sinceMs,
        this.untilMs, LEVELS[this.levelIndex], this.search, this.cursor, PAGE_SIZE);
      if (gen !== this.generation) {
        return;
      }
      // 服务端游标偶发回重复条目，按 id 去重再追加
      const known = new Set<string>(this.events.map((e: WorkerLogEvent) => e.id));
      this.events = this.events.concat(page.events.filter((e: WorkerLogEvent) => !known.has(e.id)));
      this.cursor = page.events.length > 0 ? page.events[page.events.length - 1].id : '';
      this.canLoadMore = page.events.length >= PAGE_SIZE && this.cursor !== '';
    } catch (e) {
      if (gen === this.generation) {
        ocSnackText = (e as Error).message ?? '加载失败';
        this.canLoadMore = false;
      }
    } finally {
      this.isLoadingMore = false;
    }
  }
}

@ComponentV2
export struct WorkerLogsPage {
  @Local vm: WorkerLogsVM = new WorkerLogsVM();
  @Local scriptName: string = '';
  @Local searchDraft: string = '';
  @Local detailVisible: boolean = false;
  @Local detail: WorkerLogEvent | null = null;

  private reload(): void {
    this.vm.load(this.scriptName).catch(() => {
    });
  }

  private loadMore(): void {
    this.vm.loadMore(this.scriptName).then(() => {
      if (ocSnackText !== '') {
        ocSnack(this.getUIContext(), ocSnackText);
        ocSnackText = '';
      }
    }).catch(() => {
    });
  }

  private copyText(text: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      ocSnack(this.getUIContext(), '已复制');
    }).catch(() => {
    });
  }

  @Builder
  fieldRow(title: string, value: string, color: ResourceColor) {
    Row({ space: 12 }) {
      Text(title)
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .width(72)
      Text(value)
        .fontSize(13)
        .fontFamily('monospace')
        .fontColor(color)
        .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  detailSheet() {
    Scroll() {
      Column({ space: 12 }) {
        Text('日志详情')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .margin({ top: 8 })
        if (this.detail !== null) {
          this.fieldRow('级别', this.detail!.level, levelColor(this.detail!.level))
          this.fieldRow('时间', stampText(this.detail!.timestampMs), $r('sys.color.font_primary'))
          if (this.detail!.outcome !== '') {
            this.fieldRow('结果', this.detail!.outcome, $r('sys.color.font_secondary'))
          }
          if (this.detail!.eventType !== '') {
            this.fieldRow('事件类型', this.detail!.eventType, $r('sys.color.font_secondary'))
          }
          if (this.detail!.trigger !== '') {
            this.fieldRow('触发', this.detail!.trigger, $r('sys.color.font_primary'))
          }
          if (this.detail!.url !== '') {
            this.fieldRow('请求地址', this.detail!.url, $r('sys.color.font_primary'))
          }
          if (this.detail!.statusCode > 0) {
            this.fieldRow('状态码', String(this.detail!.statusCode), statusColor(this.detail!.statusCode))
          }
          if (this.detail!.durationMs >= 0) {
            this.fieldRow('耗时', `${this.detail!.durationMs.toFixed(1)} ms`, $r('sys.color.font_secondary'))
          }
          if (this.detail!.requestId !== '') {
            this.fieldRow('请求 ID', this.detail!.requestId, $r('sys.color.font_secondary'))
          }
          if (this.detail!.rayId !== '') {
            this.fieldRow('Ray ID', this.detail!.rayId, $r('sys.color.font_secondary'))
          }
          Text('完整内容')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .margin({ top: 4 })
          Text(this.detail!.message !== '' ? this.detail!.message : this.detail!.text)
            .fontSize(13)
            .fontFamily('monospace')
            .fontColor($r('sys.color.font_primary'))
            .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
            .width('100%')
          if (this.detail!.error !== '' && this.detail!.error !== this.detail!.message) {
            Text(this.detail!.error)
              .fontSize(13)
              .fontFamily('monospace')
              .fontColor('#DC2626')
              .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
              .width('100%')
          }
          Button('复制全部')
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.oc_brand_cta'))
            .onClick(() => {
              const e = this.detail!;
              this.copyText(e.error !== '' && e.error !== e.message ? `${e.text}\n${e.error}` : e.text);
            })
        }
      }
      .padding({ left: 20, right: 20, bottom: 24 })
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .width('100%')
  }

  /// 时间范围分段
  @Builder
  rangeBar() {
    Row({ space: 6 }) {
      ForEach(RANGES, (r: TimeRange, i: number) => {
        Text(r.label)
          .fontSize(13)
          .fontWeight(this.vm.rangeIndex === i ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.vm.rangeIndex === i ? $r('app.color.oc_brand_text') : $r('sys.color.font_secondary'))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(32)
          .borderRadius(16)
          .backgroundColor(this.vm.rangeIndex === i ? $r('app.color.oc_brand_bg') : $r('sys.color.comp_background_list_card'))
          .onClick(() => {
            if (this.vm.rangeIndex !== i) {
              this.vm.rangeIndex = i;
              this.reload();
            }
          })
      }, (r: TimeRange) => r.label)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 6 })
  }

  /// 级别 + 服务端全文搜索（回车提交，避免每敲一字查一次）
  @Builder
  filterBar() {
    Row({ space: 8 }) {
      Select(LEVELS.map((l: string): SelectOption => ({ value: levelTitle(l) })))
        .selected(this.vm.levelIndex)
        .value(levelTitle(LEVELS[this.vm.levelIndex]))
        .font({ size: 12 })
        .onSelect((index: number) => {
          if (this.vm.levelIndex !== index) {
            this.vm.levelIndex = index;
            this.reload();
          }
        })
      Search({ value: this.searchDraft, placeholder: '搜索日志内容' })
        .textFont({ size: 13 })
        .height(34)
        .layoutWeight(1)
        .onChange((value: string) => {
          this.searchDraft = value;
          // 清空即恢复全部
          if (value === '' && this.vm.search !== '') {
            this.vm.search = '';
            this.reload();
          }
        })
        .onSubmit((value: string) => {
          const next = value.trim();
          if (next !== this.vm.search) {
            this.vm.search = next;
            this.reload();
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 6 })
  }

  @Builder
  eventRow(e: WorkerLogEvent) {
    Column({ space: 3 }) {
      Row({ space: 6 }) {
        Text(e.level)
          .fontSize(10)
          .fontColor(levelColor(e.level))
        Text(stampText(e.timestampMs))
          .fontSize(10)
          .fontColor($r('sys.color.font_tertiary'))
        Blank()
        if (e.statusCode > 0) {
          Text(String(e.statusCode))
            .fontSize(10)
            .fontColor(statusColor(e.statusCode))
        }
      }
      .width('100%')
      Text(e.text)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor($r('sys.color.font_primary'))
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(8)
    .onClick(() => {
      this.detail = e;
      this.detailVisible = true;
    })
    .gesture(LongPressGesture().onAction(() => {
      this.copyText(e.text);
    }))
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        Column() {
          this.rangeBar()
          this.filterBar()
          if (this.vm.isLoading && this.vm.events.length === 0) {
            Column() {
              OCLoading({ text: '正在查询历史日志…' })
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
          } else if (this.vm.events.length === 0) {
            Column() {
              OCEmpty({
                symbol: $r('sys.symbol.clock'),
                title: '这段时间没有日志',
                subtitle: '换个时间范围看看。若这个 Worker 从未出现日志，多半是没有开启 Observability——在 wrangler.toml 里打开 [observability] 后重新部署即可。',
              })
            }
            .width('100%')
            .layoutWeight(1)
          } else {
            // 接口的 events.count 实测是「本页条数」（受 limit 封顶），不是总命中数，别写成「命中」
            if (this.vm.events.length > 0) {
              Text(this.vm.isLoading
                ? '正在查询…'
                : (this.vm.canLoadMore
                  ? `已载入 ${this.vm.events.length} 条，上滑加载更早的日志`
                  : `共 ${this.vm.events.length} 条`))
                .fontSize(11)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 4 })
            }
            List({ space: 6 }) {
              ForEach(this.vm.events, (e: WorkerLogEvent) => {
                ListItem() {
                  this.eventRow(e)
                }
              }, (e: WorkerLogEvent) => e.id)
              if (this.vm.canLoadMore || this.vm.isLoadingMore) {
                ListItem() {
                  Text(this.vm.isLoadingMore ? '正在加载更早的日志…' : '加载更早的日志')
                    .fontSize(13)
                    .fontColor($r('app.color.oc_brand_text'))
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .padding(12)
                    .onClick(() => {
                      this.loadMore();
                    })
                }
              }
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 12, right: 12 })
            .scrollBar(BarState.Off)
            .onReachEnd(() => {
              this.loadMore();
            })
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
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: '历史日志' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.detailVisible, this.detailSheet(), ocSheet(() => {
      this.detailVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as NameParam;
      this.scriptName = param.name;
      this.reload();
    })
  }
}
