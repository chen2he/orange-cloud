// 页面主操作（新建 / 添加）统一走 UI Design Kit 的核心操作栏 HdsActionBar：
// 按钮本身是一枚「＋」圆钮（不带文字），但位置交给 HdsActionBar——贴底、居中、
// 落在拇指可达区，也不会被悬浮页签栏盖住（这正是原来右下角自绘 FAB 的问题）。
// label 只用于无障碍朗读，不上屏。
// 用法：OCAddActionBar({ label: '添加域名', onTap: () => { … } })
import { ActionBarButton, HdsActionBar } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';

/// 操作栏自身占用的底部净空（圆钮 56 + 上下留白）；页面可滚动内容要在底部让出这段。
export const OC_ACTION_BAR_CLEARANCE: number = 84;

/// 圆钮直径
const FAB_SIZE: number = 56;

@ComponentV2
export struct OCAddActionBar {
  @Param label: string = '新建';
  @Param onTap: () => void = () => {
  };

  @Builder
  primary() {
    Stack() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(26)
        .fontColor([Color.White])
    }
    .width(FAB_SIZE)
    .height(FAB_SIZE)
    .backgroundColor($r('app.color.oc_brand_cta'))
    .borderRadius(FAB_SIZE / 2)
    .accessibilityText(this.label)
    .onClick(() => {
      this.onTap();
    })
  }

  build() {
    HdsActionBar({
      primaryButton: new ActionBarButton({ }),
      primaryButtonBuilder: () => {
        this.primary()
      },
      primaryButtonBuilderWidth: LengthMetrics.vp(FAB_SIZE),
    })
  }
}
