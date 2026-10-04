import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// Zone 设置：开发模式 / Under Attack 模式 / 暂停 Cloudflare + 按目标清缓存（URL / 前缀 / 主机 /
// 缓存标签四模式，对照 iOS PurgeCacheSheet；POST /zones/{id}/purge_cache 的 files/prefixes/hosts/tags）。
// 同一组目标也可「标记过期」（POST /zones/{id}/invalidate_cache，请求体与权限同 purge）。
// 注意暂停与另两个开关不同源：开发模式 / Under Attack 走 zone settings（zone-settings.*），
// 暂停读写域名本身（zone.read / zone.write），权限链路各自独立。
import { ZoneRouteParam } from '../../models/Routes';
import { BotManagementConfig, PrecursorConfig, ZoneSettingsService } from '../../services/ZoneSettingsService';
import { ZoneService } from '../../services/ZoneService';
import { Zone } from '../../models/Models';
import { Scopes } from '../../core/auth/Scopes';
import { authManager } from '../../core/auth/AuthManager';
import { BRAND_ORANGE, OCLoading, SectionHeader, ToggleRow } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';

/// 清缓存四模式说明
interface PurgeModeSpec {
  key: string; // files 或 prefixes 或 hosts 或 tags
  label: string;
  placeholder: string;
  note: string;
  confirmText: string;
}

/// ai_bots_protection 的三档取值
interface AiBotsOption {
  value: string;
  label: string;
}

const AI_BOTS_OPTIONS: AiBotsOption[] = [
  { value: 'disabled', label: '放行' },
  { value: 'only_on_ad_pages', label: '仅广告页' },
  { value: 'block', label: '全站拦截' },
];

/// 2026-09-15 起 AI 爬虫拆成三类：AI 搜索 / AI 助手与 Agent 的取值
const AI_POLICY_OPTIONS: AiBotsOption[] = [
  { value: 'disabled', label: '允许' },
  { value: 'block', label: '全部拦截' },
  { value: 'only_on_ad_pages', label: '仅拦截含广告的页面' },
];

/// AI 训练多一档：只在 robots.txt 里声明禁止，不做拦截
const AI_TRAINING_OPTIONS: AiBotsOption[] = [
  { value: 'disabled', label: '允许' },
  { value: 'disallow', label: '在 robots.txt 中声明禁止' },
  { value: 'block', label: '全部拦截' },
  { value: 'only_on_ad_pages', label: '仅拦截含广告的页面' },
];

/// Precursor 会话级机器人检测的默认模式
const PRECURSOR_OPTIONS: AiBotsOption[] = [
  { value: 'off', label: '关闭' },
  { value: 'min-friction', label: '低打扰' },
  { value: 'max-security', label: '最高安全' },
];

/// 标记过期的说明（清除 / 标记过期分段切到后者时展示）
const INVALIDATE_NOTE: string =
  '保留缓存但标记为过期，下次请求时向源站校验；内容没变（304）就继续用缓存。需要源站返回 ETag 或 Last-Modified。';

const PURGE_MODES: PurgeModeSpec[] = [
  {
    key: 'files',
    label: 'URL',
    placeholder: 'https://example.com/path/file.js',
    note: '按完整 URL 精确清除，每行一个，单次最多 30 个。',
    confirmText: '将按完整 URL 精确清除这些资源的边缘缓存。',
  },
  {
    key: 'prefixes',
    label: '前缀',
    placeholder: 'example.com/static/',
    note: '清除路径前缀下的所有缓存（需企业版计划），每行一个，单次最多 30 个。',
    confirmText: '将清除这些路径前缀下的全部边缘缓存，源站压力可能短暂上升。',
  },
  {
    key: 'hosts',
    label: '主机',
    placeholder: 'img.example.com',
    note: '清除整个主机名下的缓存（需企业版计划），每行一个，单次最多 30 个。',
    confirmText: '将清除这些主机名下的全部边缘缓存，源站压力可能短暂上升。',
  },
  {
    key: 'tags',
    label: '缓存标签',
    placeholder: 'tag-a',
    note: '按响应的 Cache-Tag 头清除（需企业版计划），每行一个，单次最多 30 个。',
    confirmText: '将清除携带这些 Cache-Tag 的全部边缘缓存，源站压力可能短暂上升。',
  },
];

