// 重授权横幅：橙色警示玻璃卡（对齐 iOS 缺 refresh token 的重授权引导）。
// 会话缺 refresh token（authManager.needsReauth）时挂在 Dashboard 顶部提醒用户原地重授权。
// 本波只创建组件，挂载接线（DashboardView 等）由下一波完成。
// 建议挂载条件：authManager.needsReauth(authManager.currentSessionId)。
import { common } from '@kit.AbilityKit';
import { authManager } from '../../core/auth/AuthManager';
import { BRAND_ORANGE } from './Components';
import { OCLayout } from './Daybreak';

@ComponentV2
export struct ReauthBanner {
  /// 目标身份 id；空串 = 当前身份
  @Param sessionId: string = '';

  private targetId(): string {
    return this.sessionId !== '' ? this.sessionId : authManager.currentSessionId;
  }

  private isWorking(): boolean {
    const target = this.targetId();
    return target !== '' && authManager.reauthSessionId === target;
  }

  private startReauthorize(): void {
    const target = this.targetId();
    if (target === '' || this.isWorking()) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 全量原 scope + offline_access（union 与追加都在 AuthManager 内完成）
    authManager.reauthorize(context, target).catch(() => {
      // 错误已写入 authManager.reauthError
    });
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Text('⚠️')
          .fontSize(18)
        Column({ space: 2 }) {
          Text('登录授权已失效，部分功能受限')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          Text('重新授权后可恢复自动续期，无需退出登录')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.isWorking()) {
          Row({ space: 6 }) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(Color.White)
            Text('授权中')
              .fontSize(13)
              .fontColor(Color.White)
          }
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor('#B3F48120')
          .borderRadius(OCLayout.chipRadius)
        } else {
          Text('重新授权')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .backgroundColor($r('app.color.oc_brand_cta'))
            .borderRadius(OCLayout.chipRadius)
            .onClick(() => {
              this.startReauthorize();
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (authManager.reauthError !== '') {
        Text(authManager.reauthError)
          .fontSize(12)
          .fontColor('#DC2626')
          .width('100%')
      }
    }
    .width('100%')
    .padding(OCLayout.islandPadding)
    .backgroundColor('#26F48120')
    .borderRadius(OCLayout.islandRadius)
    .border({ width: 0.5, color: '#59F48120' })
  }
}
