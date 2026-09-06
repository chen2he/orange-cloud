// 身份详情：重命名 / 已授权 scope 列表 / 升级授权（补齐缺失模块）/ 退出该身份
//（对齐 iOS IdentityDetailView 的「升级授权」区 + Android IdentityDetailScreen）。
import { common } from '@kit.AbilityKit';
import { authManager, AuthSessionMeta } from '../../core/auth/AuthManager';
import { ScopeModule, Scopes } from '../../core/auth/Scopes';
import { BRAND_ORANGE, InfoRow } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';
import { OCLayout } from '../common/Daybreak';

@ComponentV2
export struct IdentityDetailPage {
  @Local sessionId: string = '';
  @Local editingLabel: string = '';
  private pathStack: NavPathStack | null = null;

  private meta(): AuthSessionMeta | undefined {
    return authManager.sessions.find((s: AuthSessionMeta) => s.id === this.sessionId);
  }

  private grantedScopes(): string[] {
    return (this.meta()?.scope ?? '').split(' ').filter((s: string) => s !== '');
  }

  /// 该身份读写都未授予的功能模块 → 可一键补齐（对齐 iOS upgradeableFeatures）
  private missingModules(): ScopeModule[] {
    const granted = this.grantedScopes();
    return Scopes.modules.filter((module: ScopeModule) => {
      const hasRead = module.readScopes.some((s: string) => granted.includes(s));
      const hasWrite = module.writeScopes.some((s: string) => granted.includes(s));
      return !hasRead && !hasWrite;
    });
  }

  /// 补齐 missingModules 需要并入的 scope 全集（读 + 写）
  private upgradeScopes(): string[] {
    const scopes: string[] = [];
    for (const module of this.missingModules()) {
      for (const s of Scopes.moduleScopes(module)) {
        if (!scopes.includes(s)) {
          scopes.push(s);
        }
      }
    }
    return scopes;
  }

  private isReauthorizing(): boolean {
    return authManager.reauthSessionId === this.sessionId;
  }

  /// 补齐授权：原 scope ∪ 所缺 scope，原地重授权同一身份（不退出登录、不新建账号）
  private startUpgrade(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    authManager.reauthorize(context, this.sessionId, this.upgradeScopes()).catch(() => {
      // 错误已写入 authManager.reauthError
    });
  }

