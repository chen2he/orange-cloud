import { HdsNavDestination } from '@kit.UIDesignKit';
// 添加账号：应用内无痕 Web 授权（对齐 Android WebAuthActivity）。
// incognito 模式不共享系统浏览器 Cookie，避免复用上一身份；
// onLoadIntercept 拦截 orangecloud:// 回跳直接喂给 AuthManager。
// 进入本页先弹权限选择 sheet（对齐 iOS 添加账号也走 PermissionSelectionView），
// 按选中 scope 重建授权 URL（SettingsView 传入的预构建全量 URL 不再直接加载）。
import { webview } from '@kit.ArkWeb';
import { authManager } from '../../core/auth/AuthManager';
import { OAuthConfig } from '../../core/auth/OAuthConfig';
import { PermissionSelectionSheet } from './PermissionSelectionSheet';
import { ocSheet } from '../common/Sheets';

@ComponentV2
export struct WebAuthPage {
  @Local authURL: string = '';
  @Local showSelection: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private pathStack: NavPathStack | null = null;
  private handled: boolean = false;
  /// 权限选择已确认（区分「确认关闭」与「取消关闭 → 退回设置页」）
  private confirmed: boolean = false;

  @Builder
  permissionSheet() {
    PermissionSelectionSheet({
      confirmLabel: '继续授权',
      onConfirm: (scopes: string[]) => {
        this.confirmed = true;
        this.showSelection = false;
        authManager.buildAuthorizeURL(scopes).then((authURL: string) => {
          this.authURL = authURL;
        }).catch(() => {
          // 重建失败时不能用预构建 URL 兜底（其 PKCE pending 已被覆盖，交换必失败），退回设置页
          this.pathStack?.pop();
        });
      },
    })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        if (this.authURL !== '') {
          Web({ src: this.authURL, controller: this.controller, incognitoMode: true })
            .width('100%')
            .height('100%')
            .onLoadIntercept((event) => {
              const requestURL = event.data.getRequestUrl();
              if (requestURL.startsWith(OAuthConfig.callbackPrefix)) {
                if (!this.handled) {
                  this.handled = true;
                  authManager.isAddingAccount = true;
                  authManager.handleOAuthCallback(requestURL).catch(() => {
                  });
                  this.pathStack?.pop();
                }
                return true;
              }
              return false;
            })
        } else {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(32)
              .height(32)
              .color($r('app.color.oc_brand'))
            Text('选择授权范围后继续')
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
      .bindSheet(this.showSelection, this.permissionSheet(), ocSheet(() => {
        this.showSelection = false;
        // 未确认就关掉选择 = 放弃添加账号，退回设置页
        if (!this.confirmed) {
          this.pathStack?.pop();
        }
      }))
    }
    .titleBar({ content: { title: { mainTitle: '添加账号' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      // SettingsView 传入的预构建全量 URL 不再直接使用——先弹权限选择、按所选 scope 重建
      this.showSelection = true;
    })
    .onBackPressed(() => {
      authManager.isAddingAccount = false;
      return false;
    })
  }
}
