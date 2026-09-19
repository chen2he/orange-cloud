// 连续后台任务包装：R2 上传/下载期间申请 DATA_TRANSFER 连续任务，
// 让传输在 App 切后台后继续存活；启动失败（不支持/被拒）时静默降级为前台传输。
// 需要 ohos.permission.KEEP_BACKGROUND_RUNNING + module.json5 backgroundModes: ["dataTransfer"]。
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { GlobalContext } from './GlobalContext';

/// 构造点通知栏时拉起本 App 的 WantAgent（连续任务必填参数）
async function buildTransferWantAgent(context: common.UIAbilityContext): Promise<WantAgent> {
  const info: wantAgent.WantAgentInfo = {
    wants: [
      {
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name,
      },
    ],
    actionType: wantAgent.OperationType.START_ABILITY,
    requestCode: 0,
    actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
  };
  return await wantAgent.getWantAgent(info);
}

/// 在 op（一次上传或下载）执行期间保持连续后台任务：
/// 先尽力 start，op 结束后 finally 里 stop；start 抛错则不阻塞 op（前台继续传）。
export async function withDataTransfer<T>(op: () => Promise<T>): Promise<T> {
  let context: common.UIAbilityContext | null = null;
  let started = false;
  try {
    context = GlobalContext.get();
    const agent = await buildTransferWantAgent(context);
    await backgroundTaskManager.startBackgroundRunning(
      context, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
    started = true;
  } catch (e) {
    // 不支持 / 未授权 / context 未就绪：降级前台传输，不打断实际传输
    started = false;
  }
  try {
    return await op();
  } finally {
    if (started && context) {
      try {
        await backgroundTaskManager.stopBackgroundRunning(context);
      } catch (e) {
      }
    }
  }
}
