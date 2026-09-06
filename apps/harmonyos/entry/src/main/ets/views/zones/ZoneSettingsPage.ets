// Zone 设置：开发模式 / Under Attack 模式 / 暂停 Cloudflare + 按目标清缓存（URL / 前缀 / 主机 /
// 缓存标签四模式，对照 iOS PurgeCacheSheet；POST /zones/{id}/purge_cache 的 files/prefixes/hosts/tags）。
// 注意暂停与另两个开关不同源：开发模式 / Under Attack 走 zone settings（zone-settings.*），
// 暂停读写域名本身（zone.read / zone.write），权限链路各自独立。
import { ZoneRouteParam } from '../../models/Routes';
import { BotManagementConfig, ZoneSettingsService } from '../../services/ZoneSettingsService';
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
  // AI 内容控制（Pro/Business 起）。免费套餐读取即失败，aiSettingsAvailable 保持 false，
  // 界面整组隐藏——不给用户两个永远打不开的开关。
  @Trace aiTrainingRedirect: boolean = false;
  @Trace markdownForAgents: boolean = false;
  @Trace aiSettingsAvailable: boolean = false;
  // 机器人管控（bot-management.*，全套餐可用；与 zone-settings.* 是两条权限链路）
  @Trace aiBotsProtection: string = 'disabled';
  @Trace crawlerProtection: boolean = false;
  @Trace contentBotsProtection: boolean = false;
  @Trace robotsLicense: boolean = false;
  @Trace managedRobotsTxt: boolean = false;
  @Trace botConfigLoaded: boolean = false;
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
      let aiAvailable: boolean = false;
      try {
        this.aiTrainingRedirect = (await this.service.getSetting(zoneId, 'redirects_for_ai_training')) === 'on';
        aiAvailable = true;
      } catch (e) {
      }
      try {
        this.markdownForAgents = (await this.service.getSetting(zoneId, 'content_converter')) === 'on';
        aiAvailable = true;
      } catch (e) {
      }
      this.aiSettingsAvailable = aiAvailable;
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
    this.botConfigLoaded = true;
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

  /// 按目标清缓存：mode 为 files 或 prefixes 或 hosts 或 tags
  async purgeTargets(zoneId: string, mode: string, text: string): Promise<string> {
    const items = text.split('\n').map((u: string) => u.trim()).filter((u: string) => u !== '');
    if (items.length === 0) {
      return '请输入至少一条内容';
    }
    if (items.length > 30) {
      return '单次最多 30 条';
    }
    try {
      if (mode === 'prefixes') {
        await this.service.purgePrefixes(zoneId, items);
      } else if (mode === 'hosts') {
        await this.service.purgeHosts(zoneId, items);
      } else if (mode === 'tags') {
        await this.service.purgeTags(zoneId, items);
      } else {
        await this.service.purgeFiles(zoneId, items);
      }
      return '';
    } catch (e) {
      return (e as Error).message ?? '清除失败';
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

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
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
    this.getUIContext().showAlertDialog({
      title: `按${mode.label}清除缓存`,
      message: `共 ${this.purgeCount()} 条。${mode.confirmText}`,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '清除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.purgeTargets(this.zoneId, mode.key, this.purgeUrls).then((err: string) => {
            if (err === '') {
              this.purgeUrls = '';
              this.toast('已提交缓存清除');
            } else {
              this.toast(err);
            }
          });
        },
      },
    });
  }

  build() {
    NavDestination() {
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
                  // 仅在该域名支持这组设置时出现（免费套餐读取即失败）
                  if (this.vm.aiSettingsAvailable) {
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
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
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
                  .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                  .clip(true)
                  .margin({ left: 16, right: 16 })
                }
                .width('100%')
              }

              Column() {
                SectionHeader({ title: '按目标清除缓存' })
                Column({ space: 10 }) {
                  Row({ space: 8 }) {
                    ForEach(PURGE_MODES, (spec: PurgeModeSpec, index: number) => {
                      Text(spec.label)
                        .fontSize(13)
                        .fontWeight(this.purgeModeIndex === index ? FontWeight.Medium : FontWeight.Normal)
                        .fontColor(this.purgeModeIndex === index ? Color.White : $r('sys.color.font_secondary'))
                        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                        .backgroundColor(this.purgeModeIndex === index ? BRAND_ORANGE : $r('sys.color.background_secondary'))
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
                  Button(`按${this.purgeMode().label}清除`)
                    .width('100%')
                    .height(42)
                    .fontSize(14)
                    .fontColor(Color.White)
                    .backgroundColor(BRAND_ORANGE)
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
      .width('100%')
      .height('100%')
    }
    .title(`${this.zoneName} · 设置`)
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
    })
  }
}
