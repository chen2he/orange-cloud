// 全局 UIAbility context 持有者：EntryAbility onCreate 时注入，
// 供 AppPrefs（preferences 需要 context）与 openLink 使用。
// 独立进程（WorkScheduler 扩展）无 UIAbility context，用 setBase 注入自身基础 context，
// 供仅需 common.Context 的路径（token 刷新 RefreshGate、preferences）使用。
import { common } from '@kit.AbilityKit';

export class GlobalContext {
  private static ctx: common.UIAbilityContext | null = null;
  private static base: common.Context | null = null;

  static set(context: common.UIAbilityContext): void {
    GlobalContext.ctx = context;
    GlobalContext.base = context;
  }

  /// 后台扩展进程注入自身 context（非 UIAbility）
  static setBase(context: common.Context): void {
    GlobalContext.base = context;
  }

  static get(): common.UIAbilityContext {
    const ctx = GlobalContext.ctx;
    if (!ctx) {
      throw new Error('GlobalContext 尚未初始化');
    }
    return ctx;
  }

  /// 仅需 common.Context 的路径用此（前台 = UIAbility context，后台 = 扩展 context）
  static getBase(): common.Context {
    const base = GlobalContext.base;
    if (!base) {
      throw new Error('GlobalContext 尚未初始化');
    }
    return base;
  }
}