@ObservedV2
class ZoneSettingsVM {
  @Trace developmentMode: boolean = false;
  @Trace underAttack: boolean = false;
  @Trace paused: boolean = false;
  // AI 内容控制（Pro 起）。免费套餐读得到值但 editable 为 false、一写就 400，
  // 读不到或不可改都隐藏对应开关——不给用户一个永远打不开的开关。
  @Trace aiTrainingRedirect: boolean = false;
  @Trace markdownForAgents: boolean = false;
  @Trace aiTrainingRedirectAvailable: boolean = false;
  @Trace markdownForAgentsAvailable: boolean = false;
  // 机器人管控（bot-management.*，全套餐可用；与 zone-settings.* 是两条权限链路）
  @Trace aiBotsProtection: string = 'disabled';
  @Trace crawlerProtection: boolean = false;
  @Trace contentBotsProtection: boolean = false;
  @Trace robotsLicense: boolean = false;
  @Trace managedRobotsTxt: boolean = false;
  // 拆分后的三类 AI 爬虫策略；响应里出现任一项即改用三选择器，否则保留老的「AI 爬虫」
  @Trace aiSearch: string = '';
  @Trace aiUser: string = '';
  @Trace aiTraining: string = '';
  @Trace splitAiControls: boolean = false;
  // Bot Preference Sync：响应带这个键就用它替代「托管 robots.txt」
  @Trace preferenceSync: boolean = false;
  @Trace hasPreferenceSync: boolean = false;
  @Trace botConfigLoaded: boolean = false;
  // Precursor（precursor.*，独立权限链路）：GET 失败整行不显示
  @Trace precursorMode: string = '';
  @Trace precursorLoaded: boolean = false;
  @Trace isLoading: boolean = false;
  @Trace isSaving: boolean = false;
  @Trace error: string = '';

  private service: ZoneSettingsService = new ZoneSettingsService();
  private zoneService: ZoneService = new ZoneService();

