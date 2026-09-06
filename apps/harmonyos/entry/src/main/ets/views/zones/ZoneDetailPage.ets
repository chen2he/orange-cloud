import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// Zone 详情 hub（对照 iOS ZoneDetailView）：Hero 卡（头像+名字+状态+套餐）+
// 分组（小标签 + 玻璃岛行入口）+ 缓存清除。
import { Zone, zoneDisplayStatus } from '../../models/Models';
import { Routes, ZoneRouteParam } from '../../models/Routes';
import { ZoneService } from '../../services/ZoneService';
import { BRAND_ORANGE, NavRow } from '../common/Components';
import { accountStore } from '../../core/store/AccountStore';
import { pinnedZones, PinnedZonesStore } from '../../core/system/AppPrefs';
import { ZoneAvatar, PlanBadge, StatusDot, statusLabel } from '../common/ZoneComponents';
import { OCLayout, SectionTitle, RevealBox } from '../common/Daybreak';
import { ZoneAnalyticsSection } from './ZoneAnalyticsPage';
import { entitlement, EntitlementStore } from '../../core/purchase/EntitlementStore';
import { pasteboard } from '@kit.BasicServicesKit';
import { requirePro } from '../paywall/ProGate';

interface ModuleEntry {
  symbol: Resource;
  title: string;
  subtitle: string;
  route: string;
  /// Pro 闸门场景名（空 = 免费可用）
  proFeature?: string;
}

interface ModuleSection {
  title: string;
  entries: ModuleEntry[];
}

const SECTIONS: ModuleSection[] = [
  {
    title: '解析与流量',
    entries: [
      { symbol: $r('sys.symbol.list_bullet'), title: 'DNS 记录', subtitle: '解析记录增删改查', route: Routes.DNS },
    ],
  },
  {
    title: '安全',
    entries: [
      { symbol: $r('sys.symbol.checkmark_shield'), title: 'WAF 自定义规则', subtitle: '查看 / 启停 / 新建', route: Routes.WAF, proFeature: 'WAF 自定义规则' },
      { symbol: $r('sys.symbol.nosign'), title: 'IP 访问规则', subtitle: '封禁 / 质询 / 白名单', route: Routes.ACCESS_RULES },
      { symbol: $r('sys.symbol.timer'), title: '速率限制', subtitle: 'Rate Limiting 规则', route: Routes.RATE_LIMIT },
      { symbol: $r('sys.symbol.lock'), title: 'SSL/TLS', subtitle: '加密模式与证书', route: Routes.SSL },
    ],
  },
  {
    title: '性能与规则',
    entries: [
      // 缓存规则 / Transform / Snippets 已收进「规则中心」二级页
      { symbol: $r('sys.symbol.square_stack_3d'), title: '规则中心', subtitle: '重定向 / 缓存 / Transform / Page Rules', route: Routes.RULES_HUB },
      { symbol: $r('sys.symbol.link'), title: 'Worker 路由', subtitle: 'pattern → 脚本映射', route: Routes.WORKER_ROUTES },
      { symbol: $r('sys.symbol.gauge_with_dots_needle_33percent'), title: '性能', subtitle: '开发模式 / 压缩 / 加速开关', route: Routes.PERFORMANCE },
    ],
  },
  {
    title: '更多',
    entries: [
      { symbol: $r('sys.symbol.envelope'), title: '邮件路由', subtitle: 'Email Routing 规则与地址', route: Routes.EMAIL_ROUTING },
      { symbol: $r('sys.symbol.square_grid_2x2'), title: '负载均衡', subtitle: 'Load Balancer', route: Routes.LOAD_BALANCER },
      { symbol: $r('sys.symbol.checkmark_shield'), title: '健康检查', subtitle: '源站是否在线', route: Routes.HEALTH_CHECK },
      { symbol: $r('sys.symbol.gearshape'), title: 'DNS 设置', subtitle: 'DNSSEC / CNAME 展平', route: Routes.DNS_SETTINGS },
      { symbol: $r('sys.symbol.arrow_left_arrow_right'), title: '托管头', subtitle: 'Cloudflare 维护的头部改写', route: Routes.MANAGED_HEADERS },
      { symbol: $r('sys.symbol.gearshape'), title: 'Zone 设置', subtitle: 'Under Attack / HTTPS 等', route: Routes.ZONE_SETTINGS },
    ],
  },
];

