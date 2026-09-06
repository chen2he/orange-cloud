// 登录页：HarmonyOS 系统底色 + 系统文字分层参数（深浅色由系统接管）。
// 「日出」半圆 + 地平线保留为品牌标记（不是整屏天色滤镜），是全 App 唯一的品牌图形。
import { common } from '@kit.AbilityKit';
import { authManager } from '../../core/auth/AuthManager';
import { PermissionSelectionSheet } from './PermissionSelectionSheet';
import { ocSheet } from '../common/Sheets';

@ComponentV2
export struct LoginView {
  /// 登录前先弹权限选择（对齐 iOS：先选 scope 再发起授权）
  @Local showPermissionSheet: boolean = false;


  private startLogin(scopes: string[]): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    authManager.login(context, scopes).catch(() => {
      // 错误已写入 authManager.error
    });
  }

  @Builder
  permissionSheet() {
    PermissionSelectionSheet({
      onConfirm: (scopes: string[]) => {
        this.showPermissionSheet = false;
        this.startLogin(scopes);
      },
    })
  }

  @Builder
  featureRow(icon: string, text: string) {
    Row({ space: 10 }) {
      Text(icon)
        .fontSize(15)
        .width(24)
        .textAlign(TextAlign.Center)
      Text(text)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 页面底：系统分层参数，深浅色自动切换
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('sys.color.background_primary'))

      // 地平线上的日出：太阳半升出地平线，脚下一道地平线（晨昏语言）
      Column() {
        // 太阳的下半沉在地平线下 → 半圆升起感；地平线压在其上
        Stack({ alignContent: Alignment.Bottom }) {
          Column() {
            // 只取上半圆：高 64 的容器裁下 128 圆的上半（无阴影，避免矩形辉光边）
            Circle({ width: 128, height: 128 })
              .fill($r('app.color.oc_brand'))
              .opacity(0.94)
          }
          .width(128)
          .height(64)
          .clip(true)

          // 地平线（横贯全宽，压在太阳脚下）
          Divider()
            .strokeWidth(1.5)
            .color('#59F48120')
            .width('82%')
        }
        .width('100%')
      }
      .width('100%')
      .padding({ bottom: 190 })

      Column() {
        Column({ space: 8 }) {
          Text('Orange Cloud')
            .fontSize(34)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
          Text('Cloudflare 随身管理')
            .fontSize(15)
            .fontColor($r('sys.color.font_secondary'))
        }
        .margin({ top: 96 })

        Column({ space: 14 }) {
          this.featureRow('🔐', '官方 OAuth 授权登录，无需手动粘贴 API Token')
          this.featureRow('🌐', '域名与 DNS 记录，随时随地查看')
          this.featureRow('🧡', '权限范围自己掌控，Token 仅存于本机安全存储')
        }
        .padding({ left: 36, right: 36 })
        .margin({ top: 44 })

        Blank()

        Column({ space: 12 }) {
          if (authManager.error !== '') {
            Text(authManager.error)
              .fontSize(13)
              .fontColor('#E84026')
              .textAlign(TextAlign.Center)
              .padding({ left: 24, right: 24 })
          }

          if (authManager.status === 'exchanging' || authManager.status === 'loading') {
            Row({ space: 10 }) {
              LoadingProgress()
                .width(22)
                .height(22)
                .color($r('sys.color.font_primary'))
              Text(authManager.status === 'exchanging' ? '正在登录…' : '正在恢复登录…')
                .fontSize(15)
                .fontColor($r('sys.color.font_primary'))
            }
            .height(48)
          } else {
            Button(authManager.status === 'authorizing' ? '等待浏览器授权，点按重试' : '使用 Cloudflare 登录')
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.oc_brand_cta'))
              .onClick(() => {
                this.showPermissionSheet = true;
              })

            if (authManager.status === 'authorizing') {
              Text('完成授权后会自动跳回 App')
                .fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
            }
          }
        }
        .padding({ left: 28, right: 28, bottom: 56 })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet(this.showPermissionSheet, this.permissionSheet(), ocSheet(() => {
      this.showPermissionSheet = false;
    }))
  }
}
