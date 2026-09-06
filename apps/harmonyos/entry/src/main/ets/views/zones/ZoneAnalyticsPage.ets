// 流量分析：24h/7d/30d 切换 + 汇总卡 + 请求柱状图 + 国家/地区排行（对齐 Android ZoneAnalyticsScreen）。
import { AnalyticsRange, CountryTraffic, TrafficDataPoint } from '../../models/AnalyticsModels';
import { ZoneRouteParam } from '../../models/Routes';
import { AnalyticsService } from '../../services/AnalyticsService';
import { formatBytes, formatCount } from '../../core/util/Format';
import { BRAND_ORANGE, SectionHeader } from '../common/Components';
import { entitlement, EntitlementStore } from '../../core/purchase/EntitlementStore';
import { requirePro } from '../paywall/ProGate';
import { RidgeChart } from '../common/RidgeChart';
import { SunArcGauge } from '../common/SunArcGauge';
import { centroidFor, Centroid } from './CountryCentroids';
import { MapComponent } from '@hms.core.map.MapComponent';
import { map, mapCommon } from '@kit.MapKit';
import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit';
import { OCSkyBackground } from '../common/OCSky';

const RANGES: AnalyticsRange[] = ['24h', '7d', '30d'];

@ObservedV2
class AnalyticsVM {
  @Trace points: TrafficDataPoint[] = [];
  /// 上一周期同长窗口（趋势徽章基准；拉取失败就留空，趋势不显示）
  @Trace previousPoints: TrafficDataPoint[] = [];
  @Trace countries: CountryTraffic[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';

  private service: AnalyticsService = new AnalyticsService();

  totalRequests(): number {
    let total = 0;
    for (const p of this.points) {
      total += p.requests;
    }
    return total;
  }

  totalBytes(): number {
    let total = 0;
    for (const p of this.points) {
      total += p.bytes;
    }
    return total;
  }

  totalThreats(): number {
    let total = 0;
    for (const p of this.points) {
      total += p.threats;
    }
    return total;
  }

  totalUniques(): number {
    let total = 0;
    for (const p of this.points) {
      total += p.uniques;
    }
    return total;
  }

  totalPageViews(): number {
    let total = 0;
    for (const p of this.points) {
      total += p.pageViews ?? 0;
    }
    return total;
  }

  /// 上一周期某指标的合计（0 = 无基准，趋势不显示）
  private previousTotal(pick: (p: TrafficDataPoint) => number): number {
    let total = 0;
    for (const p of this.previousPoints) {
      total += pick(p);
    }
    return total;
  }

  /// 环比百分比；无基准（上一周期为 0）返回 NaN，调用方据此隐藏徽章
  trend(current: number, pick: (p: TrafficDataPoint) => number): number {
    const previous = this.previousTotal(pick);
    if (previous <= 0) {
      return Number.NaN;
    }
    return (current - previous) / previous * 100;
  }

  cacheHitRate(): number {
    let cached = 0;
    let total = 0;
    for (const p of this.points) {
      cached += p.cachedRequests;
      total += p.requests;
    }
    return total > 0 ? cached / total : 0;
  }

  maxRequests(): number {
    let max = 0;
    for (const p of this.points) {
      if (p.requests > max) {
        max = p.requests;
      }
    }
    return max;
  }

  async load(zoneId: string, range: AnalyticsRange): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    this.error = '';
    try {
      this.points = await this.service.zoneTraffic(zoneId, range);
      // 上一周期失败不阻塞主图（趋势徽章隐藏即可）
      try {
        this.previousPoints = await this.service.zoneTrafficPrevious(zoneId, range);
      } catch (e) {
        this.previousPoints = [];
      }
      // 国家排行失败不阻塞主图
      try {
        this.countries = await this.service.zoneCountryTraffic(zoneId, range);
      } catch (e) {
        this.countries = [];
      }
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }
}

/// 可复用分析区块：拥有自己的 AnalyticsVM，aboutToAppear 加载。
/// 既可整页承载（ZoneAnalyticsPage），也可内嵌到 ZoneDetailPage 的「分析」段。
@ComponentV2
export struct ZoneAnalyticsSection {
  @Param zoneId: string = '';
  /// 供 7d / 30d 闸门推付费墙；为 null 时闸门只拦不推（不会发生，两个宿主都传）
  @Param pathStack: NavPathStack | null = null;
  @Local vm: AnalyticsVM = new AnalyticsVM();
  @Local range: AnalyticsRange = '24h';
  /// 观察权益：购买后长窗口按钮的 Pro 标记即时消失
  @Local entitlements: EntitlementStore = entitlement;

  // 地图控制器（真机上由 MapComponent 回调注入；模拟器不初始化，保持 undefined）
  private mapController?: map.MapComponentController;
  // 世界视图：中心纬度 20 / 经度 0，最低缩放
  private mapOptions: mapCommon.MapOptions = {
    position: {
      target: { latitude: 20, longitude: 0 },
      zoom: 2,
    },
    mapType: mapCommon.MapType.STANDARD,
  };

