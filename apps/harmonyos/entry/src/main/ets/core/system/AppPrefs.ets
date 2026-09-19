// 轻量 Preferences 封装（非敏感数据：身份索引、选中账号、UI 偏好）。
// Token 绝不进这里，只进 Asset Store Kit（TokenStore）。
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { GlobalContext } from './GlobalContext';

const STORE_NAME = 'orange_cloud_prefs';

/// 按账号隔离的「固定域名」key 前缀（value 为逗号连接的 zoneId 串）
const PINNED_ZONES_PREFIX = 'pinned_zones_';
/// 按账号隔离的「固定资源」key 前缀（域名以外的五类：worker/r2/d1/kv/tunnel；
/// value 为逗号连接的 `type|id` 串，只存类型+标识、不存会变的展示文案，资源改名后仍有效）
const PINNED_RES_PREFIX = 'pinned_resources_';
/// 外观模式：'system' | 'light' | 'dark'
const KEY_APPEARANCE = 'appearance_mode';
/// 用量「今日」日界口径：'utc' | 'local'
const KEY_DAY_BOUNDARY = 'usage_day_boundary';
/// 首启隐私政策同意标记（'1' = 已同意；同意前不发起任何网络请求）
const KEY_PRIVACY_ACCEPTED = 'privacy_accepted';
/// 减少动画（'1' = 开启，页面浮现等过渡直接到位）
const KEY_REDUCE_MOTION = 'reduce_motion';
/// 已看过「新功能」的版本号（空 = 从未看过）
const KEY_LAST_SEEN_WHATSNEW = 'last_seen_whatsnew_version';
/// 评分邀请：已登录启动计数 + 上次主动邀请的版本
const KEY_RATING_LAUNCHES = 'rating_engaged_launches';
const KEY_RATING_LAST_VERSION = 'rating_last_prompt_version';

export class AppPrefs {
  private static store: preferences.Preferences | null = null;
  /// 独立进程（如 WorkScheduler 扩展）可显式注入自身 context——
  /// 那里 GlobalContext（UIAbility context）未初始化，同名 store 走同一 bundle 沙箱共享。
  private static ctxOverride: common.Context | null = null;

  /// 后台进程启动时调用，让 AppPrefs 用扩展自身 context 打开同名 store
  static attach(context: common.Context): void {
    AppPrefs.ctxOverride = context;
    AppPrefs.store = null;
  }

  private static async instance(): Promise<preferences.Preferences> {
    if (AppPrefs.store) {
      return AppPrefs.store;
    }
    const context: common.Context = AppPrefs.ctxOverride ?? GlobalContext.get();
    const store = await preferences.getPreferences(context, STORE_NAME);
    AppPrefs.store = store;
    return store;
  }

  static async getString(key: string, fallback: string = ''): Promise<string> {
    const store = await AppPrefs.instance();
    return await store.get(key, fallback) as string;
  }

  static async putString(key: string, value: string): Promise<void> {
    const store = await AppPrefs.instance();
    await store.put(key, value);
    await store.flush();
  }

  static async remove(key: string): Promise<void> {
    const store = await AppPrefs.instance();
    await store.delete(key);
    await store.flush();
  }

  // MARK: - 隐私合规

  static async getPrivacyAccepted(): Promise<boolean> {
    const v = await AppPrefs.getString(KEY_PRIVACY_ACCEPTED, '');
    return v === '1';
  }

  static async setPrivacyAccepted(): Promise<void> {
    await AppPrefs.putString(KEY_PRIVACY_ACCEPTED, '1');
  }

  // MARK: - UI 偏好（外观 / 用量日界）

  /// 外观模式偏好：'system'（默认）| 'light' | 'dark'
  static async getAppearanceMode(): Promise<string> {
    return AppPrefs.getString(KEY_APPEARANCE, 'system');
  }

  static async setAppearanceMode(mode: string): Promise<void> {
    return AppPrefs.putString(KEY_APPEARANCE, mode);
  }

  /// 用量「今日」日界口径：'utc'（默认，与 Cloudflare 免费额度重置一致）| 'local'
  static async getDayBoundary(): Promise<string> {
    return AppPrefs.getString(KEY_DAY_BOUNDARY, 'utc');
  }

  static async setDayBoundary(value: string): Promise<void> {
    return AppPrefs.putString(KEY_DAY_BOUNDARY, value);
  }

  /// 减少动画偏好：开启后错峰浮现等过渡一步到位（对齐 iOS 设置页「减少动画」）
  static async getReduceMotion(): Promise<boolean> {
    const v = await AppPrefs.getString(KEY_REDUCE_MOTION, '');
    return v === '1';
  }

  static async setReduceMotion(on: boolean): Promise<void> {
    return AppPrefs.putString(KEY_REDUCE_MOTION, on ? '1' : '0');
  }

  // MARK: - 「新功能」与评分邀请

  /// 已看过「新功能」的版本号（空 = 从未看过；全新安装时由 WhatsNewStore 静默对齐）
  static async getLastSeenWhatsNew(): Promise<string> {
    return AppPrefs.getString(KEY_LAST_SEEN_WHATSNEW, '');
  }

