// 登录页：晨昏天空随本地时刻 + 明暗推导（对齐 iOS/Android 晨昏设计语言）。
// 天体用相位辉光；文本色按天色明暗自适应（深色天用暖白，浅色天用深棕）。
import { common } from '@kit.AbilityKit';
import { mediaquery } from '@kit.ArkUI';
import { authManager } from '../../core/auth/AuthManager';
import { SkyPhase, SkyPhaseColors } from '../../core/design/SkyPhase';
import { PermissionSelectionSheet } from './PermissionSelectionSheet';
import { ocSheet } from '../common/Sheets';

@ComponentV2
export struct LoginView {
  @Local phase: SkyPhase = SkyPhase.Day;
  /// 登录前先弹权限选择（对齐 iOS：先选 scope 再发起授权）
  @Local showPermissionSheet: boolean = false;

  aboutToAppear(): void {
    let isDark = false;
    try {
      const listener = mediaquery.matchMediaSync('(dark-mode: true)');
      isDark = listener.matches;
    } catch (e) {
      isDark = false;
    }
    this.phase = SkyPhaseColors.current(isDark, new Date().getHours());
  }

  private skyColors(): Array<[string, number]> {
    const body = SkyPhaseColors.body(this.phase);
    const stops: Array<[string, number]> = [];
    for (let i = 0; i < body.length; i++) {
      stops.push([body[i], body.length === 1 ? 0 : i / (body.length - 1)]);
    }
    return stops;
  }

  /// 天景之上的主文本色
  private onSky(): string {
    return SkyPhaseColors.isDark(this.phase) ? '#F3ECE4' : '#24190F';
  }

  private onSkyDim(): string {
    return SkyPhaseColors.isDark(this.phase) ? '#B3F3ECE4' : '#9924190F';
  }

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
        .fontColor(this.onSkyDim())
    }
    .width('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 天空：随相位的天色渐变
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: this.skyColors(),
        })

      // 地平线上的日出：太阳半升出地平线，脚下一道地平线（晨昏语言）
      Column() {
        // 太阳的下半沉在地平线下 → 半圆升起感；地平线压在其上
        Stack({ alignContent: Alignment.Bottom }) {
          Column() {
            // 只取上半圆：高 64 的容器裁下 128 圆的上半（无阴影，避免矩形辉光边）
            Circle({ width: 128, height: 128 })
              .fill('#F48120')
              .opacity(SkyPhaseColors.isDark(this.phase) ? 0.96 : 0.92)
          }
          .width(128)
          .height(64)
          .clip(true)

          // 地平线（横贯全宽，压在太阳脚下）
          Divider()
            .strokeWidth(1.5)
            .color(SkyPhaseColors.isDark(this.phase) ? '#59F48120' : '#59C2502A')
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
            .fontColor(this.onSky())
          Text('Cloudflare 随身管理')
            .fontSize(15)
            .fontColor(this.onSkyDim())
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
              .fontColor(SkyPhaseColors.isDark(this.phase) ? '#FFD9C2' : '#B3401200')
              .textAlign(TextAlign.Center)
              .padding({ left: 24, right: 24 })
          }

          if (authManager.status === 'exchanging' || authManager.status === 'loading') {
            Row({ space: 10 }) {
              LoadingProgress()
                .width(22)
                .height(22)
                .color(this.onSky())
              Text(authManager.status === 'exchanging' ? '正在登录…' : '正在恢复登录…')
                .fontSize(15)
                .fontColor(this.onSky())
            }
            .height(48)
          } else {
            Button(authManager.status === 'authorizing' ? '等待浏览器授权，点按重试' : '使用 Cloudflare 登录')
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor('#F48120')
              .onClick(() => {
                this.showPermissionSheet = true;
              })

            if (authManager.status === 'authorizing') {
              Text('完成授权后会自动跳回 App')
                .fontSize(12)
                .fontColor(this.onSkyDim())
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