@ComponentV2
export struct ZoneDetailPage {
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local zoneStatus: string = '';
  @Local zonePlan: string = '';
  /// 名称服务器与 Zone ID（对齐 iOS ZoneDetailView 底部的 Name Servers / Zone ID 区）
  @Local zoneNameServers: string[] = [];
  @Local isPurging: boolean = false;
  /// 固定域名（共享可观察实例，与 Dashboard / 域名列表联动）
  @Local pins: PinnedZonesStore = pinnedZones;
  /// 观察权益：购买后 Pro 徽章即时消失
  @Local entitlements: EntitlementStore = entitlement;
  /// @Local 而非私有字段：onReady 拿到栈后要传给 ZoneAnalyticsSection（闸门用），需触发重建
  @Local pathStack: NavPathStack | null = null;
  private zoneService: ZoneService = new ZoneService();

  /// 切换「固定到首页」（本机偏好，无需确认弹窗）+ toast 反馈
  private togglePin(): void {
    const accountId = accountStore.selectedId;
    if (accountId === '' || this.zoneId === '') {
      return;
    }
    pinnedZones.toggle(accountId, this.zoneId).then((nowPinned: boolean) => {
      ocSnack(this.getUIContext(), nowPinned ? '已固定到首页' : '已取消固定',);
    }).catch(() => {
    });
  }

