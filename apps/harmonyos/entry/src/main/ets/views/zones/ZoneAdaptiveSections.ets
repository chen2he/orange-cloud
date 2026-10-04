// 流量分析下方的「访问明细」「安全事件」（adaptive 数据集；时间窗跟随上方 24h / 7d / 30d，
// 门槛同上：24h 免费，7d / 30d 由上方选择器的 Pro 闸门把关）。上方 1h/1d 图表不受影响。
// 查询前先读 viewer.zones.settings：数据集停用就整段换成一句说明；窗口超出 maxDuration /
// notOlderThan 就裁到上限并注明；查询报错也只换成说明，不打断上方图表。
import {
  AccessDetails,
  AdaptiveWindow,
  AnalyticsRange,
  FirewallEventRow,
  SecurityEvents,
  TopItem,
  ZoneDatasetSettings,
} from '../../models/AnalyticsModels';
import { AnalyticsService, adaptiveWindow } from '../../services/AnalyticsService';
import { formatCount } from '../../core/util/Format';
import { BRAND_ORANGE, SectionHeader } from '../common/Components';
import { actionLabel } from './RuleComponents';

interface DetailDimension {
  key: string;
  label: string;
}

const DETAIL_DIMENSIONS: DetailDimension[] = [
  { key: 'country', label: '国家/地区' },
  { key: 'status', label: '状态码' },
  { key: 'path', label: '路径' },
  { key: 'host', label: '主机名' },
];

/// 安全事件处置方式 → 中文（规则动作沿用 actionLabel，事件特有的补几个，未知原样）
function eventActionLabel(action: string): string {
  if (action === 'allow') {
    return '放行';
  }
  if (action === 'jschallenge') {
    return 'JS 质询';
  }
  if (action === 'challenge_solved' || action === 'managed_challenge_non_interactive_solved'
    || action === 'managed_challenge_interactive_solved' || action === 'jschallenge_solved') {
    return '质询已通过';
  }
  if (action === 'challenge_failed' || action === 'jschallenge_failed') {
    return '质询未通过';
  }
  if (action === 'bypass') {
    return '绕过';
  }
  if (action === 'connection_close') {
    return '断开连接';
  }
  return actionLabel(action);
}

/// 事件来源 → 中文（未知原样）
function eventSourceLabel(source: string): string {
  if (source === 'firewallCustom') {
    return '自定义规则';
  }
  if (source === 'firewallManaged') {
    return '托管规则';
  }
  if (source === 'firewallRules') {
    return '防火墙规则';
  }
  if (source === 'waf') {
    return 'WAF';
  }
  if (source === 'rateLimit') {
    return '速率限制';
  }
  if (source === 'securityLevel') {
    return '安全级别';
  }
  if (source === 'bic') {
    return '浏览器完整性检查';
  }
  if (source === 'hot') {
    return '防盗链';
  }
  if (source === 'uaBlock') {
    return 'UA 拦截';
  }
  if (source === 'ip' || source === 'ipRange' || source === 'asn' || source === 'country') {
    return 'IP 访问规则';
  }
  if (source === 'zoneLockdown') {
    return '区域锁定';
  }
  if (source === 'l7ddos') {
    return 'DDoS 防护';
  }
  if (source === 'botFight') {
    return 'Bot Fight Mode';
  }
  if (source === 'botManagement') {
    return '机器人管理';
  }
  if (source === 'apiShield') {
    return 'API Shield';
  }
  return source;
}

