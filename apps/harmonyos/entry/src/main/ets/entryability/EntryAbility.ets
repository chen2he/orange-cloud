import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { workScheduler } from '@kit.BackgroundTasksKit';
import { authManager } from '../core/auth/AuthManager';
import { GlobalContext } from '../core/system/GlobalContext';
import { AppPrefs } from '../core/system/AppPrefs';

const DOMAIN = 0x0000;
/// 后台刷新任务 id 与周期（系统对 isRepeat 的最小周期约 2h）
const REFRESH_WORK_ID = 1;
const REFRESH_CYCLE_MS = 2 * 60 * 60 * 1000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    GlobalContext.set(this.context);
    // 外观模式：启动时读取用户偏好并应用（跟随系统 / 浅色 / 深色，设置页可即时切换）
    AppPrefs.getAppearanceMode().then((mode: string) => {
      try {
        let colorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
        if (mode === 'light') {
          colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
        } else if (mode === 'dark') {
          colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
        }
        this.context.getApplicationContext().setColorMode(colorMode);
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
      }
    }).catch((err: Error) => {
      hilog.warn(DOMAIN, 'testTag', 'read appearance pref failed: %{public}s', JSON.stringify(err));
    });
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    this.scheduleBackgroundRefresh();
    this.handleOAuthWant(want);
  }

  /// 注册后台刷新延迟任务（token 保活 + 卡片刷新）；重复注册幂等由框架处理，全程 try/catch 不影响启动
  private scheduleBackgroundRefresh(): void {
    try {
      const work: workScheduler.WorkInfo = {
        workId: REFRESH_WORK_ID,
        bundleName: 'ltd.zhe.orange_cloud',
        abilityName: 'RefreshWorker',
        isRepeat: true,
        repeatCycleTime: REFRESH_CYCLE_MS,
        networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
        isPersisted: true,
      };
      workScheduler.startWork(work);
      hilog.info(DOMAIN, 'testTag', '%{public}s', 'background refresh work scheduled');
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'scheduleBackgroundRefresh failed: %{public}s', JSON.stringify(err));
    }
  }

  // 浏览器 302 到 orangecloud://oauth/callback 时，App 已在运行则走 onNewWant
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleOAuthWant(want);
  }

  private handleOAuthWant(want: Want): void {
    const uri = want.uri ?? '';
    if (uri.startsWith('orangecloud://oauth/callback')) {
      authManager.handleOAuthCallback(uri).catch((e: Error) => {
        hilog.error(DOMAIN, 'testTag', 'OAuth callback failed: %{public}s', e.message);
      });
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}