  // MapComponent 初始化回调：拿到控制器后（若已有数据）画气泡
  private mapCallback: AsyncCallback<map.MapComponentController> =
    (err: BusinessError, controller: map.MapComponentController): void => {
      if (err) {
        return;
      }
      this.mapController = controller;
      this.renderBubbles();
    };

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    this.vm.load(this.zoneId, this.range)
      .then(() => {
        this.renderBubbles();
      })
      .catch(() => {
      });
  }

  /// 气泡半径（米）：面积感知，∝ √(请求占比)，避免大国吞掉整张图。
  /// 世界视图下 ~120km–1600km 直径落到屏上是舒服的点。
  private bubbleRadiusMeters(requests: number, maxRequests: number): number {
    const ratio = maxRequests > 0 ? requests / maxRequests : 0;
    const minR = 120000;
    const maxR = 1600000;
    return minR + (maxR - minR) * Math.sqrt(ratio > 0 ? ratio : 0);
  }

  /// 把当前国家数据落到地图上的圆形气泡。控制器不可用时静默跳过（模拟器/初始化失败）。
  private renderBubbles(): void {
    const controller = this.mapController;
    if (!controller) {
      return;
    }
    const list = this.vm.countries;
    if (list.length === 0) {
      return;
    }
    let maxRequests = 0;
    for (const c of list) {
      if (c.requests > maxRequests) {
        maxRequests = c.requests;
      }
    }
    try {
      controller.clear();
    } catch (e) {
      // clear 可能在无 overlay 时抛，忽略
    }
    for (const c of list) {
      const geo: Centroid | undefined = centroidFor(c.country);
      if (!geo) {
        continue;
      }
      const options: mapCommon.MapCircleOptions = {
        center: { latitude: geo.lat, longitude: geo.lng },
        radius: this.bubbleRadiusMeters(c.requests, maxRequests),
        // ARGB：品牌橙 #F48120，填充半透明 + 实线描边
        fillColor: 0x8CF48120,
        strokeColor: 0xFFF48120,
        strokeWidth: 2,
        clickable: false,
      };
      controller.addCircle(options).catch((e: BusinessError) => {
        // 单个圆失败不影响其它
      });
    }
  }

  /// 有已知质心的国家数量（决定是否显示地图 / 占位）
  private mappableCount(): number {
    let n = 0;
    for (const c of this.vm.countries) {
      if (centroidFor(c.country)) {
        n++;
      }
    }
    return n;
  }

