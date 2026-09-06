// 存储 Tab（对照 iOS StorageView）：大标题「存储」+ 玻璃岛入口列表。
// 整个 Tab 是 Pro 功能：非 Pro 时列表换成锁定态，不做半截可用的假象。
import { Routes } from '../../models/Routes';
import { tabBarScroll } from '../common/PlatformCompat';
import { NavRow } from '../common/Components';
import { OCLayout } from '../common/Daybreak';
import { entitlement, EntitlementStore } from '../../core/purchase/EntitlementStore';
import { ProLockedView, requirePro } from '../paywall/ProGate';

interface StorageEntry {
  symbol: Resource;
  title: string;
  subtitle: string;
  route: string;
}

const ENTRIES: StorageEntry[] = [
  { symbol: $r('sys.symbol.externaldrive'), title: 'R2 对象存储', subtitle: '存储桶与对象浏览', route: Routes.R2_BUCKETS },
  { symbol: $r('sys.symbol.square_stack_3d'), title: 'D1 数据库', subtitle: 'SQL 控制台与表浏览', route: Routes.D1_DATABASES },
  { symbol: $r('sys.symbol.key'), title: 'KV 键值存储', subtitle: '命名空间与键值管理', route: Routes.KV_NAMESPACES },
];

@ComponentV2
export struct StorageHubView {
  @Require @Param pathStack: NavPathStack;
  /// 观察权益：购买后本页即时从锁定态翻回入口列表
  @Local entitlements: EntitlementStore = entitlement;

  @Builder
  entryList() {
    Scroll() {
      Column({ space: 8 }) {
        Text('账户级存储')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 4 })
        Column() {
          ForEach(ENTRIES, (entry: StorageEntry, index: number) => {
            NavRow({
              symbol: entry.symbol,
              title: entry.title,
              subtitle: entry.subtitle,
              onNav: () => {
                this.pathStack.pushPathByName(entry.route, null);
              },
            })
            if (index < ENTRIES.length - 1) {
              Divider()
                .strokeWidth(0.5)
                .color($r('sys.color.comp_divider'))
                .margin({ left: 64 })
            }
          }, (entry: StorageEntry) => entry.route)
        }
        .width('100%')
        .backgroundColor($r('sys.color.comp_background_list_card'))
        .borderRadius(OCLayout.chipRadius)
        .clip(true)
      }
      .width('100%')
      .padding({ left: OCLayout.pagePadding, right: OCLayout.pagePadding, bottom: 24 })
    }
    .align(Alignment.Top)
    .onDidScroll((dx: number, dy: number) => { tabBarScroll.notifyScroll(dy); })
    .scrollBar(BarState.Off)
    .layoutWeight(1)
  }

  build() {
    Column() {
      Text('存储')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .padding({ left: OCLayout.pagePadding, right: OCLayout.pagePadding, top: 8, bottom: 8 })
        // 大标题上滑收起：随浮栏同步的滚动状态折叠+淡出
        .height(tabBarScroll.hidden ? 0 : 56)
        .opacity(tabBarScroll.hidden ? 0 : 1)
        .clip(true)
        .animation({ duration: 250, curve: Curve.EaseInOut })

      if (!this.entitlements.isPro) {
        ProLockedView({
          symbol: $r('sys.symbol.externaldrive'),
          title: '存储是 Pro 功能',
          message: 'R2 对象存储、D1 数据库与 KV 键值管理属于 Orange Cloud Pro。解锁后可在手机上浏览存储桶、跑 SQL、读写键值。',
          onUnlock: () => {
            requirePro(this.pathStack, '存储');
          },
        })
      } else {
        this.entryList()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
