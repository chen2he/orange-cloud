import { systemMaterial, OC_TITLE_BAR_INSET } from './Effects';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 兜底页：路由已定义但模块尚未落地时展示（分批移植期间的中间态）。
import { OCEmpty } from './Components';

@ComponentV2
export struct ComingSoonPage {
  build() {
    HdsNavDestination() {
      Column() {
        OCEmpty({ symbol: $r('sys.symbol.wrench_and_screwdriver'), title: '模块开发中', subtitle: '正在从 Android 版对齐移植' })
      }
      .width('100%')
      .height('100%')
      .padding({ top: OC_TITLE_BAR_INSET })
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: '开发中' } } })
    .backgroundColor($r('sys.color.background_secondary'))
  }
}
