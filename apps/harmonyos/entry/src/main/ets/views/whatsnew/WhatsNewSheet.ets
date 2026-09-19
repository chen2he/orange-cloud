// 「新功能」半模态（晨昏风，对照 iOS WhatsNewView）：标题 + 版本号 + 图标条目 + 「继续」。
// 由 MainShell 在登录后评估并弹出；触发口径见 core/whatsnew/WhatsNew.ets。
//
// 收起方式无论是点「继续」还是下拉，宿主都会写 lastSeen——不靠按钮保证「只弹一次」。
import { WhatsNewItem } from '../../core/whatsnew/WhatsNew';
import { appVersionName } from '../../core/system/AppVersion';
import { BRAND_ORANGE, BRAND_ORANGE_BG } from '../common/Components';
import { OCLayout } from '../common/Daybreak';

/// 「新功能」专用半模态配置：大档单档、不给关闭按钮（正常路径走「继续」），
/// 但保留拖拽条，避免用户被困在弹窗里。
export function whatsNewSheetOptions(onDisappear: () => void): SheetOptions {
  const opts: SheetOptions = {
    detents: [SheetSize.LARGE],
    preferType: SheetType.BOTTOM,
    dragBar: true,
    showClose: false,
    backgroundColor: $r('sys.color.background_secondary'),
    onDisappear: onDisappear,
  };
  return opts;
}

@ComponentV2
export struct WhatsNewSheet {
  @Param @Require items: WhatsNewItem[];
  @Event onContinue: () => void = () => {
  };

  build() {
    Column() {
      Scroll() {
        Column({ space: 28 }) {
          Column({ space: 6 }) {
            Text('新功能')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font_primary'))
            Text(`版本 ${appVersionName()}`)
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding({ top: 24 })

          Column({ space: 24 }) {
            ForEach(this.items, (item: WhatsNewItem, index: number) => {
              Row({ space: 16 }) {
                Stack() {
                  SymbolGlyph(item.symbol)
                    .fontSize(24)
                    .fontColor([$r('app.color.oc_brand_text')])
                }
                .width(44)
                .height(44)
                .backgroundColor($r('app.color.oc_brand_bg'))
                .borderRadius(12)

                Column({ space: 4 }) {
                  Text(item.title)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('sys.color.font_primary'))
                    .width('100%')
                  Text(item.detail)
                    .fontSize(13)
                    .fontColor($r('sys.color.font_secondary'))
                    .width('100%')
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            }, (item: WhatsNewItem, index: number) => `${index}-${item.title}`)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 24, right: 24, bottom: 16 })
      }
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .width('100%')

      Button('继续')
        .width('100%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .borderRadius(OCLayout.chipRadius)
        .margin({ left: 24, right: 24, bottom: 24 })
        .onClick(() => {
          this.onContinue();
        })
    }
    .width('100%')
    .height('100%')
  }
}
