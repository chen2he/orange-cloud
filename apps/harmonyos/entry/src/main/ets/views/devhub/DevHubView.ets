// 开发 Tab（对照 iOS DeveloperHubView）：大标题「开发者平台」+ 分组玻璃岛列表。
// 分组顺序与 iOS 一致：计算 / 数据与消息 / AI。
// Workers 免费（只按 scope 门控），其余入口均为 Pro——与 iOS DeveloperHubView 的
// ProGatedNavigationLink 一一对应。
import { Routes } from '../../models/Routes';
import { tabBarScroll } from '../common/PlatformCompat';
import { NavRow } from '../common/Components';
import { OCLayout } from '../common/Daybreak';
import { entitlement, EntitlementStore } from '../../core/purchase/EntitlementStore';
import { requirePro } from '../paywall/ProGate';

interface DevEntry {
  symbol: Resource;
  title: string;
  subtitle: string;
  route: string;
  /// Pro 闸门场景名（空 = 免费可用）
  feature?: string;
}

interface DevSection {
  title: string;
  entries: DevEntry[];
}

const SECTIONS: DevSection[] = [
  {
    title: '计算',
    entries: [
      { symbol: $r('sys.symbol.bolt'), title: 'Workers', subtitle: '脚本列表 / 配置 / 实时日志', route: Routes.WORKERS },
      {
        symbol: $r('sys.symbol.doc_text'), title: 'Cloudflare Pages', subtitle: '项目 / 部署 / 自定义域名',
        route: Routes.PAGES, feature: 'Cloudflare Pages',
      },
    ],
  },
  {
    title: '数据与消息',
    entries: [
      {
        symbol: $r('sys.symbol.rectangle_stack'), title: 'Queues', subtitle: '消息队列',
        route: Routes.DEV_QUEUES, feature: 'Queues',
      },
      {
        symbol: $r('sys.symbol.square_stack_3d'), title: 'Durable Objects', subtitle: '命名空间与对象实例',
        route: Routes.DEV_DO, feature: 'Durable Objects',
      },
      {
        symbol: $r('sys.symbol.externaldrive'), title: 'Hyperdrive', subtitle: '数据库加速配置',
        route: Routes.DEV_HYPERDRIVE, feature: 'Hyperdrive',
      },
    ],
  },
  {
    title: 'AI',
    entries: [
      {
        symbol: $r('sys.symbol.wand_and_stars'), title: 'Workers AI', subtitle: '模型目录与试运行',
        route: Routes.DEV_AI, feature: 'Workers AI',
      },
      {
        symbol: $r('sys.symbol.wand_and_stars'), title: 'AI Gateway', subtitle: '网关列表与用量',
        route: Routes.DEV_AI_GATEWAY, feature: 'AI Gateway',
      },
    ],
  },
];

@ComponentV2
export struct DevHubView {
  @Require @Param pathStack: NavPathStack;
  /// 观察权益：购买后各入口的 Pro 徽章即时消失
  @Local entitlements: EntitlementStore = entitlement;

  @Builder
  section(sec: DevSection) {
    Column({ space: 8 }) {
      Text(sec.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .padding({ left: 4 })
      Column() {
        ForEach(sec.entries, (entry: DevEntry, index: number) => {
          NavRow({
            symbol: entry.symbol,
            title: entry.title,
            subtitle: entry.subtitle,
            locked: entry.feature !== undefined && !this.entitlements.isPro,
            onNav: () => {
              const feature = entry.feature ?? '';
              if (feature !== '' && !requirePro(this.pathStack, feature)) {
                return;
              }
              this.pathStack.pushPathByName(entry.route, null);
            },
          })
          if (index < sec.entries.length - 1) {
            Divider()
              .strokeWidth(0.5)
              .color($r('sys.color.comp_divider'))
              .margin({ left: 64 })
          }
        }, (entry: DevEntry) => entry.route)
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

  build() {
    Column() {
      Text('开发者平台')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .padding({ left: OCLayout.pagePadding, right: OCLayout.pagePadding, top: 8, bottom: 8 })
        // 大标题上滑收起
        .height(tabBarScroll.hidden ? 0 : 56)
        .opacity(tabBarScroll.hidden ? 0 : 1)
        .clip(true)
        .animation({ duration: 250, curve: Curve.EaseInOut })

      Scroll() {
        Column({ space: 18 }) {
          ForEach(SECTIONS, (sec: DevSection) => {
            this.section(sec)
          }, (sec: DevSection) => sec.title)
        }
        .width('100%')
        .padding({ left: OCLayout.pagePadding, right: OCLayout.pagePadding, bottom: 24 })
      }
      .align(Alignment.Top)
      .onDidScroll((dx: number, dy: number) => { tabBarScroll.notifyScroll(dy); })
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