  /// 汇总卡。delta 为 NaN 时不出趋势徽章（无上一周期基准）；
  /// positiveIsGood=false 用于「威胁拦截」这类下降才是好事的指标。
  @Builder
  summaryCard(title: string, value: string, delta: number = Number.NaN, positiveIsGood: boolean = true) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
      Text(title)
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
      if (!Number.isNaN(delta)) {
        Text(`${delta >= 0 ? '↑' : '↓'} ${Math.abs(delta).toFixed(1)}%`)
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor((delta >= 0) === positiveIsGood ? '#22C55E' : '#DC2626')
      }
    }
    .layoutWeight(1)
    .padding({ top: 14, bottom: 14 })
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(12)
  }

  /// 请求序列 → number[]（供山脊图）
  private series(): number[] {
    const out: number[] = [];
    for (const p of this.vm.points) {
      out.push(p.requests);
    }
    return out;
  }

  /// 24h 视图下当前钟点在样本中的下标（太阳位置）；非 24h 用末端
  private sunIndex(): number {
    if (this.vm.points.length === 0) {
      return -1;
    }
    if (this.range === '24h') {
      const hour = new Date().getHours();
      const label = `${hour < 10 ? '0' : ''}${hour}:00`;
      const idx = this.vm.points.findIndex((p: TrafficDataPoint) => p.label === label);
      return idx >= 0 ? idx : this.vm.points.length - 1;
    }
    return this.vm.points.length - 1;
  }

  @Builder
  ridge() {
    Column({ space: 6 }) {
      RidgeChart({ data: this.series(), sunIndex: this.sunIndex(), ridgeHeight: 150 })

      if (this.vm.points.length > 1) {
        Row() {
          Text(this.vm.points[0].label)
            .fontSize(10)
            .fontColor($r('sys.color.font_tertiary'))
          Blank()
          Text(this.vm.points[this.vm.points.length - 1].label)
            .fontSize(10)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(12)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
  }

  @Builder
  cacheGauge() {
    Column({ space: 4 }) {
      Stack({ alignContent: Alignment.Bottom }) {
        SunArcGauge({ ratio: this.vm.cacheHitRate(), gaugeSize: 160 })
        Text(`${Math.round(this.vm.cacheHitRate() * 100)}%`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .margin({ bottom: 4 })
      }
      Text('缓存命中率')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(12)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
  }

  @Builder
  trafficMap() {
    Column({ space: 10 }) {
      SectionHeader({ title: '全球流量分布' })

      if (this.mappableCount() === 0) {
        // 无可定位数据：占位（Top-5 列表仍在下方独立展示）
        Column({ space: 6 }) {
          Text('暂无地理数据')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .height(120)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('sys.color.comp_background_list_card'))
        .borderRadius(14)
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })
      } else {
        // Map Kit（Petal Maps）：真机渲染；模拟器不显示属预期，Top-5 列表兜底
        Stack() {
          MapComponent({
            mapOptions: this.mapOptions,
            mapCallback: this.mapCallback,
          })
            .width('100%')
            .height('100%')
        }
        .width('100%')
        .height(240)
        .borderRadius(14)
        .clip(true)
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })
      }
    }
    .width('100%')
  }

  @Builder
  countryRow(item: CountryTraffic, maxRequests: number) {
    Column({ space: 4 }) {
      Row() {
        Text(item.country)
          .fontSize(13)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Text(formatCount(item.requests))
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')

      Row() {
        Column()
          .width(`${maxRequests > 0 ? Math.max(1, item.requests * 100 / maxRequests) : 1}%`)
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

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        ForEach(RANGES, (r: AnalyticsRange) => {
          // 7d / 30d 是 Pro 窗口：非 Pro 点按弹付费墙并停在 24h（不切、不发请求）
          Row({ space: 4 }) {
            Text(r)
              .fontSize(13)
              .fontWeight(this.range === r ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.range === r ? Color.White : $r('sys.color.font_secondary'))
            if (r !== '24h' && !this.entitlements.isPro) {
              SymbolGlyph($r('sys.symbol.lock'))
                .fontSize(11)
                .fontColor([this.range === r ? Color.White : $r('sys.color.font_tertiary')])
            }
          }
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor(this.range === r ? $r('app.color.oc_brand_cta') : $r('sys.color.comp_background_list_card'))
          .borderRadius(16)
          .onClick(() => {
            if (this.range === r) {
              return;
            }
            if (r !== '24h' && !requirePro(this.pathStack, '7 天 / 30 天流量分析')) {
              return;
            }
            this.range = r;
            this.reload();
          })
        }, (r: AnalyticsRange) => r)
        Blank()
      }
      .width('100%')

      if (this.vm.isLoading && this.vm.points.length === 0) {
        Row() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(BRAND_ORANGE)
          Text('正在加载分析数据…')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .margin({ left: 10 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 24, bottom: 24 })
      } else if (this.vm.error !== '') {
        Column({ space: 8 }) {
          Text(this.vm.error)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .textAlign(TextAlign.Center)
          Button('重试')
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.oc_brand_cta'))
            .onClick(() => {
              this.reload();
            })
        }
        .width('100%')
        .padding({ top: 20, bottom: 20 })
      } else if (this.vm.points.length === 0) {
        Text('该时间范围内没有请求')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 20, bottom: 20 })
      } else {
        Row({ space: 10 }) {
          this.summaryCard('请求', formatCount(this.vm.totalRequests()),
            this.vm.trend(this.vm.totalRequests(), (p: TrafficDataPoint) => p.requests))
          this.summaryCard('带宽', formatBytes(this.vm.totalBytes()),
            this.vm.trend(this.vm.totalBytes(), (p: TrafficDataPoint) => p.bytes))
        }
        .width('100%')

        Row({ space: 10 }) {
          this.summaryCard('威胁拦截', formatCount(this.vm.totalThreats()),
            this.vm.trend(this.vm.totalThreats(), (p: TrafficDataPoint) => p.threats), false)
          this.summaryCard('独立访客', formatCount(this.vm.totalUniques()),
            this.vm.trend(this.vm.totalUniques(), (p: TrafficDataPoint) => p.uniques))
        }
        .width('100%')

        Row({ space: 10 }) {
          this.summaryCard('页面浏览', formatCount(this.vm.totalPageViews()),
            this.vm.trend(this.vm.totalPageViews(), (p: TrafficDataPoint) => p.pageViews ?? 0))
          // 右侧留白让四指标 + 页面浏览保持 2 列网格对齐
          Column().layoutWeight(1)
        }
        .width('100%')

        // 山脊：请求长成地形，太阳落在当前时刻
        this.ridge()

        // 太阳弧：缓存命中率
        this.cacheGauge()

        // 全球流量地图（气泡按请求量大小）—— 始终展示区块（真机渲染地图，模拟器/无数据显示占位）
        this.trafficMap()

        // 下方 Top 列表：有数据才展示
        if (this.vm.countries.length > 0) {
          Column() {
            SectionHeader({ title: '国家 / 地区排行' })
            Column() {
              ForEach(this.vm.countries.slice(0, 10), (item: CountryTraffic) => {
                this.countryRow(item, this.vm.countries[0].requests)
              }, (item: CountryTraffic) => item.country)
            }
            .backgroundColor($r('sys.color.comp_background_list_card'))
            .borderRadius(12)
            .clip(true)
          }
          .width('100%')
        }
      }
    }
    .width('100%')
  }
}

@ComponentV2
export struct ZoneAnalyticsPage {
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local pathStack: NavPathStack | null = null;

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        Scroll() {
          Column() {
            ZoneAnalyticsSection({ zoneId: this.zoneId, pathStack: this.pathStack })
          }
          .padding({ left: 16, right: 16, top: 8, bottom: 24 })
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
    }
    .title(`${this.zoneName} · 分析`)
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
    })
  }
}