  async load(zoneId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      try {
        this.developmentMode = (await this.service.getSetting(zoneId, 'development_mode')) === 'on';
      } catch (e) {
      }
      try {
        this.underAttack = (await this.service.getSetting(zoneId, 'security_level')) === 'under_attack';
      } catch (e) {
      }
      let aiRedirect: string | null = null;
      try {
        aiRedirect = await this.service.getSettingIfEditable(zoneId, 'redirects_for_ai_training');
      } catch (e) {
      }
      this.aiTrainingRedirect = aiRedirect === 'on';
      this.aiTrainingRedirectAvailable = aiRedirect !== null;
      let converter: string | null = null;
      try {
        converter = await this.service.getSettingIfEditable(zoneId, 'content_converter');
      } catch (e) {
      }
      this.markdownForAgents = converter === 'on';
      this.markdownForAgentsAvailable = converter !== null;
      // 暂停态只需 zone.read，缺 zone-settings.read 时这一项照常能读到
      try {
        const zone: Zone = await this.zoneService.fetchZone(zoneId);
        this.paused = zone.paused === true;
      } catch (e) {
      }
    } finally {
      this.isLoading = false;
    }
  }

  async setDevelopmentMode(zoneId: string, on: boolean): Promise<string> {
    this.isSaving = true;
    try {
      const applied = await this.service.setSetting(zoneId, 'development_mode', on ? 'on' : 'off');
      this.developmentMode = applied === 'on';
      return '';
    } catch (e) {
      return (e as Error).message ?? '设置失败';
    } finally {
      this.isSaving = false;
    }
  }

  async setUnderAttack(zoneId: string, on: boolean): Promise<string> {
    this.isSaving = true;
    try {
      const applied = await this.service.setSetting(zoneId, 'security_level', on ? 'under_attack' : 'medium');
      this.underAttack = applied === 'under_attack';
      return '';
    } catch (e) {
      return (e as Error).message ?? '设置失败';
    } finally {
      this.isSaving = false;
    }
  }

  /// 读机器人管控。四种套餐形态共用 base_config，任何套餐都能读到。
  async loadBotConfig(zoneId: string): Promise<void> {
    try {
      this.applyBotConfig(await this.service.getBotManagement(zoneId));
    } catch (e) {
      // 无 bot-management.read 或接口异常：整组不显示，不打断本页其余内容
    }
  }

  private applyBotConfig(cfg: BotManagementConfig): void {
    this.aiBotsProtection = cfg.ai_bots_protection ?? 'disabled';
    this.crawlerProtection = cfg.crawler_protection === 'enabled';
    this.contentBotsProtection = cfg.content_bots_protection === 'block';
    this.robotsLicense = cfg.cf_robots_variant === 'policy_only';
    this.managedRobotsTxt = cfg.is_robots_txt_managed === true;
    const search = cfg.ai_search ?? '';
    const user = cfg.ai_user ?? '';
    const training = cfg.ai_training ?? '';
    // 一旦认出新字段就保持新界面（PUT 回包若偶发缺键，不来回切换布局）
    if (search !== '' || user !== '' || training !== '') {
      this.splitAiControls = true;
    }
    this.aiSearch = search;
    this.aiUser = user;
    this.aiTraining = training;
    const sync = cfg.bot_preference_sync_enabled;
    if (sync !== undefined && sync !== null) {
      this.hasPreferenceSync = true;
    }
    this.preferenceSync = sync === true;
    this.botConfigLoaded = true;
  }

  /// 读 Precursor 默认模式；无 precursor.read 不发请求，失败静默（整行隐藏）
  async loadPrecursor(zoneId: string): Promise<void> {
    if (!authManager.hasScope(Scopes.PRECURSOR_READ)) {
      return;
    }
    try {
      const cfg: PrecursorConfig = await this.service.getPrecursor(zoneId);
      this.precursorMode = cfg.default_mode ?? '';
      this.precursorLoaded = true;
    } catch (e) {
      this.precursorLoaded = false;
    }
  }

  async setPrecursorMode(zoneId: string, mode: string): Promise<string> {
    this.isSaving = true;
    try {
      const cfg: PrecursorConfig = await this.service.setPrecursorMode(zoneId, mode);
      this.precursorMode = cfg.default_mode ?? mode;
      return '';
    } catch (e) {
      return (e as Error).message ?? '设置失败';
    } finally {
      this.isSaving = false;
    }
  }

  /// 写单个字段。PUT 合并语义，只发改动那一项，不动 sbfm_* 等套餐专属配置。
  async setBotField(zoneId: string, body: BotManagementConfig): Promise<string> {
    this.isSaving = true;
    try {
      this.applyBotConfig(await this.service.setBotManagement(zoneId, body));
      return '';
    } catch (e) {
      await this.loadBotConfig(zoneId);   // 回读，纠正界面上的乐观值
      return (e as Error).message ?? '设置失败';
    } finally {
      this.isSaving = false;
    }
  }

  async setAiTrainingRedirect(zoneId: string, on: boolean): Promise<string> {
    this.isSaving = true;
    try {
      const applied = await this.service.setSetting(zoneId, 'redirects_for_ai_training', on ? 'on' : 'off');
      this.aiTrainingRedirect = applied === 'on';
      return '';
    } catch (e) {
      return (e as Error).message ?? '设置失败';
    } finally {
      this.isSaving = false;
    }
  }

  async setMarkdownForAgents(zoneId: string, on: boolean): Promise<string> {
    this.isSaving = true;
    try {
      const applied = await this.service.setSetting(zoneId, 'content_converter', on ? 'on' : 'off');
      this.markdownForAgents = applied === 'on';
      return '';
    } catch (e) {
      return (e as Error).message ?? '设置失败';
    } finally {
      this.isSaving = false;
    }
  }

  /// 暂停 / 恢复 Cloudflare 代理。影响面大，界面先弹确认再调这里。
  async setPaused(zoneId: string, on: boolean): Promise<string> {
    this.isSaving = true;
    try {
      const zone: Zone = await this.zoneService.setPaused(zoneId, on);
      this.paused = zone.paused === true;
      return '';
    } catch (e) {
      return (e as Error).message ?? '设置失败';
    } finally {
      this.isSaving = false;
    }
  }

  /// 按目标清缓存：mode 为 files 或 prefixes 或 hosts 或 tags；invalidate 为 true 时改为标记过期
  async purgeTargets(zoneId: string, mode: string, text: string, invalidate: boolean): Promise<string> {
    const items = text.split('\n').map((u: string) => u.trim()).filter((u: string) => u !== '');
    if (items.length === 0) {
      return '请输入至少一条内容';
    }
    if (items.length > 30) {
      return '单次最多 30 条';
    }
    try {
      if (mode === 'prefixes') {
        await this.service.purgePrefixes(zoneId, items, invalidate);
      } else if (mode === 'hosts') {
        await this.service.purgeHosts(zoneId, items, invalidate);
      } else if (mode === 'tags') {
        await this.service.purgeTags(zoneId, items, invalidate);
      } else {
        await this.service.purgeFiles(zoneId, items, invalidate);
      }
      return '';
    } catch (e) {
      return (e as Error).message ?? (invalidate ? '标记失败' : '清除失败');
    }
  }
}

