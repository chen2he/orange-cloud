// 域名的 DNS 设置：DNSSEC、CNAME 展平、多提供商 DNS、名称服务器、域名模式。
// 与 DNS 记录列表分开——那里是逐条记录，这里是 zone 级策略。
import { ZoneRouteParam } from '../../models/Routes';
import { DnsSettingsService, ZoneDnsSettings, ZoneDnssec, ZoneNameservers } from '../../services/DnsSettingsService';
import { Scopes } from '../../core/auth/Scopes';
import { authManager } from '../../core/auth/AuthManager';
import { OCLoading, SectionHeader, ToggleRow } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';

interface ZoneModeOption {
  value: string;
  label: string;
}

const ZONE_MODES: ZoneModeOption[] = [
  { value: 'standard', label: '标准' },
  { value: 'cdn_only', label: '仅 CDN' },
  { value: 'dns_only', label: '仅 DNS' },
];

function dnssecStatusText(status: string): string {
  if (status === 'active') {
    return '已启用';
  }
  if (status === 'pending') {
    return '待在注册商处添加 DS 记录';
  }
  if (status === 'pending-disabled') {
    return '正在停用';
  }
  if (status === 'error') {
    return '出错';
  }
  return '未启用';
}

@ObservedV2
class DnsSettingsVM {
  @Trace settings: ZoneDnsSettings | null = null;
  @Trace dnssec: ZoneDnssec | null = null;
  @Trace isLoading: boolean = false;
  @Trace isSaving: boolean = false;
  private service: DnsSettingsService = new DnsSettingsService();

  async load(zoneId: string): Promise<void> {
    this.isLoading = true;
    // 两条链路权限不同，任一失败不连累另一条
    try {
      this.settings = await this.service.settings(zoneId);
    } catch (e) {
    }
    try {
      this.dnssec = await this.service.dnssec(zoneId);
    } catch (e) {
    }
    this.isLoading = false;
  }

  async apply(zoneId: string, body: ZoneDnsSettings): Promise<string> {
    this.isSaving = true;
    try {
      this.settings = await this.service.updateSettings(zoneId, body);
      return '';
    } catch (e) {
      await this.load(zoneId);
      return (e as Error).message ?? '设置失败';
    } finally {
      this.isSaving = false;
    }
  }

  async setDnssec(zoneId: string, on: boolean): Promise<string> {
    this.isSaving = true;
    try {
      this.dnssec = await this.service.setDnssec(zoneId, on);
      return '';
    } catch (e) {
      return (e as Error).message ?? '设置失败';
    } finally {
      this.isSaving = false;
    }
  }
}

@ComponentV2
export struct ZoneDnsSettingsPage {
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local vm: DnsSettingsVM = new DnsSettingsVM();
  private pathStack: NavPathStack | null = null;
  private canWriteSettings: boolean = authManager.hasScope(Scopes.ZONE_DNS_SETTINGS_WRITE);
  private canWriteDns: boolean = authManager.hasScope(Scopes.DNS_WRITE);

  private toast(msg: string): void {
    if (msg !== '') {
      promptAction.showToast({ message: msg });
    }
  }

