// 版本更新后的「新功能」：内容按版本 curated，登录后比对 lastSeen 决定是否弹。
//
// ⚠️ 内容是**单一数据源**：改 packages/changelog/harmonyos.json 后跑 `pnpm changelog:gen`，
//    会重新生成 WhatsNewReleases.generated.ets（勿手改生成物，也别在本文件内联文案）。
//
// 触发口径逐条对齐 iOS（Views/WhatsNew/WhatsNewView.swift 的 WhatsNewModifier）：
//  · 全新安装（无 lastSeen 且启动时并非已登录态）→ 静默对齐，不打扰新用户；
//  · 老用户升级到首个带「新功能」的版本（lastSeen 为空但启动即已登录）→ 用 "0" 兜底补看一次；
//  · (lastSeen, current] 区间内的条目全展示，新版在前；无内容则只对齐 lastSeen 不弹。
import { AppPrefs } from '../system/AppPrefs';
import { appVersionName } from '../system/AppVersion';
import { whatsNewReleases } from './WhatsNewReleases.generated';

export interface WhatsNewItem {
  symbol: Resource;
  title: string;
  detail: string;
}

export interface WhatsNewRelease {
  version: string;
  items: WhatsNewItem[];
}

/// 数值分段比较：a 是否比 b 新（"1.10.0" > "1.9.9"）。
/// 不用 localeCompare(numeric)——ArkTS 侧该选项不可靠，按段自己比。
export function isNewerVersion(a: string, b: string): boolean {
  const pa = a.split('.');
  const pb = b.split('.');
  const len = Math.max(pa.length, pb.length);
  for (let i = 0; i < len; i++) {
    const na = Number.parseInt(pa[i] ?? '0');
    const nb = Number.parseInt(pb[i] ?? '0');
    const va = Number.isNaN(na) ? 0 : na;
    const vb = Number.isNaN(nb) ? 0 : nb;
    if (va !== vb) {
      return va > vb;
    }
  }
  return false;
}

/// 启动时拍一张「是否已登录」的快照，用于区分老用户升级 vs 全新安装；
/// presentedThisLaunch 让评分邀请等其它一次性打扰给「新功能」让路（同一启动只出一个）。
export class WhatsNewGate {
  static wasLoggedInAtLaunch: boolean = false;
  static presentedThisLaunch: boolean = false;
}

export class WhatsNewStore {
  /// (seen, current] 区间内所有版本的新功能，新版在前
  static itemsAfter(seen: string, current: string): WhatsNewItem[] {
    const releases = whatsNewReleases()
      .filter((r: WhatsNewRelease) => isNewerVersion(r.version, seen) && !isNewerVersion(r.version, current));
    releases.sort((a: WhatsNewRelease, b: WhatsNewRelease) => isNewerVersion(a.version, b.version) ? -1 : 1);
    let items: WhatsNewItem[] = [];
    for (const release of releases) {
      items = items.concat(release.items);
    }
    return items;
  }

  /// 评估本次启动是否该弹：返回要展示的条目（空数组 = 不弹，lastSeen 已就地对齐）
  static async evaluate(): Promise<WhatsNewItem[]> {
    const current = appVersionName();
    const lastSeen = await AppPrefs.getLastSeenWhatsNew();
    // 全新安装：静默对齐，不打扰新用户
    if (lastSeen === '' && !WhatsNewGate.wasLoggedInAtLaunch) {
      await AppPrefs.setLastSeenWhatsNew(current);
      return [];
    }
    // 老用户升级到首个带「新功能」的版本时 lastSeen 为空，用 "0" 兜底展示全部 ≤ current
    const baseline = lastSeen === '' ? '0' : lastSeen;
    const unseen = WhatsNewStore.itemsAfter(baseline, current);
    if (unseen.length === 0) {
      // 版本升了但无可展示内容：对齐，避免每次启动反复评估
      await AppPrefs.setLastSeenWhatsNew(current);
      return [];
    }
    return unseen;
  }

  /// 看完（点「继续」或收起弹窗）后写入，保证同一版本只弹一次
  static async markSeen(): Promise<void> {
    await AppPrefs.setLastSeenWhatsNew(appVersionName());
  }
}
