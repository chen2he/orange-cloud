// Zone 设置读写（/zones/{id}/settings/{setting}，PATCH 改值）+ 按目标清缓存 / 标记过期。
// 对齐 Android ZoneSettingsRepository。
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

interface ZoneSetting {
  id: string;
  value: string;
  // 当前套餐能否修改这项。套餐不够时照样读得到值，只是 editable 为 false、PATCH 一律 400
  editable?: boolean;
}

interface ZoneSettingUpdate {
  value: string;
}

/**
 * Zone 机器人管控配置（GET/PUT /zones/{id}/bot_management）。
 *
 * 响应 result 是四种套餐形态的 oneOf，四者都 allOf 引用同一个 base_config；
 * 这里只建模 base_config 里与 AI / 爬虫相关的字段，套餐专属字段（sbfm_* / fight_mode）不碰，
 * 故全部可选，任何套餐的响应都能安全解码。
 *
 * 写入用 PUT 但是**合并语义**：官方示例就是只发要改的字段，base_config 无 required。
 * 因此 setBotManagement 每次只带一个键，不会误清其它设置。
 */
export interface BotManagementConfig {
  ai_bots_protection?: string;      // block / only_on_ad_pages / disabled
  crawler_protection?: string;      // enabled / disabled —— 链接迷宫
  content_bots_protection?: string; // block / disabled
  cf_robots_variant?: string;       // off / policy_only
  is_robots_txt_managed?: boolean;
  // 2026-09-15 起 ai_bots_protection 拆成三类（全套餐）。老响应里没有这些键，一律可选；
  // 值按字符串收，未知取值不崩（界面上不高亮任何选项）
  ai_search?: string;               // disabled / block / only_on_ad_pages —— AI 搜索爬虫
  ai_user?: string;                 // disabled / block / only_on_ad_pages —— AI 助手与 Agent
  ai_training?: string;             // disabled / disallow / block / only_on_ad_pages —— AI 训练
  /// Bot Preference Sync：按三项偏好由 Cloudflare 生成 robots.txt（取代托管 robots.txt）
  bot_preference_sync_enabled?: boolean;
}

interface PurgeFilesBody {
  files: string[];
}

interface PurgePrefixesBody {
  prefixes: string[];
}

interface PurgeHostsBody {
  hosts: string[];
}

interface PurgeTagsBody {
  tags: string[];
}

export class ZoneSettingsService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  async getSetting(zoneId: string, setting: string): Promise<string> {
    const result = await this.client.getObject<ZoneSetting>(`/zones/${zoneId}/settings/${setting}`);
    return result.value;
  }

  /// 读值；当前套餐不允许修改这项（editable 为 false）时返回 null，调用方据此隐藏开关
  async getSettingIfEditable(zoneId: string, setting: string): Promise<string | null> {
    const result = await this.client.getObject<ZoneSetting>(`/zones/${zoneId}/settings/${setting}`);
    return result.editable === false ? null : result.value;
  }

  async setSetting(zoneId: string, setting: string, value: string): Promise<string> {
    const body: ZoneSettingUpdate = { value: value };
    const result = await this.client.patchObject<ZoneSetting>(`/zones/${zoneId}/settings/${setting}`, body);
    return result.value;
  }

  /// 读机器人管控配置（bot-management.read，全套餐可用）
  getBotManagement(zoneId: string): Promise<BotManagementConfig> {
    return this.client.getObject<BotManagementConfig>(`/zones/${zoneId}/bot_management`);
  }

  /// 写机器人管控。PUT 合并语义，body 只带要改的那个键。
  setBotManagement(zoneId: string, body: BotManagementConfig): Promise<BotManagementConfig> {
    return this.client.putObject<BotManagementConfig>(`/zones/${zoneId}/bot_management`, body);
  }

  /// 缓存操作端点：invalidate=false 走 purge_cache（删除），true 走 invalidate_cache（标记过期）。
  /// 两者请求体、权限（cache.purge）与限流完全相同（invalidate 2026-09-28 GA）。
  private cachePath(zoneId: string, invalidate: boolean): string {
    return invalidate ? `/zones/${zoneId}/invalidate_cache` : `/zones/${zoneId}/purge_cache`;
  }

  /// 按 URL 清缓存 / 标记过期（单次最多 30 个）
  async purgeFiles(zoneId: string, urls: string[], invalidate: boolean = false): Promise<void> {
    const body: PurgeFilesBody = { files: urls };
    await this.client.postObject<object>(this.cachePath(zoneId, invalidate), body);
  }

  /// 按路径前缀清缓存 / 标记过期（企业版，单次最多 30 个）
  async purgePrefixes(zoneId: string, prefixes: string[], invalidate: boolean = false): Promise<void> {
    const body: PurgePrefixesBody = { prefixes: prefixes };
    await this.client.postObject<object>(this.cachePath(zoneId, invalidate), body);
  }

  /// 按主机名清缓存 / 标记过期（企业版，单次最多 30 个）
  async purgeHosts(zoneId: string, hosts: string[], invalidate: boolean = false): Promise<void> {
    const body: PurgeHostsBody = { hosts: hosts };
    await this.client.postObject<object>(this.cachePath(zoneId, invalidate), body);
  }

  /// 按 Cache-Tag 清缓存 / 标记过期（企业版，单次最多 30 个）
  async purgeTags(zoneId: string, tags: string[], invalidate: boolean = false): Promise<void> {
    const body: PurgeTagsBody = { tags: tags };
    await this.client.postObject<object>(this.cachePath(zoneId, invalidate), body);
  }
}