  private copyDs(ds: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, ds);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: '已复制' });
    }).catch(() => {
    });
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载 DNS 设置…' })
          }
          .width('100%')
          .height('100%')
        } else {
          Scroll() {
            Column({ space: 4 }) {
              if (this.vm.dnssec !== null) {
                Column() {
                  SectionHeader({ title: 'DNSSEC' })
                  Column({ space: 8 }) {
                    ToggleRow({
                      title: 'DNSSEC',
                      subtitle: dnssecStatusText(this.vm.dnssec?.status ?? ''),
                      isOn: (this.vm.dnssec?.status === 'active' || this.vm.dnssec?.status === 'pending'),
                      isEnabled: this.canWriteDns && !this.vm.isSaving,
                      onToggle: (on: boolean) => {
                        this.vm.setDnssec(this.zoneId, on).then((err: string) => this.toast(err));
                      },
                    })
                    // DS 记录必须由用户粘到注册商处，DNSSEC 才真正生效——最易被忽略的一步
                    if ((this.vm.dnssec?.ds ?? '') !== '') {
                      Column({ space: 4 }) {
                        Text('DS 记录')
                          .fontSize(12)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('sys.color.font_secondary'))
                          .width('100%')
                        Text(this.vm.dnssec?.ds)
                          .fontSize(12)
                          .fontColor($r('sys.color.font_primary'))
                          .width('100%')
                          .copyOption(CopyOptions.LocalDevice)
                        Text('复制 DS 记录')
                          .fontSize(13)
                          .fontColor($r('sys.color.font_secondary'))
                          .onClick(() => this.copyDs(this.vm.dnssec?.ds ?? ''))
                        if (this.vm.dnssec?.status === 'pending') {
                          Text('还需把 DS 记录添加到你的域名注册商处，DNSSEC 才会真正生效。')
                            .fontSize(12)
                            .fontColor($r('sys.color.font_secondary'))
                            .width('100%')
                        }
                      }
                      .padding({ left: 14, right: 14, bottom: 12 })
                    }
                  }
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(14)
                  .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                  .clip(true)
                  .margin({ left: 16, right: 16 })
                }
                .width('100%')
              }

              if (this.vm.settings !== null) {
                Column() {
                  SectionHeader({ title: `解析（${this.zoneName}）` })
                  Column() {
                    ToggleRow({
                      title: '展平所有 CNAME',
                      subtitle: '把 CNAME 解析成最终 IP 返回',
                      isOn: this.vm.settings?.flatten_all_cnames === true,
                      isEnabled: this.canWriteSettings && !this.vm.isSaving,
                      onToggle: (on: boolean) => {
                        const body: ZoneDnsSettings = { flatten_all_cnames: on };
                        this.vm.apply(this.zoneId, body).then((err: string) => this.toast(err));
                      },
                    })
                    ToggleRow({
                      title: '多提供商 DNS',
                      subtitle: '允许与其他 DNS 服务商共存',
                      isOn: this.vm.settings?.multi_provider === true,
                      isEnabled: this.canWriteSettings && !this.vm.isSaving,
                      onToggle: (on: boolean) => {
                        const body: ZoneDnsSettings = { multi_provider: on };
                        this.vm.apply(this.zoneId, body).then((err: string) => this.toast(err));
                      },
                    })
                    ToggleRow({
                      title: '高级名称服务器',
                      subtitle: '使用 Cloudflare 高级名称服务器',
                      isOn: this.vm.settings?.nameservers?.type === 'cloudflare.advanced',
                      isEnabled: this.canWriteSettings && !this.vm.isSaving,
                      onToggle: (on: boolean) => {
                        const ns: ZoneNameservers = { type: on ? 'cloudflare.advanced' : 'cloudflare.standard' };
                        const body: ZoneDnsSettings = { nameservers: ns };
                        this.vm.apply(this.zoneId, body).then((err: string) => this.toast(err));
                      },
                    })
                    Column({ space: 6 }) {
                      Text('域名模式')
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('sys.color.font_primary'))
                        .width('100%')
                      Row({ space: 8 }) {
                        ForEach(ZONE_MODES, (opt: ZoneModeOption) => {
                          Text(opt.label)
                            .fontSize(13)
                            .fontColor((this.vm.settings?.zone_mode ?? 'standard') === opt.value
                              ? Color.White : $r('sys.color.font_secondary'))
                            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                            .backgroundColor((this.vm.settings?.zone_mode ?? 'standard') === opt.value
                              ? '#F48120' : $r('sys.color.background_secondary'))
                            .borderRadius(14)
                            .onClick(() => {
                              if (!this.canWriteSettings || this.vm.isSaving) {
                                return;
                              }
                              const body: ZoneDnsSettings = { zone_mode: opt.value };
                              this.vm.apply(this.zoneId, body).then((err: string) => this.toast(err));
                            })
                        }, (opt: ZoneModeOption) => opt.value)
                      }
                      .width('100%')
                    }
                    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                  }
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(14)
                  .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                  .clip(true)
                  .margin({ left: 16, right: 16 })
                }
                .width('100%')
              }

              if (this.vm.settings === null && this.vm.dnssec === null) {
                Text('读不到该域名的 DNS 设置。可能是权限不足，或此域名不支持这些选项。')
                  .fontSize(13)
                  .fontColor($r('sys.color.font_secondary'))
                  .padding(24)
              }
            }
            .width('100%')
            .padding({ top: 8, bottom: 24 })
          }
          .width('100%')
          .height('100%')
        }
      }
    }
    .title('DNS 设置')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      this.vm.load(param.zoneId).catch(() => {
      });
    })
  }
}
