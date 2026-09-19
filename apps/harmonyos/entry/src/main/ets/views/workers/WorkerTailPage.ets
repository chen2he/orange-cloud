import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// Worker 实时日志 tail：创建会话 → WebSocket 流；条目展平成日志行后滚动展示。
// 对齐 iOS WorkerTailView：关键词搜索 + 级别筛选 + 暂停（只冻结画面、日志照收）
// + 长按复制整行 + 点按看完整详情 + 清屏。
//
// **原始行始终保留全量**：筛选只影响展示，改条件不丢历史；暂停只停自动滚底，
// 事件照常入 buffer，恢复后能看到这段日志（与 iOS 口径一致）。
import { TailSession, TailTraceItem, TailLog, TailException } from '../../models/WorkerModels';
import { NameParam } from '../../models/Routes';
import { WorkerService } from '../../services/WorkerService';
import { TailSocket } from '../../core/network/TailSocket';
import { accountStore } from '../../core/store/AccountStore';
import { BRAND_ORANGE, OCEmpty } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';
import { ocSheet } from '../common/Sheets';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';

/// 展平后的一行日志：级别 + 正文（原始 trace item 一条可能展开成多行）
interface LogLine {
  id: string;
  level: string;   // event | log | debug | info | warn | error | exception
  text: string;
  time: string;
  outcome: string;
}

/// 级别筛选项（log/debug/info/warn 是 Workers runtime 的原样 token，不翻译；
/// error 归并 runtime 抛出的 exception 行）
const LEVELS: string[] = ['all', 'event', 'log', 'debug', 'info', 'warn', 'error'];

function levelTitle(level: string): string {
  if (level === 'all') {
    return '全部级别';
  }
  if (level === 'event') {
    return '事件';
  }
  return level;
}

function levelMatches(filter: string, level: string): boolean {
  if (filter === 'all') {
    return true;
  }
  if (filter === 'error') {
    return level === 'error' || level === 'exception';
  }
  return filter === level;
}

function levelColor(level: string): string {
  if (level === 'error' || level === 'exception') {
    return '#DC2626';
  }
  if (level === 'warn') {
    return '#EA580C';
  }
  if (level === 'info') {
    return '#2563EB';
  }
  if (level === 'event') {
    return '#9CA3AF';
  }
  return '#22C55E';
}

function outcomeColor(outcome: string): string {
  if (outcome === 'ok') {
    return '#22C55E';
  }
  if (outcome === 'exception' || outcome === 'exceededCpu') {
    return '#DC2626';
  }
  return '#9CA3AF';
}

