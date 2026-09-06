import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 在 Cloudflare 注册的域名：到期日、自动续费、转移锁（只读）。
// 域名注册是花钱操作，移动端不做。
import { DomainRegistration, RegistrarService } from '../../services/RegistrarService';
import { accountStore } from '../../core/store/AccountStore';
import { Scopes } from '../../core/auth/Scopes';
import { authManager } from '../../core/auth/AuthManager';
import { OCLoading, SectionHeader, ToggleRow } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';
import { promptAction } from '@kit.ArkUI';

function statusText(status: string): string {
  if (status === 'active') {
    return '正常';
  }
  if (status === 'registration_pending') {
    return '注册中';
  }
  if (status === 'expired') {
    return '已过期';
  }
  if (status === 'suspended') {
    return '已暂停';
  }
  if (status === 'redemption_period') {
    return '赎回期';
  }
  return '未知';
}

/// 距到期天数；NaN 表示无法解析
function daysUntil(expiresAt: string): number {
  const t = Date.parse(expiresAt);
  if (isNaN(t)) {
    return NaN;
  }
  return Math.floor((t - new Date().getTime()) / 86400000);
}

@ObservedV2
class RegistrarVM {
  @Trace items: DomainRegistration[] = [];
  @Trace isLoading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace isSaving: boolean = false;
  private service: RegistrarService = new RegistrarService();

  async load(): Promise<void> {
    this.isLoading = true;
    try {
      const list = await this.service.registrations(accountStore.selectedId);
      // 快到期又没开自动续费的排最前
      this.items = list.sort((a: DomainRegistration, b: DomainRegistration) => {
        const da = daysUntil(a.expires_at ?? '');
        const db = daysUntil(b.expires_at ?? '');
        const ua = (!isNaN(da) && da <= 30 && a.auto_renew !== true) ? 0 : 1;
        const ub = (!isNaN(db) && db <= 30 && b.auto_renew !== true) ? 0 : 1;
        if (ua !== ub) {
          return ua - ub;
        }
        return (isNaN(da) ? 99999 : da) - (isNaN(db) ? 99999 : db);
      });
      this.loaded = true;
    } catch (e) {
    } finally {
      this.isLoading = false;
    }
  }

  /// 接口是异步 workflow，返回后回读列表拿真实状态
  async setAutoRenew(item: DomainRegistration, enabled: boolean): Promise<string> {
    this.isSaving = true;
    try {
      await this.service.setAutoRenew(accountStore.selectedId, item.domain_name, enabled);
      await this.load();
      return '';
    } catch (e) {
      return (e as Error).message ?? '设置失败';
    } finally {
      this.isSaving = false;
    }
  }
}

@ComponentV2
export struct RegistrarPage {
  @Local vm: RegistrarVM = new RegistrarVM();
  private canAdmin: boolean = authManager.hasScope(Scopes.REGISTRAR_ADMIN);

  private toast(msg: string): void {
    if (msg !== '') {
      ocSnack(this.getUIContext(), msg);
    }
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading && !this.vm.loaded) {
          Column() {
            OCLoading({ text: '正在加载域名…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.items.length === 0) {
          Column() {
            Text('此账号下没有在 Cloudflare 注册的域名。')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding(32)
        } else {
          Scroll() {
            Column() {
              SectionHeader({ title: '已注册域名' })
              Column({ space: 10 }) {
                ForEach(this.vm.items, (item: DomainRegistration) => {
                  Column({ space: 4 }) {
                    Row() {
                      Text(item.domain_name)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('sys.color.font_primary'))
                        .layoutWeight(1)
                      Text(statusText(item.status ?? ''))
                        .fontSize(12)
                        .fontColor(item.status === 'active'
                          ? $r('sys.color.font_secondary') : '#EF6C00')
                    }
                    .width('100%')

                    if ((item.expires_at ?? '') !== '' && !isNaN(daysUntil(item.expires_at ?? ''))) {
                      Text(daysUntil(item.expires_at ?? '') >= 0
                        ? `还剩 ${daysUntil(item.expires_at ?? '')} 天到期`
                        : '已过期')
                        .fontSize(12)
                        .fontColor(daysUntil(item.expires_at ?? '') <= 30 && item.auto_renew !== true
                          ? '#EF6C00' : $r('sys.color.font_secondary'))
                        .width('100%')
                    }

                    ToggleRow({
                      title: '自动续费',
                      subtitle: '到期前 30 天内自动扣默认支付方式',
                      isOn: item.auto_renew === true,
                      isEnabled: this.canAdmin && !this.vm.isSaving,
                      onToggle: (on: boolean) => {
                        this.vm.setAutoRenew(item, on).then((err: string) => this.toast(err));
                      },
                    })

                    // 转移锁在新版 API 里只读，做成开关会误导用户以为能改
                    if (item.locked !== undefined) {
                      Text(item.locked === true ? '转移锁：已开启' : '转移锁：未开启')
                        .fontSize(12)
                        .fontColor($r('sys.color.font_secondary'))
                        .width('100%')
                    }
                  }
                  .width('100%')
                  .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                }, (item: DomainRegistration) => item.domain_name)
              }
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(14)
              .border({ width: 0.5, color: $r('sys.color.comp_divider') })
              .clip(true)
              .margin({ left: 16, right: 16 })

              Text('域名注册与转移锁请在 Cloudflare 控制台操作。')
                .fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
                .padding({ left: 20, right: 20, top: 12, bottom: 24 })
            }
            .width('100%')
            .padding({ top: 8 })
          }
          .width('100%')
          .height('100%')
        }
      }
    }
    .titleBar({ content: { title: { mainTitle: '域名注册' } } })
    .onReady(() => {
      this.vm.load().catch(() => {
      });
    })
  }
}