@ComponentV2
export struct ZoneSettingsPage {
  @Local vm: ZoneSettingsVM = new ZoneSettingsVM();
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local purgeUrls: string = '';
  @Local purgeModeIndex: number = 0;
  /// 缓存动作：false = 清除（purge），true = 标记过期（invalidate）
  @Local invalidateMode: boolean = false;

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  private purgeMode(): PurgeModeSpec {
    return PURGE_MODES[this.purgeModeIndex];
  }

  private purgeCount(): number {
    return this.purgeUrls.split('\n').map((u: string) => u.trim()).filter((u: string) => u !== '').length;
  }

  /// 暂停 / 恢复前先说清影响。
  /// 注意 Toggle 是用户手势直接翻的：取消 / 失败必须把 vm.paused 显式改回去，
  /// 靠 @Param 变化才能把开关纠回原位（不改状态 = 开关停在错误位置）。
  private confirmPause(on: boolean): void {
    if (!authManager.hasScope(Scopes.ZONE_WRITE)) {
      this.toast(`当前授权未包含域名写入权限（${Scopes.ZONE_WRITE}）`);
      this.vm.paused = !on;
      return;
    }
    const name = this.zoneName === '' ? '该域名' : this.zoneName;
    this.getUIContext().showAlertDialog({
      title: on ? '暂停 Cloudflare？' : '恢复 Cloudflare？',
      message: on
        ? `暂停后，${name} 的流量不再经过 Cloudflare：WAF、缓存加速与源站 IP 隐藏都会失效，DNS 仍由 Cloudflare 解析。生效约需 5 分钟。`
        : `恢复后，${name} 的流量重新经由 Cloudflare 代理，缓存与安全防护随之生效。生效约需 5 分钟。`,
      primaryButton: {
        value: '取消',
        action: () => {
          this.vm.paused = !on;
        },
      },
      secondaryButton: {
        value: on ? '确认暂停' : '确认恢复',
        fontColor: on ? '#DC2626' : BRAND_ORANGE,
        action: () => {
          this.vm.setPaused(this.zoneId, on).then((err: string) => {
            if (err !== '') {
              this.vm.paused = !on;
              this.toast(err);
            }
          });
        },
      },
      cancel: () => {
        this.vm.paused = !on;
      },
    });
  }

