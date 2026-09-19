// 应用内评分邀请（AppGallery Kit 的 commentManager.showCommentDialog，API 20+）。
//
// 策略对齐 iOS RatingPrompt：只把「已登录启动」计为参与度信号；达到阈值后每个版本最多
// 主动邀请一次；与「新功能」错峰（同一启动只出一个打扰）。设置「关于」里另有常驻手动入口，
// 两者互不影响。
//
// 华为侧自身还有限频（同一版本已评论 / 一年内已评价会直接抛错），这些错误一律静默——
// 主动邀请失败不该给用户看错误弹窗；手动入口才把原因 toast 出来。
import { commentManager } from '@kit.AppGalleryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppPrefs } from '../system/AppPrefs';
import { appVersionName } from '../system/AppVersion';
import { GlobalContext } from '../system/GlobalContext';

/// 触发主动邀请所需的最小「已登录启动」次数
const MIN_ENGAGED_LAUNCHES = 3;

/// 手动入口用的人话错误文案（错误码见 @hms.core.appgalleryservice.commentManager.d.ts）
function commentErrorText(code: number): string {
  if (code === 1021500006) {
    return '请先登录华为账号后再评价';
  }
  if (code === 1021500007) {
    return '你已经评价过当前版本了，谢谢支持';
  }
  if (code === 1021500009) {
    return '距上次评价不足一年，暂时无法再次评价';
  }
  if (code === 1021500008) {
    return '评价次数已达上限';
  }
  if (code === 1021500003) {
    return '连接应用市场失败，请稍后再试';
  }
  return '暂时无法打开评价，请稍后再试';
}

export class RatingPrompt {
  /// App 启动且此次为已登录态时 +1（MainShell 挂载时调用——它只在登录后出现）
  static async registerEngagedLaunch(): Promise<void> {
    const count = await AppPrefs.getRatingLaunches();
    await AppPrefs.setRatingLaunches(count + 1);
  }

  /// 是否满足主动邀请：达到最小启动次数，且当前版本尚未邀请过
  static async shouldRequest(): Promise<boolean> {
    const count = await AppPrefs.getRatingLaunches();
    if (count < MIN_ENGAGED_LAUNCHES) {
      return false;
    }
    const last = await AppPrefs.getRatingPromptVersion();
    return last !== appVersionName();
  }

  /// 拉起评价弹窗（context 取全局 UIAbility context，与 openLink / AppPrefs 同源）。
  /// 返回 '' = 已拉起，否则是给手动入口用的失败原因。
  static async request(): Promise<string> {
    try {
      await commentManager.showCommentDialog(GlobalContext.get());
      return '';
    } catch (e) {
      const err = e as BusinessError;
      return commentErrorText(err.code ?? 0);
    }
  }

  /// 记录已在当前版本主动邀请过（无论用户是否真的评价，都不再重复打扰）
  static async markRequested(): Promise<void> {
    await AppPrefs.setRatingPromptVersion(appVersionName());
  }
}
