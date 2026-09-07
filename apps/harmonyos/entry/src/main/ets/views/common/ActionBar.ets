// 页面主操作（新建 / 添加）统一走 UI Design Kit 的核心操作栏 HdsActionBar：
// 贴底的宽按钮落在拇指可达区，比右下角圆形 FAB 更好够；在 Tab 页里还能避开悬浮页签栏。
// 用法：OCAddActionBar({ label: '添加域名', onTap: () => { … } })
import { ActionBarButton, HdsActionBar } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';

/// 操作栏自身占用的底部净空（按钮高 44 + 上下留白）；页面可滚动内容要在底部让出这段。
export const OC_ACTION_BAR_CLEARANCE: number = 76;

@ComponentV2
export struct OCAddActionBar {
  @Param label: string = '新建';
  @Param onTap: () => void = () => {
  };

  @Builder
  primary() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(18)
        .fontColor([Color.White])
      Text(this.label)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
    }
    .justifyContent(FlexAlign.Center)
    .width(220)
    .height(44)
    .backgroundColor($r('app.color.oc_brand_cta'))
    .borderRadius(22)
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
      primaryButtonBuilderWidth: LengthMetrics.vp(220),
    })
  }
}