  static async setLastSeenWhatsNew(version: string): Promise<void> {
    return AppPrefs.putString(KEY_LAST_SEEN_WHATSNEW, version);
  }

  /// 已登录启动次数（评分邀请的参与度信号）
  static async getRatingLaunches(): Promise<number> {
    const raw = await AppPrefs.getString(KEY_RATING_LAUNCHES, '0');
    const n = Number.parseInt(raw);
    return Number.isNaN(n) ? 0 : n;
  }

  static async setRatingLaunches(count: number): Promise<void> {
    return AppPrefs.putString(KEY_RATING_LAUNCHES, `${count}`);
  }

  /// 上次主动邀请评分的版本（每个版本最多主动邀请一次）
  static async getRatingPromptVersion(): Promise<string> {
    return AppPrefs.getString(KEY_RATING_LAST_VERSION, '');
  }

  static async setRatingPromptVersion(version: string): Promise<void> {
    return AppPrefs.putString(KEY_RATING_LAST_VERSION, version);
  }

  /// 固定域名的存储 key（按账号隔离）
  static pinnedZonesKey(accountId: string): string {
    return PINNED_ZONES_PREFIX + accountId;
  }

  /// 固定资源（域名以外五类）的存储 key（按账号隔离）
  static pinnedResourcesKey(accountId: string): string {
    return PINNED_RES_PREFIX + accountId;
  }
}

/// 「固定到首页」的域名 id 集合（按账号隔离持久化 + 内存可观察态）。
/// Dashboard / ZoneList / ZoneDetail 共享同一实例，任一处 toggle 全端即时联动。
@ObservedV2
export class PinnedZonesStore {
  /// 当前账号下已固定的 zoneId 列表（保持固定顺序）
  @Trace ids: string[] = [];
  private accountId: string = '';

  /// 切账号 / 首次进入时加载该账号的固定列表
  async loadFor(accountId: string): Promise<void> {
    if (accountId === '') {
      this.accountId = '';
      this.ids = [];
      return;
    }
    this.accountId = accountId;
    const raw = await AppPrefs.getString(AppPrefs.pinnedZonesKey(accountId), '');
    this.ids = raw === '' ? [] : raw.split(',');
  }

  isPinned(zoneId: string): boolean {
    return this.ids.includes(zoneId);
  }

  /// 切换固定状态并持久化；返回切换后是否处于「已固定」
  async toggle(accountId: string, zoneId: string): Promise<boolean> {
    if (accountId === '') {
      return false;
    }
    if (this.accountId !== accountId) {
      await this.loadFor(accountId);
    }
    const nowPinned = !this.ids.includes(zoneId);
    const next = nowPinned
      ? this.ids.concat([zoneId])
      : this.ids.filter((id: string) => id !== zoneId);
    this.ids = next;
    await AppPrefs.putString(AppPrefs.pinnedZonesKey(accountId), next.join(','));
    return nowPinned;
  }
}

export const pinnedZones: PinnedZonesStore = new PinnedZonesStore();

/// 「固定到首页」的跨类型资源（域名以外的 Workers / R2 / D1 / KV / Tunnel 五类，
/// 对齐 iOS PinnedResourceStore）。域名仍走 [[PinnedZonesStore]]——概览页把域名单独成段，
/// 两者合并反而会让同一张卡出现两次。
///
/// **只持久化 `type|resourceId`**：标题副标题展示时从当前清单现查，资源改名后置顶依旧有效；
/// 查不到的固定项在首页显示为「未找到」并允许一键取消固定。
@ObservedV2
export class PinnedResourcesStore {
  /// 当前账号已固定的 `type|id` 列表（保持固定顺序）
  @Trace keys: string[] = [];
  private accountId: string = '';

  static key(type: string, resourceId: string): string {
    return `${type}|${resourceId}`;
  }

  async loadFor(accountId: string): Promise<void> {
    if (accountId === '') {
      this.accountId = '';
      this.keys = [];
      return;
    }
    this.accountId = accountId;
    const raw = await AppPrefs.getString(AppPrefs.pinnedResourcesKey(accountId), '');
    this.keys = raw === '' ? [] : raw.split(',');
  }

  isPinned(type: string, resourceId: string): boolean {
    return this.keys.includes(PinnedResourcesStore.key(type, resourceId));
  }

  /// 切换固定状态并持久化；返回切换后是否处于「已固定」
  async toggle(accountId: string, type: string, resourceId: string): Promise<boolean> {
    if (accountId === '') {
      return false;
    }
    if (this.accountId !== accountId) {
      await this.loadFor(accountId);
    }
    const key = PinnedResourcesStore.key(type, resourceId);
    const nowPinned = !this.keys.includes(key);
    const next = nowPinned
      ? this.keys.concat([key])
      : this.keys.filter((k: string) => k !== key);
    this.keys = next;
    await AppPrefs.putString(AppPrefs.pinnedResourcesKey(accountId), next.join(','));
    return nowPinned;
  }
}

export const pinnedResources: PinnedResourcesStore = new PinnedResourcesStore();
