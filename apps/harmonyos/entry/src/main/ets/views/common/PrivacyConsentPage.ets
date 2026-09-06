// 首次启动隐私合规同意页（AppGallery 审核要求：进入 App 前展示隐私政策并取得同意）。
// 同意前不发起任何网络请求（Index 在同意后才调 authManager.bootstrap）。
import { common } from '@kit.AbilityKit';
import { GlobalContext } from '../../core/system/GlobalContext';
import { OCSkyBackground } from './OCSky';
import { GlassIsland, OCLayout } from './Daybreak';
import { BRAND_ORANGE } from './Components';

const PRIVACY_URL = 'https://o-c.do/privacy';
const TERMS_URL = 'https://o-c.do/terms';

interface ConsentPoint {
  icon: string;
  text: string;
}

const CONSENT_POINTS: ConsentPoint[] = [
  { icon: '🔑', text: '本应用不注册自有账号，登录使用 Cloudflare 官方 OAuth 授权，访问令牌仅加密保存在本机' } as ConsentPoint,
  { icon: '🌐', text: '网络请求仅发往 Cloudflare API 与本应用官网 o-c.do（登录回调中转），用于实现产品功能' } as ConsentPoint,
  { icon: '🚫', text: '不接入任何第三方统计 / 广告 SDK，不收集设备标识，不向第三方共享个人信息' } as ConsentPoint,
  { icon: '✉️', text: '「帮助与反馈」经你的邮件应用发送，内容与是否发送完全由你决定' } as ConsentPoint,
];

@ComponentV2
export struct PrivacyConsentPage {
  /// 用户点「同意并继续」后回调（由 Index 落盘标记并继续启动）
  @Param onAccept: () => void = () => {};

  private openLink(target: string): void {
    GlobalContext.get().openLink(target).catch(() => {
      // 打不开浏览器时静默；正文已含完整域名可手动访问
    });
  }

  private exitApp(): void {
    const context = GlobalContext.get() as common.UIAbilityContext;
    context.terminateSelf();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      OCSkyBackground()
      Column({ space: OCLayout.islandGap }) {
        Blank().layoutWeight(1)
        Text('欢迎使用 Orange Cloud')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Text('在开始之前，请了解我们如何对待你的信息')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .margin({ bottom: 4 })

        GlassIsland() {
          Column({ space: 14 }) {
            ForEach(CONSENT_POINTS, (p: ConsentPoint) => {
              Row({ space: 10 }) {
                Text(p.icon).fontSize(18)
                Text(p.text)
                  .fontSize(13)
                  .fontColor($r('sys.color.font_primary'))
                  .lineHeight(19)
                  .layoutWeight(1)
              }
              .alignItems(VerticalAlign.Top)
              .width('100%')
            }, (p: ConsentPoint) => p.text)
          }
          .width('100%')
        }

        Row() {
          Text('详见 ')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
          Text('《隐私政策》')
            .fontSize(13)
            .fontColor(BRAND_ORANGE)
            .onClick(() => {
              this.openLink(PRIVACY_URL);
            })
          Text(' 与 ')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
          Text('《使用条款》')
            .fontSize(13)
            .fontColor(BRAND_ORANGE)
            .onClick(() => {
              this.openLink(TERMS_URL);
            })
        }
        .margin({ top: 2 })

        Blank().layoutWeight(1)

        Button('同意并继续')
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(BRAND_ORANGE)
          .borderRadius(OCLayout.islandRadius)
          .onClick(() => {
            this.onAccept();
          })
        Button('不同意并退出')
          .width('100%')
          .height(44)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.exitApp();
          })
      }
      .padding({ left: 24, right: 24, top: 24, bottom: 34 })
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