  private confirmRemove(): void {
    this.getUIContext().showAlertDialog({
      title: '退出该身份',
      message: '将撤销此身份的授权并清除本机 Token。',
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '退出',
        fontColor: '#DC2626',
        action: () => {
          const stack = this.pathStack;
          authManager.removeSession(this.sessionId).then(() => {
            stack?.pop();
          }).catch(() => {
          });
        },
      },
    });
  }

  // 分组小标签（对照样板 ZoneDetailPage 的组头）
  @Builder
  groupHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 4 })
  }

  /// Hero 卡（对照 iOS IdentityDetailView 顶部：橙渐变字母头像 + 显示名大字 + OAuth 2.0 绿徽章）
  @Builder
  heroCard() {
    Column({ space: 10 }) {
      Text((this.meta()?.label ?? 'C').substring(0, 1).toUpperCase())
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .width(56)
        .height(56)
        .borderRadius(28)
        .linearGradient({
          angle: 135,
          colors: [['#FFA64F', 0.0], ['#D96A0F', 1.0]],
        })

      Text(this.meta()?.label ?? '')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 8 }) {
        Row({ space: 5 }) {
          Circle({ width: 7, height: 7 })
            .fill('#22C55E')
          Text('OAuth 2.0')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#22C55E')
        }
        Text(`${this.grantedScopes().length} 项权限`)
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
      }
    }
    .width('100%')
    .padding(OCLayout.islandPadding)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(OCLayout.islandRadius)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        Scroll() {
          Column({ space: 18 }) {
            this.heroCard()

            Column({ space: 8 }) {
              this.groupHeader('标签')
              Row({ space: 10 }) {
                TextInput({ text: this.editingLabel, placeholder: '身份显示名' })
                  .fontSize(15)
                  .layoutWeight(1)
                  .onChange((value: string) => {
                    this.editingLabel = value;
                  })
                Button('保存')
                  .fontSize(14)
                  .fontColor(Color.White)
                  .backgroundColor(BRAND_ORANGE)
                  .enabled(this.editingLabel.trim() !== '')
                  .onClick(() => {
                    authManager.renameSession(this.sessionId, this.editingLabel.trim()).then(() => {
                      this.getUIContext().getPromptAction().showToast({ message: '已保存' });
                    });
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(OCLayout.chipRadius)
              .border({ width: 0.5, color: $r('sys.color.comp_divider') })
              .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
            }
            .width('100%')

            Column({ space: 8 }) {
              this.groupHeader('身份信息')
              Column() {
                InfoRow({ label: '身份 ID', value: this.sessionId })
                InfoRow({
                  label: '添加时间',
                  value: new Date(this.meta()?.createdAtMs ?? 0).toLocaleString(),
                })
              }
              .width('100%')
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(OCLayout.chipRadius)
              .border({ width: 0.5, color: $r('sys.color.comp_divider') })
              .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
              .clip(true)
            }
            .width('100%')

            Column({ space: 8 }) {
              this.groupHeader(`已授权权限（${this.grantedScopes().length}）`)
              Column() {
                ForEach(this.grantedScopes(),
                  (scope: string) => {
                    Text(scope)
                      .fontSize(12)
                      .fontColor($r('sys.color.font_secondary'))
                      .width('100%')
                      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                  }, (scope: string) => scope)
              }
              .width('100%')
              .padding({ top: 6, bottom: 6 })
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(OCLayout.chipRadius)
              .border({ width: 0.5, color: $r('sys.color.comp_divider') })
              .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
              .clip(true)
            }
            .width('100%')

            // ── 升级授权：缺 refresh token 或有未授予模块时展示 ──
            if (authManager.needsReauth(this.sessionId) || this.missingModules().length > 0) {
              Column({ space: 8 }) {
                this.groupHeader('升级授权')
                Column() {
                  if (authManager.needsReauth(this.sessionId)) {
                    Row({ space: 8 }) {
                      Text('⚠️')
                        .fontSize(14)
                      Text('登录授权已失效（缺少长期授权），到期后将无法自动续期')
                        .fontSize(13)
                        .fontColor($r('sys.color.font_primary'))
                        .layoutWeight(1)
                    }
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
                  }
                  ForEach(this.missingModules(), (module: ScopeModule) => {
                    Row({ space: 10 }) {
                      Text(module.icon)
                        .fontSize(14)
                        .width(22)
                        .textAlign(TextAlign.Center)
                      Text(module.title)
                        .fontSize(14)
                        .fontColor($r('sys.color.font_primary'))
                        .layoutWeight(1)
                      Text('未授权')
                        .fontSize(12)
                        .fontColor($r('sys.color.font_tertiary'))
                    }
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 7, bottom: 7 })
                  }, (module: ScopeModule) => module.id)

                  Divider()
                    .strokeWidth(0.5)
                    .color($r('sys.color.comp_divider'))
                    .margin({ left: 16, right: 16 })

                  Row({ space: 8 }) {
                    if (this.isReauthorizing()) {
                      LoadingProgress()
                        .width(18)
                        .height(18)
                        .color(BRAND_ORANGE)
                      Text('等待浏览器授权…')
                        .fontSize(14)
                        .fontColor($r('sys.color.font_secondary'))
                    } else {
                      Text(this.missingModules().length > 0 ? '🔓 补齐授权' : '🔓 重新授权')
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.oc_brand_text'))
                    }
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.Center)
                  .padding({ top: 12, bottom: 12 })
                  .onClick(() => {
                    if (!this.isReauthorizing()) {
                      this.startUpgrade();
                    }
                  })

                  if (authManager.reauthError !== '') {
                    Text(authManager.reauthError)
                      .fontSize(12)
                      .fontColor('#DC2626')
                      .width('100%')
                      .padding({ left: 16, right: 16, bottom: 10 })
                  }
                }
                .width('100%')
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(OCLayout.chipRadius)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
                .clip(true)

                Text('补齐授权会跳转浏览器重新授权当前账号，无需退出登录；请务必使用原账号完成授权。')
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                  .width('100%')
                  .padding({ left: 4, right: 4 })
              }
              .width('100%')
            }

            // 危险区（对照样板底部红色危险操作）
            Button('退出该身份')
              .width('100%')
              .height(46)
              .fontSize(15)
              .fontColor('#DC2626')
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(OCLayout.chipRadius)
              .border({ width: 0.5, color: $r('sys.color.comp_divider') })
              .margin({ bottom: 8 })
              .onClick(() => {
                this.confirmRemove();
              })
          }
          .width('100%')
          .padding(OCLayout.pagePadding)
        }
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
    }
    .title('身份管理')
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.sessionId = context.pathInfo.param as string;
      this.editingLabel = this.meta()?.label ?? '';
    })
  }
}
