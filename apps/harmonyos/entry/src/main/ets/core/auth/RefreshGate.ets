// 跨进程刷新互斥锁（对齐 iOS Core/Auth/RefreshGate fcntl 锁 / Android RefreshGate）。
// 背景：Cloudflare 每次刷新都轮换 refresh_token，旧 token 一旦被消费即失效；
// 若主 App 与后台 WorkScheduler 进程并发刷新同一身份，会用到已消费的 refresh_token，
// 触发 CF 复用检测 → 整条 token 链被吊销 → 永久登出。
// 因此任何进程刷新共享 token 前，必须先拿到本身份的跨进程锁。
//
// 实现：以「锁目录」为原子原语——fs.mkdirSync(path) 在目录已存在时抛错，
// 是 POSIX 上最可移植的跨进程原子占位（等价 O_EXCL；SDK 未暴露 openSync 的 EXCLUSIVE OpenMode）。
// 锁目录存放于 context.filesDir（同 bundle 各进程共享沙箱）。
// 新鲜锁（mtime < 90s）视为他人正在刷新 → 放弃；陈旧锁（> 90s，进程崩溃遗留）→ 抢占后重建。
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'RefreshGate';
/// 锁陈旧阈值（秒）：超过则认定持锁进程已崩溃，可抢占
const STALE_SECONDS = 90;

function lockPath(context: common.Context, key: string): string {
  return `${context.filesDir}/${key}`;
}

/// 锁目录 mtime（秒，Unix 纪元）；不存在或读取失败返回 null
function lockAgeSeconds(path: string): number | null {
  try {
    const stat = fs.statSync(path);
    const nowSeconds = Math.floor(Date.now() / 1000);
    return nowSeconds - stat.mtime;
  } catch (e) {
    return null;
  }
}

function tryRemoveLock(path: string): void {
  try {
    fs.rmdirSync(path);
  } catch (e) {
    // 已被他人释放或不存在，忽略
  }
}

/// 尝试原子创建锁目录；成功返回 true
function tryCreateLock(path: string): boolean {
  try {
    fs.mkdirSync(path);
    return true;
  } catch (e) {
    return false;
  }
}

export class RefreshGate {
  /// 在本身份的跨进程锁保护下执行 fn；未抢到锁返回 null（调用方应视为「他人正在刷新，跳过」）。
  /// key 建议按身份区分，如 refresh_<sessionId>.lock
  static async runExclusive<T>(context: common.Context, key: string, fn: () => Promise<T>): Promise<T | null> {
    const path = lockPath(context, key);
    let acquired = tryCreateLock(path);
    if (!acquired) {
      // 锁已存在：看是否陈旧（持锁进程崩溃遗留）
      const age = lockAgeSeconds(path);
      if (age === null) {
        // 读不到状态但创建又失败：竞态窗口，稳妥起见放弃
        return null;
      }
      if (age < STALE_SECONDS) {
        // 新鲜锁 → 他人正在刷新，放弃
        return null;
      }
      // 陈旧锁 → 抢占：删旧目录后重建
      hilog.warn(DOMAIN, TAG, 'stealing stale lock %{public}s (age=%{public}ds)', key, age);
      tryRemoveLock(path);
      acquired = tryCreateLock(path);
      if (!acquired) {
        // 抢占竞态失败（另一进程刚抢到），放弃
        return null;
      }
    }
    try {
      return await fn();
    } finally {
      tryRemoveLock(path);
    }
  }
}