  private confirmPurge(): void {
    this.getUIContext().showAlertDialog({
      title: '清除全部缓存',
      message: `将清除 ${this.zoneName} 的所有边缘缓存，源站压力可能短暂上升。`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '清除',
        fontColor: '#DC2626',
        action: () => {
          this.isPurging = true;
          this.zoneService.purgeAllCache(this.zoneId).then(() => {
            this.isPurging = false;
            ocSnack(this.getUIContext(), '已提交缓存清除');
          }).catch((e: Error) => {
            this.isPurging = false;
            ocSnack(this.getUIContext(), e.message ?? '清除失败');
          });
        },
      },
    });
  }

  @Builder
  heroCard() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: 10 }) {
        ZoneAvatar({ domain: this.zoneName, dim: 52 })
        Text(this.zoneName)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 8 }) {
          if (this.zoneStatus !== '') {
            Row({ space: 5 }) {
              StatusDot({ status: this.zoneStatus, dim: 7 })
              Text(statusLabel(this.zoneStatus))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.zoneStatus === 'active' ? '#22C55E' : $r('sys.color.font_secondary'))
            }
          }
          if (this.zonePlan !== '') {
            PlanBadge({ planName: this.zonePlan })
          }
        }
      }
      .width('100%')

      // 图钉：固定到首页 / 取消固定（对齐 iOS ZoneDetailView 的 pin 按钮）
      Column() {
        SymbolGlyph(this.pins.isPinned(this.zoneId) ? $r('sys.symbol.pin_fill') : $r('sys.symbol.pin'))
          .fontSize(18)
          .fontColor([this.pins.isPinned(this.zoneId) ? BRAND_ORANGE : $r('sys.color.font_secondary')])
      }
      .padding(8)
      .onClick(() => {
        this.togglePin();
      })
    }
    .width('100%')
    .padding(OCLayout.islandPadding)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(OCLayout.islandRadius)
  }

  private copyText(text: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      ocSnack(this.getUIContext(), '已复制');
    }).catch(() => {
    });
  }

  /// 名称服务器 + Zone ID：待激活时最常被问的两件事，点按即复制
  @Builder
  identitySection() {
    Column({ space: 8 }) {
      if (this.zoneNameServers.length > 0) {
        SectionTitle({ title: '名称服务器' })
        Column() {
          ForEach(this.zoneNameServers, (server: string, index: number) => {
            Row({ space: 10 }) {
              Text(server)
                .fontSize(13)
                .fontFamily('monospace')
                .fontColor($r('sys.color.font_primary'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              SymbolGlyph($r('sys.symbol.square_on_square_fill'))
                .fontSize(15)
                .fontColor([$r('sys.color.font_tertiary')])
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 11, bottom: 11 })
            .onClick(() => {
              this.copyText(server);
            })
            if (index < this.zoneNameServers.length - 1) {
              Divider()
                .strokeWidth(0.5)
                .color($r('sys.color.comp_divider'))
                .margin({ left: 14 })
            }
          }, (server: string) => server)
        }
        .width('100%')
        .backgroundColor($r('sys.color.comp_background_list_card'))
        .borderRadius(OCLayout.chipRadius)
        .clip(true)
      }
      Text(`Zone ID · ${this.zoneId}`)
        .fontSize(11)
        .fontFamily('monospace')
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 4 })
        .onClick(() => {
          this.copyText(this.zoneId);
        })
    }
    .width('100%')
  }

  @Builder
  moduleSection(section: ModuleSection) {
    Column({ space: 8 }) {
      Text(section.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .padding({ left: 4 })
      Column() {
        ForEach(section.entries, (entry: ModuleEntry, index: number) => {
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
              const param: ZoneRouteParam = { zoneId: this.zoneId, zoneName: this.zoneName };
              this.pathStack?.pushPathByName(entry.route, param);
            },
          })
          if (index < section.entries.length - 1) {
            Divider()
              .strokeWidth(0.5)
              .color($r('sys.color.comp_divider'))
              .margin({ left: 64 })
          }
        }, (entry: ModuleEntry) => entry.route)
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .borderRadius(OCLayout.chipRadius)
      .clip(true)
    }
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: 22 }) {
          // Hero / 分析 / 各分组岛按视觉顺序错峰浮现
          RevealBox({ idx: 0 }) {
            this.heroCard()
          }

          // 内嵌流量分析（对照 iOS ZoneDetailView 的 ZoneAnalyticsSection）
          RevealBox({ idx: 1 }) {
            Column({ space: 10 }) {
              SectionTitle({ title: '分析' })
              ZoneAnalyticsSection({ zoneId: this.zoneId, pathStack: this.pathStack })
            }
            .width('100%')
          }

          ForEach(SECTIONS, (section: ModuleSection, index: number) => {
            RevealBox({ idx: 2 + index }) {
              this.moduleSection(section)
            }
          }, (section: ModuleSection) => section.title)

          this.identitySection()

          Button(this.isPurging ? '正在清除缓存…' : '清除全部缓存')
            .width('100%')
            .height(46)
            .fontSize(15)
            .fontColor('#DC2626')
            .backgroundColor($r('sys.color.comp_background_list_card'))
            .borderRadius(OCLayout.chipRadius)
            .enabled(!this.isPurging)
            .margin({ bottom: 8 })
            .onClick(() => {
              this.confirmPurge();
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
    .titleBar({ content: { title: { mainTitle: this.zoneName } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      // 固定域名列表兜底加载（通常已由 Dashboard / 域名列表载入，幂等）
      accountStore.loadIfNeeded().then(() => {
        pinnedZones.loadFor(accountStore.selectedId).catch(() => {
        });
      }).catch(() => {
      });
      // 拉 zone 详情补 hero 的状态/套餐
      this.zoneService.fetchZone(param.zoneId).then((zone: Zone) => {
        this.zoneStatus = zoneDisplayStatus(zone);
        this.zonePlan = zone.plan?.name ?? '';
        this.zoneNameServers = zone.name_servers ?? [];
      }).catch(() => {
      });
    })
  }
}
