// 延迟任务扩展（对齐 iOS BGAppRefreshTask / Android WorkManager）：系统按周期在独立进程拉起，
// 执行 token 保活 + 卡片刷新，完成后 stopWork 释放进程。周期性由注册时的 isRepeat 承担。
import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { runBackgroundRefresh } from '../core/system/BackgroundRefresh';

const DOMAIN = 0x0001;
const TAG = 'RefreshWorker';

export default class RefreshWorker extends WorkSchedulerExtensionAbility {
  onWorkStart(work: workScheduler.WorkInfo): void {
    hilog.info(DOMAIN, TAG, 'onWorkStart id=%{public}d', work.workId);
    runBackgroundRefresh(this.context)
      .then(() => {
        hilog.info(DOMAIN, TAG, 'background refresh done');
      })
      .catch((e: Error) => {
        hilog.warn(DOMAIN, TAG, 'background refresh error: %{public}s', e.message ?? '');
      })
      .finally(() => {
        // 完成后释放本次任务（isRepeat 由框架按周期再次拉起，needCancel=false 保留任务）
        try {
          workScheduler.stopWork(work, false);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'stopWork failed: %{public}s', (e as Error).message ?? '');
        }
      });
  }

  onWorkStop(work: workScheduler.WorkInfo): void {
    hilog.info(DOMAIN, TAG, 'onWorkStop id=%{public}d', work.workId);
  }
}