/// 裁剪后实际覆盖时长的说明
function clampNote(seconds: number): string {
  if (seconds <= 0) {
    return '';
  }
  if (seconds < 24 * 3600) {
    return `受数据集查询上限限制，仅统计最近 ${Math.max(1, Math.round(seconds / 3600))} 小时`;
  }
  return `受数据集查询上限限制，仅统计最近 ${Math.round(seconds / 86400)} 天`;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/// 事件时间 → MM-dd HH:mm:ss
function eventTime(iso: string | undefined): string {
  const date = new Date(iso ?? '');
  if (Number.isNaN(date.getTime())) {
    return iso ?? '';
  }
  return `${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} ${pad2(date.getHours())}:${pad2(date.getMinutes())}:${pad2(date.getSeconds())}`;
}

@ObservedV2
class AdaptiveVM {
  @Trace details: AccessDetails | null = null;
  @Trace detailsNote: string = '';
  @Trace detailsClampNote: string = '';
  @Trace detailsLoading: boolean = false;
  @Trace events: SecurityEvents | null = null;
  @Trace eventsNote: string = '';
  @Trace eventsClampNote: string = '';
  @Trace eventsLoading: boolean = false;
  private service: AnalyticsService = new AnalyticsService();
  private generation: number = 0;

  async load(zoneId: string, range: AnalyticsRange): Promise<void> {
    if (zoneId === '') {
      return;
    }
    this.generation++;
    const gen = this.generation;
    this.detailsLoading = true;
    this.eventsLoading = true;
    this.detailsNote = '';
    this.eventsNote = '';
    let settings: ZoneDatasetSettings | null = null;
    try {
      settings = await this.service.adaptiveSettings(zoneId);
    } catch (e) {
      // settings 字段不可用：不裁剪，直接按原窗口查，出错再换说明
      settings = null;
    }
    if (gen !== this.generation) {
      return;
    }
    this.loadDetails(zoneId, adaptiveWindow(range, settings?.httpRequestsAdaptiveGroups), gen).catch(() => {
    });
    this.loadEvents(zoneId, adaptiveWindow(range, settings?.firewallEventsAdaptive), gen).catch(() => {
    });
  }

  private async loadDetails(zoneId: string, win: AdaptiveWindow, gen: number): Promise<void> {
    try {
      if (win.unavailable) {
        this.details = null;
        this.detailsNote = '当前套餐不提供访问明细数据';
        return;
      }
      const details = await this.service.accessDetails(zoneId, win);
      if (gen !== this.generation) {
        return;
      }
      this.details = details;
      this.detailsClampNote = clampNote(win.clampedSeconds);
    } catch (e) {
      if (gen === this.generation) {
        this.details = null;
        this.detailsNote = `暂时无法加载访问明细：${(e as Error).message ?? ''}`;
      }
    } finally {
      if (gen === this.generation) {
        this.detailsLoading = false;
      }
    }
  }

  private async loadEvents(zoneId: string, win: AdaptiveWindow, gen: number): Promise<void> {
    try {
      if (win.unavailable) {
        this.events = null;
        this.eventsNote = '当前套餐不提供安全事件数据';
        return;
      }
      const events = await this.service.securityEvents(zoneId, win);
      if (gen !== this.generation) {
        return;
      }
      this.events = events;
      this.eventsClampNote = clampNote(win.clampedSeconds);
    } catch (e) {
      if (gen === this.generation) {
        this.events = null;
        this.eventsNote = `暂时无法加载安全事件：${(e as Error).message ?? ''}`;
      }
    } finally {
      if (gen === this.generation) {
        this.eventsLoading = false;
      }
    }
  }
}

@ComponentV2
export struct ZoneAdaptiveSections {
  @Param zoneId: string = '';
  @Param range: AnalyticsRange = '24h';
  @Local vm: AdaptiveVM = new AdaptiveVM();
  @Local dimIndex: number = 0;

  aboutToAppear(): void {
    this.reload();
  }

  @Monitor('zoneId', 'range')
  onTargetChange(): void {
    this.reload();
  }

  private reload(): void {
    this.vm.load(this.zoneId, this.range).catch(() => {
    });
  }

  /// 当前维度的 Top 10
  private detailItems(): TopItem[] {
    const d = this.vm.details;
    if (d === null) {
      return [];
    }
    const key = DETAIL_DIMENSIONS[this.dimIndex].key;
    if (key === 'status') {
      return d.status;
    }
    if (key === 'path') {
      return d.path;
    }
    if (key === 'host') {
      return d.host;
    }
    return d.country;
  }

  @Builder
  note(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 4, right: 4 })
  }

  @Builder
  loadingRow() {
    Row({ space: 8 }) {
      LoadingProgress()
        .width(18)
        .height(18)
        .color(BRAND_ORANGE)
      Text('正在加载…')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .padding({ left: 4, top: 6, bottom: 6 })
  }

  /// 排行行：标签 + 次数 + 比例条（与国家排行同款）
  @Builder
  barRow(item: TopItem, maxCount: number, mono: boolean) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(item.label)
          .fontSize(13)
          .fontFamily(mono ? 'monospace' : 'HarmonyOS Sans')
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(formatCount(item.count))
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      Row() {
        Column()
          .width(`${maxCount > 0 ? Math.max(1, item.count * 100 / maxCount) : 1}%`)
          .height(5)
          .backgroundColor($r('app.color.oc_brand'))
          .borderRadius(3)
          .opacity(0.8)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
  }

  @Builder
  barCard(items: TopItem[], mono: boolean) {
    Column() {
      ForEach(items, (item: TopItem, index: number) => {
        this.barRow(item, items.length > 0 ? items[0].count : 0, mono)
      }, (item: TopItem, index: number) => `${index}-${item.label}`)
    }
    .width('100%')
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(12)
    .clip(true)
  }

  @Builder
  detailsSection() {
    Column({ space: 8 }) {
      SectionHeader({ title: '访问明细' })
      if (this.vm.detailsLoading && this.vm.details === null) {
        this.loadingRow()
      } else if (this.vm.detailsNote !== '') {
        this.note(this.vm.detailsNote)
      } else if (this.vm.details !== null) {
        Row({ space: 6 }) {
          ForEach(DETAIL_DIMENSIONS, (dim: DetailDimension, index: number) => {
            Text(dim.label)
              .fontSize(12)
              .fontWeight(this.dimIndex === index ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.dimIndex === index ? $r('app.color.oc_brand_text') : $r('sys.color.font_secondary'))
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(30)
              .borderRadius(15)
              .backgroundColor(this.dimIndex === index ? $r('app.color.oc_brand_bg') : $r('sys.color.comp_background_list_card'))
              .onClick(() => {
                this.dimIndex = index;
              })
          }, (dim: DetailDimension) => dim.key)
        }
        .width('100%')
        if (this.detailItems().length === 0) {
          this.note('该时间范围内没有请求')
        } else {
          this.barCard(this.detailItems(), DETAIL_DIMENSIONS[this.dimIndex].key === 'path'
            || DETAIL_DIMENSIONS[this.dimIndex].key === 'host')
        }
        if (this.vm.detailsClampNote !== '') {
          this.note(this.vm.detailsClampNote)
        }
      }
    }
    .width('100%')
  }

  @Builder
  eventRow(event: FirewallEventRow) {
    Column({ space: 3 }) {
      Row({ space: 6 }) {
        Text(eventActionLabel(event.action ?? ''))
          .fontSize(10)
          .fontColor($r('app.color.oc_brand_text'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor('#1AF48120')
          .borderRadius(4)
        Text(eventSourceLabel(event.source ?? ''))
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
        Blank()
        Text(eventTime(event.datetime))
          .fontSize(10)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      Text(`${event.clientRequestHTTPHost ?? ''}${event.clientRequestPath ?? ''}`)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor($r('sys.color.font_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text([event.clientIP ?? '', event.clientCountryName ?? '', event.rayName ?? '']
        .filter((part: string) => part !== '').join(' · '))
        .fontSize(10)
        .fontFamily('monospace')
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
  }

  @Builder
  eventsSection() {
    Column({ space: 8 }) {
      SectionHeader({ title: '安全事件' })
      if (this.vm.eventsLoading && this.vm.events === null) {
        this.loadingRow()
      } else if (this.vm.eventsNote !== '') {
        this.note(this.vm.eventsNote)
      } else if (this.vm.events !== null) {
        if (this.vm.events!.byAction.length === 0 && this.vm.events!.recent.length === 0) {
          this.note('该时间范围内没有安全事件')
        } else {
          if (this.vm.events!.byAction.length > 0) {
            this.note('按处置方式')
            this.barCard(this.vm.events!.byAction.map((i: TopItem): TopItem => {
              const item: TopItem = { label: eventActionLabel(i.label), count: i.count };
              return item;
            }), false)
          }
          if (this.vm.events!.bySource.length > 0) {
            this.note('按来源')
            this.barCard(this.vm.events!.bySource.map((i: TopItem): TopItem => {
              const item: TopItem = { label: eventSourceLabel(i.label), count: i.count };
              return item;
            }), false)
          }
          if (this.vm.events!.recent.length > 0) {
            this.note('最近事件')
            Column() {
              ForEach(this.vm.events!.recent, (event: FirewallEventRow, index: number) => {
                this.eventRow(event)
                if (index < this.vm.events!.recent.length - 1) {
                  Divider()
                    .strokeWidth(0.5)
                    .color($r('sys.color.comp_divider'))
                    .margin({ left: 14 })
                }
              }, (event: FirewallEventRow, index: number) => `${index}-${event.rayName ?? ''}-${event.datetime ?? ''}`)
            }
            .width('100%')
            .backgroundColor($r('sys.color.comp_background_list_card'))
            .borderRadius(12)
            .clip(true)
          }
        }
        if (this.vm.eventsClampNote !== '') {
          this.note(this.vm.eventsClampNote)
        }
      }
    }
    .width('100%')
  }

  build() {
    Column({ space: 12 }) {
      this.detailsSection()
      this.eventsSection()
    }
    .width('100%')
  }
}