  private confirmPurgeTargets(): void {
    if (!authManager.hasScope(Scopes.CACHE_PURGE)) {
      this.toast(`当前授权未包含缓存清除权限（${Scopes.CACHE_PURGE}）`);
      return;
    }
    const mode = this.purgeMode();
    const invalidate = this.invalidateMode;
    this.getUIContext().showAlertDialog({
      title: invalidate ? `按${mode.label}标记过期` : `按${mode.label}清除缓存`,
      message: invalidate
        ? `共 ${this.purgeCount()} 条。${INVALIDATE_NOTE}`
        : `共 ${this.purgeCount()} 条。${mode.confirmText}`,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: invalidate ? '标记过期' : '清除',
        fontColor: invalidate ? BRAND_ORANGE : '#DC2626',
        action: () => {
          this.vm.purgeTargets(this.zoneId, mode.key, this.purgeUrls, invalidate).then((err: string) => {
            if (err === '') {
              this.purgeUrls = '';
              this.toast(invalidate ? '已标记为过期' : '已提交缓存清除');
            } else {
              this.toast(err);
            }
          });
        },
      },
    });
  }

  /// 当前 AI 策略取值（三选择器共用一个 Builder，按字段名取值）
  private aiPolicyValue(field: string): string {
    if (field === 'ai_search') {
      return this.vm.aiSearch;
    }
    if (field === 'ai_user') {
      return this.vm.aiUser;
    }
    return this.vm.aiTraining;
  }

  /// 写单个 AI 策略字段（PUT 合并语义，只带这一个键）
  private setAiPolicy(field: string, value: string): void {
    if (this.vm.isSaving || this.aiPolicyValue(field) === value) {
      return;
    }
    const body: BotManagementConfig = {};
    if (field === 'ai_search') {
      body.ai_search = value;
    } else if (field === 'ai_user') {
      body.ai_user = value;
    } else {
      body.ai_training = value;
    }
    this.vm.setBotField(this.zoneId, body).then((err: string) => {
      this.toast(err);
    });
  }

  private setPrecursor(mode: string): void {
    if (this.vm.isSaving || this.vm.precursorMode === mode) {
      return;
    }
    if (!authManager.hasScope(Scopes.PRECURSOR_WRITE)) {
      this.toast(`当前授权未包含会话级机器人检测写入权限（${Scopes.PRECURSOR_WRITE}），可在「设置 → 身份」中升级授权`);
      return;
    }
    this.vm.setPrecursorMode(this.zoneId, mode).then((err: string) => {
      this.toast(err);
    });
  }

  /// Precursor 默认模式选择器（同 AI 策略的胶囊样式；未知取值不高亮任何项）
  @Builder
  precursorPicker() {
    Column({ space: 6 }) {
      Text('会话级机器人检测')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Text('在整个会话中持续评估访客行为（Precursor）')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(PRECURSOR_OPTIONS, (opt: AiBotsOption) => {
          Text(opt.label)
            .fontSize(13)
            .fontWeight(this.vm.precursorMode === opt.value ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.vm.precursorMode === opt.value ? Color.White : $r('sys.color.font_secondary'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(this.vm.precursorMode === opt.value
              ? BRAND_ORANGE : $r('sys.color.background_secondary'))
            .borderRadius(14)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.setPrecursor(opt.value);
            })
        }, (opt: AiBotsOption) => `precursor-${opt.value}`)
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .padding({ left: 14, right: 14, top: 12, bottom: 4 })
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(14)
    .margin({ left: 16, right: 16 })
  }

  /// AI 爬虫策略选择器：标题 + 说明 + 可换行的选项胶囊
  @Builder
  aiPolicyPicker(field: string, title: string, subtitle: string, options: AiBotsOption[]) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Text(subtitle)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(options, (opt: AiBotsOption) => {
          Text(opt.label)
            .fontSize(13)
            .fontWeight(this.aiPolicyValue(field) === opt.value ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.aiPolicyValue(field) === opt.value
              ? Color.White : $r('sys.color.font_secondary'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(this.aiPolicyValue(field) === opt.value
              ? BRAND_ORANGE : $r('sys.color.background_secondary'))
            .borderRadius(14)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.setAiPolicy(field, opt.value);
            })
        }, (opt: AiBotsOption) => `${field}-${opt.value}`)
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .padding({ left: 14, right: 14, top: 12, bottom: 4 })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载设置…' })
          }
          .width('100%')
          .height('100%')
        } else {
          Scroll() {
            Column({ space: 4 }) {
              Column() {
                SectionHeader({ title: '快速开关' })
                Column() {
                  ToggleRow({
                    title: '开发模式',
                    subtitle: '绕过缓存直连源站，3 小时后自动关闭',
                    isOn: this.vm.developmentMode,
                    isEnabled: !this.vm.isSaving,
                    onToggle: (on: boolean) => {
                      this.vm.setDevelopmentMode(this.zoneId, on).then((err: string) => {
                        this.toast(err);
                      });
                    },
                  })
                  ToggleRow({
                    title: 'Under Attack 模式',
                    subtitle: '对所有访客弹出质询页，遭受攻击时使用',
                    isOn: this.vm.underAttack,
                    isEnabled: !this.vm.isSaving,
                    onToggle: (on: boolean) => {
                      this.vm.setUnderAttack(this.zoneId, on).then((err: string) => {
                        this.toast(err);
                      });
                    },
                  })
                  // 仅在当前套餐可改时出现（Pro 起；免费套餐读得到但不可改）
                  if (this.vm.aiTrainingRedirectAvailable) {
                    ToggleRow({
                      title: 'AI 训练重定向',
                      subtitle: '把用于模型训练的爬虫引走',
                      isOn: this.vm.aiTrainingRedirect,
                      isEnabled: !this.vm.isSaving,
                      onToggle: (on: boolean) => {
                        this.vm.setAiTrainingRedirect(this.zoneId, on).then((err: string) => {
                          this.toast(err);
                        });
                      },
                    })
                  }
                  if (this.vm.markdownForAgentsAvailable) {
                    ToggleRow({
                      title: '面向 Agent 的 Markdown',
                      subtitle: '按请求把页面转成 Markdown 返回',
                      isOn: this.vm.markdownForAgents,
                      isEnabled: !this.vm.isSaving,
                      onToggle: (on: boolean) => {
                        this.vm.setMarkdownForAgents(this.zoneId, on).then((err: string) => {
                          this.toast(err);
                        });
                      },
                    })
                  }
                  ToggleRow({
                    title: '暂停 Cloudflare',
                    subtitle: '流量绕过 Cloudflare，仅保留 DNS 解析',
                    isOn: this.vm.paused,
                    isEnabled: !this.vm.isSaving,
                    onToggle: (on: boolean) => {
                      // 先乐观翻，取消 / 失败在 confirmPause 里回滚
                      this.vm.paused = on;
                      this.confirmPause(on);
                    },
                  })
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .clip(true)
                .margin({ left: 16, right: 16 })
              }
              .width('100%')

              // 机器人管控走 bot-management.* 这条独立权限链路，全套餐可用；
              // 读不到（无该 scope）就整组不显示。
              if (this.vm.botConfigLoaded) {
                Column() {
                  SectionHeader({ title: 'AI 与机器人' })
                  Column({ space: 10 }) {
                    // 新版（2026-09-15）三类策略取代单一的「AI 爬虫」；老响应没有新字段时保留旧选择器
                    if (this.vm.splitAiControls) {
                      this.aiPolicyPicker('ai_search', 'AI 搜索', '为回答问题而索引内容的爬虫', AI_POLICY_OPTIONS)
                      this.aiPolicyPicker('ai_user', 'AI 助手与 Agent', '代表用户实时抓取页面的机器人', AI_POLICY_OPTIONS)
                      this.aiPolicyPicker('ai_training', 'AI 训练', '抓取内容用于训练或微调模型的爬虫', AI_TRAINING_OPTIONS)
                    } else {
                      Column({ space: 6 }) {
                        Text('AI 爬虫')
                          .fontSize(15)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('sys.color.font_primary'))
                          .width('100%')
                        Text('抓取内容用于训练或问答的机器人')
                          .fontSize(12)
                          .fontColor($r('sys.color.font_secondary'))
                          .width('100%')
                        Row({ space: 8 }) {
                          ForEach(AI_BOTS_OPTIONS, (opt: AiBotsOption) => {
                            Text(opt.label)
                              .fontSize(13)
                              .fontWeight(this.vm.aiBotsProtection === opt.value ? FontWeight.Medium : FontWeight.Normal)
                              .fontColor(this.vm.aiBotsProtection === opt.value
                                ? Color.White : $r('sys.color.font_secondary'))
                              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                              .backgroundColor(this.vm.aiBotsProtection === opt.value
                                ? BRAND_ORANGE : $r('sys.color.background_secondary'))
                              .borderRadius(14)
                              .onClick(() => {
                                if (this.vm.isSaving) {
                                  return;
                                }
                                const body: BotManagementConfig = { ai_bots_protection: opt.value };
                                this.vm.setBotField(this.zoneId, body).then((err: string) => {
                                  this.toast(err);
                                });
                              })
                          }, (opt: AiBotsOption) => opt.value)
                        }
                        .width('100%')
                        .margin({ top: 4 })
                      }
                      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                    }

                    ToggleRow({
                      title: '链接迷宫',
                      subtitle: '用无尽链接消耗违规爬虫',
                      isOn: this.vm.crawlerProtection,
                      isEnabled: !this.vm.isSaving,
                      onToggle: (on: boolean) => {
                        const body: BotManagementConfig = { crawler_protection: on ? 'enabled' : 'disabled' };
                        this.vm.setBotField(this.zoneId, body).then((err: string) => {
                          this.toast(err);
                        });
                      },
                    })
                    ToggleRow({
                      title: '拦截内容机器人',
                      subtitle: '拦下低可信自动流量，已验证的机器人除外',
                      isOn: this.vm.contentBotsProtection,
                      isEnabled: !this.vm.isSaving,
                      onToggle: (on: boolean) => {
                        const body: BotManagementConfig = { content_bots_protection: on ? 'block' : 'disabled' };
                        this.vm.setBotField(this.zoneId, body).then((err: string) => {
                          this.toast(err);
                        });
                      },
                    })
                    // 托管 robots.txt 已并入 Bot Preference Sync：响应带新键就只显示新开关
                    if (this.vm.hasPreferenceSync) {
                      ToggleRow({
                        title: '按偏好生成 robots.txt',
                        subtitle: '根据以上三项，由 Cloudflare 生成 robots.txt 规则',
                        isOn: this.vm.preferenceSync,
                        isEnabled: !this.vm.isSaving,
                        onToggle: (on: boolean) => {
                          const body: BotManagementConfig = { bot_preference_sync_enabled: on };
                          this.vm.setBotField(this.zoneId, body).then((err: string) => {
                            this.toast(err);
                          });
                        },
                      })
                    } else {
                      ToggleRow({
                        title: '托管 robots.txt',
                        subtitle: '由 Cloudflare 维护，置于现有内容之前',
                        isOn: this.vm.managedRobotsTxt,
                        isEnabled: !this.vm.isSaving,
                        onToggle: (on: boolean) => {
                          const body: BotManagementConfig = { is_robots_txt_managed: on };
                          this.vm.setBotField(this.zoneId, body).then((err: string) => {
                            this.toast(err);
                          });
                        },
                      })
                    }
                    ToggleRow({
                      title: '内容使用声明',
                      subtitle: '在 robots.txt 中声明内容的使用许可',
                      isOn: this.vm.robotsLicense,
                      isEnabled: !this.vm.isSaving,
                      onToggle: (on: boolean) => {
                        const body: BotManagementConfig = { cf_robots_variant: on ? 'policy_only' : 'off' };
                        this.vm.setBotField(this.zoneId, body).then((err: string) => {
                          this.toast(err);
                        });
                      },
                    })
                  }
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(14)
                  .clip(true)
                  .margin({ left: 16, right: 16 })
                }
                .width('100%')
              }

              // Precursor 走 precursor.* 独立权限链路；GET 失败（无权限 / 接口异常）整行不显示
              if (this.vm.precursorLoaded) {
                Column() {
                  SectionHeader({ title: '机器人检测' })
                  this.precursorPicker()
                }
                .width('100%')
              }

              Column() {
                SectionHeader({ title: '按目标清除缓存' })
                Column({ space: 10 }) {
                  // 清除 / 标记过期：同一组目标、同一权限，只是端点不同
                  Row({ space: 6 }) {
                    ForEach([false, true], (inv: boolean) => {
                      Text(inv ? '标记过期' : '清除')
                        .fontSize(13)
                        .fontWeight(this.invalidateMode === inv ? FontWeight.Medium : FontWeight.Normal)
                        .fontColor(this.invalidateMode === inv ? Color.White : $r('sys.color.font_secondary'))
                        .textAlign(TextAlign.Center)
                        .layoutWeight(1)
                        .height(32)
                        .borderRadius(16)
                        .backgroundColor(this.invalidateMode === inv ? BRAND_ORANGE : $r('sys.color.background_secondary'))
                        .onClick(() => {
                          this.invalidateMode = inv;
                        })
                    }, (inv: boolean) => inv ? 'invalidate' : 'purge')
                  }
                  .width('100%')

                  if (this.invalidateMode) {
                    Text(INVALIDATE_NOTE)
                      .fontSize(11)
                      .fontColor($r('sys.color.font_secondary'))
                      .width('100%')
                  }

                  Row({ space: 8 }) {
                    ForEach(PURGE_MODES, (spec: PurgeModeSpec, index: number) => {
                      Text(spec.label)
                        .fontSize(13)
                        .fontWeight(this.purgeModeIndex === index ? FontWeight.Medium : FontWeight.Normal)
                        .fontColor(this.purgeModeIndex === index ? $r('app.color.oc_brand_text') : $r('sys.color.font_secondary'))
                        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                        .backgroundColor(this.purgeModeIndex === index ? $r('app.color.oc_brand_bg') : $r('sys.color.background_secondary'))
                        .borderRadius(14)
                        .onClick(() => {
                          this.purgeModeIndex = index;
                        })
                    }, (spec: PurgeModeSpec) => spec.key)
                    Blank()
                  }
                  .width('100%')

                  Text(this.purgeMode().note)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_secondary'))
                    .width('100%')

                  TextArea({ text: this.purgeUrls, placeholder: this.purgeMode().placeholder })
                    .fontSize(13)
                    .height(100)
                    .width('100%')
                    .onChange((value: string) => {
                      this.purgeUrls = value;
                    })
                  Button(this.invalidateMode ? `按${this.purgeMode().label}标记过期` : `按${this.purgeMode().label}清除`)
                    .width('100%')
                    .height(42)
                    .fontSize(14)
                    .fontColor(Color.White)
                    .backgroundColor($r('app.color.oc_brand_cta'))
                    .enabled(this.purgeUrls.trim() !== '')
                    .onClick(() => {
                      this.confirmPurgeTargets();
                    })
                }
                .padding(14)
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .margin({ left: 16, right: 16 })
              }
              .width('100%')
              .margin({ bottom: 24 })
            }
            .width('100%')
          }
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .width('100%')
          .height('100%')
        }
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: `${this.zoneName} · 设置` } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      this.vm.load(param.zoneId).catch(() => {
      });
      // 机器人管控是另一条权限链路，与上面的 zone-settings 读取互不阻塞
      this.vm.loadBotConfig(param.zoneId).catch(() => {
      });
      this.vm.loadPrecursor(param.zoneId).catch(() => {
      });
    })
  }
}
