// 轻提示统一走 UI Design Kit 的 HdsSnackBar（即时操作组件），替代 promptAction.showToast。
// 相比 toast：系统材质卡片 + 图文布局 + 可挂快捷操作按钮，且样式与系统一致。
// 用法：ocSnack(this.getUIContext(), '已保存')
import { HdsSnackBar } from '@kit.UIDesignKit';

export function ocSnack(ctx: UIContext, message: string): void {
  try {
    new HdsSnackBar(ctx).show({}, { title: message }, {});
  } catch (e) {
    // 兜底：极端情况下（UIContext 不可用）退回系统 toast，不让提示丢失
    ctx.getPromptAction().showToast({ message: message });
  }
}
