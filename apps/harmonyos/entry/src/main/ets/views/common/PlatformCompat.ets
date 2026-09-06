// 平台能力分档 + 悬浮页签滚动显隐控制（HarmonyOS Design 适配）。
// - 悬浮式材质页签栏（backgroundBlurStyle 材质 + 圆角内缩 + 阴影，内容从其下方穿过）针对 API 20+ 启用；
// - 动态显隐：下滑隐藏、上滑/回顶显示，沉浸阅读；
// 低于 20 回退经典底部 Tab 栏。
import { deviceInfo } from '@kit.BasicServicesKit';

export const API_LEVEL: number = deviceInfo.sdkApiVersion;

/// API 20+（HarmonyOS NEXT 6.0 起）启用悬浮材质页签栏 + 动态显隐
export const USE_FLOATING_TABBAR: boolean = API_LEVEL >= 20;

/// 悬浮栏尺寸 / 内缩，供各 Tab 根页给滚动内容预留底部净空
export const FLOATING_BAR_HEIGHT: number = 60;
export const FLOATING_BAR_BOTTOM_INSET: number = 20;
export const FLOATING_BAR_SIDE_INSET: number = 16;
export const TABBAR_CONTENT_CLEARANCE: number =
  USE_FLOATING_TABBAR ? (FLOATING_BAR_HEIGHT + FLOATING_BAR_BOTTOM_INSET + 12) : 0;

/// 悬浮栏动态显隐控制器：各 Tab 根页滚动时 notify，MainShell 的浮栏绑定 hidden 做平移+淡出。
@ObservedV2
export class TabBarScrollCtrl {
  @Trace hidden: boolean = false;
  private acc: number = 0;

  /// dy 为本帧滚动增量：>0 下滑（隐藏），<0 上滑（显示）。带 8vp 死区去抖。
  notifyScroll(dy: number): void {
    if (dy > 0.5) {
      this.acc = this.acc > 0 ? this.acc + dy : dy;
    } else if (dy < -0.5) {
      this.acc = this.acc < 0 ? this.acc + dy : dy;
    }
    if (this.acc > 8 && !this.hidden) {
      this.hidden = true;
      this.acc = 0;
    } else if (this.acc < -8 && this.hidden) {
      this.hidden = false;
      this.acc = 0;
    }
  }

  /// 回到顶部或切换 Tab 时强制显示
  reveal(): void {
    this.acc = 0;
    if (this.hidden) {
      this.hidden = false;
    }
  }
}

export const tabBarScroll: TabBarScrollCtrl = new TabBarScrollCtrl();
