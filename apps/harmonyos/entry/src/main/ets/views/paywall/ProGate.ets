// Pro 闸门（对齐 iOS 的场景付费墙）：闸门只挂在场景入口，不在设置页拦人。
// 用法：if (!requirePro(pathStack, '实时日志')) { return; } —— 非 Pro 会推付费墙并拦下本次操作。
import { PaywallParam, Routes } from '../../models/Routes';
import { entitlement } from '../../core/purchase/EntitlementStore';
import { BRAND_ORANGE, BRAND_ORANGE_BG } from '../common/Components';
import { OCLayout } from '../common/Daybreak';

/// 已是 Pro 返回 true 放行；否则推付费墙（带场景名）并返回 false
export function requirePro(pathStack: NavPathStack | null, feature: string): boolean {
  if (entitlement.isPro) {
    return true;
  }
  const param: PaywallParam = { feature: feature };
  pathStack?.pushPathByName(Routes.PAYWALL, param);
  return false;
}

/// 整页锁定态（存储 Tab 用）：说明这是什么、为什么锁，一个按钮直达付费墙。
/// 不做半截可用的假象——锁就锁全页，避免用户以为加载失败。
@ComponentV2
export struct ProLockedView {
  @Param symbol: Resource | null = null;
  @Param title: string = '';
  @Param message: string = '';
  @Param onUnlock: () => void = () => {
  };

  build() {
    Column({ space: 14 }) {
      if (this.symbol !== null) {
        Stack() {
          SymbolGlyph(this.symbol)
            .fontSize(34)
            .fontColor([BRAND_ORANGE])
        }
        .width(72)
        .height(72)
        .backgroundColor(BRAND_ORANGE_BG)
        .borderRadius(20)
      }
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
      Text(this.message)
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .lineHeight(20)
        .padding({ left: 36, right: 36 })
      Button('了解 Orange Cloud Pro')
        .height(44)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .backgroundColor(BRAND_ORANGE)
        .borderRadius(OCLayout.chipRadius)
        .padding({ left: 24, right: 24 })
        .margin({ top: 4 })
        .onClick(() => {
          this.onUnlock();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}