/// 时间戳（毫秒）→ HH:mm:ss
function clockText(ms: number | undefined): string {
  const d = ms !== undefined && ms > 0 ? new Date(ms) : new Date();
  const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
  return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

/// 一条 trace item → 若干展示行：日志逐条、异常逐条，都没有时给一条事件行
function flattenItem(item: TailTraceItem, seq: number): LogLine[] {
  const outcome = item.outcome ?? '';
  const lines: LogLine[] = [];
  const logs = item.logs ?? [];
  for (let i = 0; i < logs.length; i++) {
    const log: TailLog = logs[i];
    lines.push({
      id: `${seq}-l${i}`,
      level: log.level ?? 'log',
      text: (log.message ?? []).join(' '),
      time: clockText(log.timestamp ?? item.eventTimestamp),
      outcome: outcome,
    });
  }
  const exceptions = item.exceptions ?? [];
  for (let i = 0; i < exceptions.length; i++) {
    const ex: TailException = exceptions[i];
    lines.push({
      id: `${seq}-e${i}`,
      level: 'exception',
      text: `${ex.name ?? 'Error'}: ${ex.message ?? ''}`,
      time: clockText(item.eventTimestamp),
      outcome: outcome,
    });
  }
  if (lines.length === 0) {
    const req = item.event?.request;
    const text = req !== undefined
      ? `${req.method ?? 'GET'} ${req.url ?? ''}`
      : (outcome !== '' ? outcome : '(事件)');
    lines.push({
      id: `${seq}-v`, level: 'event', text: text,
      time: clockText(item.eventTimestamp), outcome: outcome,
    });
  }
  return lines;
}

@ComponentV2
export struct WorkerTailPage {
  @Local scriptName: string = '';
  /// 原始全量日志行（筛选不改它）
  @Local lines: LogLine[] = [];
  @Local connected: boolean = false;
  @Local statusText: string = '正在建立连接…';
  /// 暂停 = 冻结画面（停止自动滚底），事件照常入 buffer
  @Local paused: boolean = false;
  @Local pausedNewCount: number = 0;
  /// 展示过滤
  @Local keyword: string = '';
  @Local levelIndex: number = 0;
  /// 详情 sheet
  @Local detailVisible: boolean = false;
  @Local detailLine: LogLine | null = null;
  private seq: number = 0;
  private socket: TailSocket | null = null;
  private session: TailSession | null = null;
  /// 页面已离开：createTail 还在飞时离开，回来的会话要立即删掉、也不再连 socket，
  /// 否则服务端 tail 会话泄漏，反复进出会撞上每脚本并发 tail 上限
  private disposed: boolean = false;
  private service: WorkerService = new WorkerService();
  private scroller: Scroller = new Scroller();
  /// buffer 上限（对齐 iOS maxLines）
  private static readonly MAX_LINES: number = 1000;

  private start(): void {
    this.service.createTail(accountStore.selectedId, this.scriptName).then((session: TailSession) => {
      if (this.disposed) {
        this.service.deleteTail(accountStore.selectedId, this.scriptName, session.id).catch(() => {
        });
        return;
      }
      this.session = session;
      const socket = new TailSocket(session.url);
      this.socket = socket;
      socket.connect((item: TailTraceItem) => {
        this.seq += 1;
        const incoming = flattenItem(item, this.seq);
        const next = this.lines.concat(incoming);
        this.lines = next.length > WorkerTailPage.MAX_LINES
          ? next.slice(next.length - WorkerTailPage.MAX_LINES)
          : next;
        if (this.paused) {
          this.pausedNewCount += incoming.length;
        } else {
          this.scroller.scrollEdge(Edge.Bottom);
        }
      }, (connected: boolean, error: string) => {
        this.connected = connected;
        if (connected) {
          this.statusText = '已连接，实时接收日志';
        } else if (error !== '') {
          this.statusText = `连接中断：${error}`;
        } else {
          this.statusText = '连接已关闭';
        }
      });
    }).catch((e: Error) => {
      this.statusText = `无法创建 tail：${e.message ?? ''}`;
    });
  }

  private stop(): void {
    this.socket?.close();
    this.socket = null;
    const session = this.session;
    if (session) {
      this.service.deleteTail(accountStore.selectedId, this.scriptName, session.id).catch(() => {
      });
      this.session = null;
    }
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.stop();
  }

  /// 实际渲染的行：级别 + 关键词双重过滤（大小写不敏感）
  private visibleLines(): LogLine[] {
    const filter = LEVELS[this.levelIndex];
    const query = this.keyword.trim().toLowerCase();
    if (filter === 'all' && query === '') {
      return this.lines;
    }
    return this.lines.filter((line: LogLine) => {
      if (!levelMatches(filter, line.level)) {
        return false;
      }
      return query === '' || line.text.toLowerCase().includes(query);
    });
  }

  private isFiltering(): boolean {
    return LEVELS[this.levelIndex] !== 'all' || this.keyword.trim() !== '';
  }

  private copyText(text: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      ocSnack(this.getUIContext(), '已复制');
    }).catch(() => {
    });
  }

  /// 日志详情（可长文换行展示 + 复制全部）
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
        Row({ space: 8 }) {
          Text(this.detailLine?.level ?? '')
            .fontSize(11)
            .fontColor(levelColor(this.detailLine?.level ?? ''))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#14000000')
            .borderRadius(4)
          Text(this.detailLine?.time ?? '')
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
          Blank()
          if ((this.detailLine?.outcome ?? '') !== '') {
            Text(this.detailLine?.outcome)
              .fontSize(11)
              .fontColor(outcomeColor(this.detailLine?.outcome ?? ''))
          }
        }
        .width('100%')
        Text(this.detailLine?.text ?? '')
          .fontSize(13)
          .fontFamily('monospace')
          .fontColor($r('sys.color.font_primary'))
          .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
          .width('100%')
        Button('复制全部')
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.oc_brand_cta'))
          .onClick(() => {
            this.copyText(this.detailLine?.text ?? '');
          })
      }
      .padding({ left: 20, right: 20, bottom: 24 })
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .width('100%')
  }

  /// 顶部：连接状态 + 暂停 / 清屏
  @Builder
  statusBar() {
    Row({ space: 8 }) {
      Circle({ width: 8, height: 8 })
        .fill(this.connected ? '#22C55E' : '#EAB308')
      Text(this.paused && this.pausedNewCount > 0
        ? `已暂停 · 新增 ${this.pausedNewCount} 条`
        : this.statusText)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.paused ? '继续' : '暂停')
        .fontSize(12)
        .fontColor($r('app.color.oc_brand_text'))
        .onClick(() => {
          this.paused = !this.paused;
          if (!this.paused) {
            this.pausedNewCount = 0;
            this.scroller.scrollEdge(Edge.Bottom);
          }
        })
      Text('清屏')
        .fontSize(12)
        .fontColor($r('app.color.oc_brand_text'))
        .onClick(() => {
          this.lines = [];
          this.pausedNewCount = 0;
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 6 })
  }

  /// 筛选条：级别下拉 + 关键词（普通输入框，不与下拉刷新争手势）
  @Builder
  filterBar() {
    Row({ space: 8 }) {
      Select(LEVELS.map((l: string): SelectOption => ({ value: levelTitle(l) })))
        .selected(this.levelIndex)
        .value(levelTitle(LEVELS[this.levelIndex]))
        .font({ size: 12 })
        .onSelect((index: number) => {
          this.levelIndex = index;
        })
      TextInput({ text: this.keyword, placeholder: '搜索日志' })
        .fontSize(13)
        .height(34)
        .layoutWeight(1)
        .onChange((value: string) => {
          this.keyword = value;
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 6 })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        Column() {
          this.statusBar()
          this.filterBar()

          if (this.lines.length === 0) {
            OCEmpty({
              symbol: $r('sys.symbol.dot_radiowaves_left_and_right'),
              title: '等待日志',
              subtitle: '触发该 Worker 后日志会实时出现',
            })
          } else if (this.visibleLines().length === 0) {
            Column({ space: 10 }) {
              Text('没有符合筛选的日志')
                .fontSize(14)
                .fontColor($r('sys.color.font_secondary'))
              Text('清除筛选')
                .fontSize(13)
                .fontColor($r('app.color.oc_brand_text'))
                .onClick(() => {
                  this.keyword = '';
                  this.levelIndex = 0;
                })
            }
            .width('100%')
            .padding(32)
          } else {
            Scroll(this.scroller) {
              Column({ space: 6 }) {
                ForEach(this.visibleLines(), (line: LogLine) => {
                  Column({ space: 3 }) {
                    Row({ space: 6 }) {
                      Text(line.level)
                        .fontSize(10)
                        .fontColor(levelColor(line.level))
                      Text(line.time)
                        .fontSize(10)
                        .fontColor($r('sys.color.font_tertiary'))
                      Blank()
                      if (line.outcome !== '') {
                        Circle({ width: 6, height: 6 })
                          .fill(outcomeColor(line.outcome))
                      }
                    }
                    .width('100%')
                    Text(line.text)
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
                    this.detailLine = line;
                    this.detailVisible = true;
                  })
                  .gesture(LongPressGesture().onAction(() => {
                    this.copyText(line.text);
                  }))
                }, (line: LogLine) => line.id)
              }
              .width('100%')
              .padding({ left: 12, right: 12, bottom: 16 })
            }
            .scrollBar(BarState.Off)
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
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: `${this.scriptName} · 日志` } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.detailVisible, this.detailSheet(), ocSheet(() => {
      this.detailVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as NameParam;
      this.scriptName = param.name;
      this.start();
    })
  }
}
