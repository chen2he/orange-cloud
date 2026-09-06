import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 通知告警：告警策略（查看+删除）+ Webhook 目标（查看+新建）（对齐 Android CFAlertingScreen）。
import { AlertPolicy, WebhookDestination } from '../../models/AccountModels';
import { AccountModuleService } from '../../services/AccountModuleService';
import { accountStore } from '../../core/store/AccountStore';
import { BRAND_ORANGE, OCEmpty, OCError, OCLoading, SectionHeader } from '../common/Components';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

@ObservedV2
class AlertingVM {
  @Trace policies: AlertPolicy[] = [];
  @Trace webhooks: WebhookDestination[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  private service: AccountModuleService = new AccountModuleService();

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    const accountId = accountStore.selectedId;
    try {
      this.policies = await this.service.alertPolicies(accountId);
      try {
        this.webhooks = await this.service.webhooks(accountId);
      } catch (e) {
        this.webhooks = [];
      }
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async addWebhook(name: string, url: string): Promise<string> {
    try {
      const created = await this.service.createWebhook(accountStore.selectedId, name, url);
      this.webhooks = this.webhooks.concat([created]);
      return '';
    } catch (e) {
      return (e as Error).message ?? '创建失败';
    }
  }

  async removePolicy(policyId: string): Promise<string> {
    try {
      await this.service.deletePolicy(accountStore.selectedId, policyId);
      this.policies = this.policies.filter((p: AlertPolicy) => p.id !== policyId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }

  async removeWebhook(webhookId: string): Promise<string> {
    try {
      await this.service.deleteWebhook(accountStore.selectedId, webhookId);
      this.webhooks = this.webhooks.filter((w: WebhookDestination) => w.id !== webhookId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }

  async addPolicy(name: string, alertType: string, webhookId: string): Promise<string> {
    try {
      const created = await this.service.createPolicy(accountStore.selectedId, name, alertType, webhookId);
      this.policies = this.policies.concat([created]);
      return '';
    } catch (e) {
      return (e as Error).message ?? '创建失败';
    }
  }
}

interface AlertTypeSpec {
  id: string;
  label: string;
}

const ALERT_TYPES: AlertTypeSpec[] = [
  { id: 'universal_ssl_event_type', label: 'Universal SSL 证书事件' },
  { id: 'dos_attack_l7', label: 'L7 DDoS 攻击' },
  { id: 'clickhouse_alert_fw_anomaly', label: 'WAF 异常' },
  { id: 'billing_usage_alert', label: '账单用量' },
  { id: 'health_check_status_notification', label: '健康检查状态' },
  { id: 'http_alert_origin_error', label: '源站错误率' },
];

@ComponentV2
export struct AlertingPage {
  @Local vm: AlertingVM = new AlertingVM();
  @Local sheetVisible: boolean = false;
  @Local fName: string = '';
  @Local fUrl: string = '';
  @Local policySheetVisible: boolean = false;
  @Local pName: string = '';
  @Local pTypeIndex: number = 0;
  @Local pWebhookId: string = '';

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  @Builder
  policySheet() {
    Column({ space: 12 }) {
      Text('新建告警策略')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.pName, placeholder: '策略名称' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.pName = value;
        })
      Row({ space: 12 }) {
        Text('告警类型')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Select(ALERT_TYPES.map((t: AlertTypeSpec): SelectOption => ({ value: t.label })))
          .selected(this.pTypeIndex)
          .value(ALERT_TYPES[this.pTypeIndex].label)
          .font({ size: 13 })
          .onSelect((index: number) => {
            this.pTypeIndex = index;
          })
      }
      .width('100%')
      Row({ space: 12 }) {
        Text('通知到')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Select(this.vm.webhooks.map((w: WebhookDestination): SelectOption => ({ value: w.name ?? w.id })))
          .selected(this.vm.webhooks.findIndex((w: WebhookDestination) => w.id === this.pWebhookId))
          .value(this.pWebhookId !== '' ? (this.vm.webhooks.find((w: WebhookDestination) => w.id === this.pWebhookId)?.name ?? '选择 Webhook') : '选择 Webhook')
          .font({ size: 13 })
          .onSelect((index: number) => {
            this.pWebhookId = this.vm.webhooks[index].id;
          })
      }
      .width('100%')
      Button('创建')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(this.pName.trim() !== '' && this.pWebhookId !== '')
        .onClick(() => {
          this.vm.addPolicy(this.pName.trim(), ALERT_TYPES[this.pTypeIndex].id, this.pWebhookId)
            .then((err: string) => {
              if (err === '') {
                this.policySheetVisible = false;
                this.pName = '';
              } else {
                this.toast(err);
              }
            });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  @Builder
  webhookSheet() {
    Column({ space: 12 }) {
      Text('添加 Webhook')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.fName, placeholder: '名称' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fName = value;
        })
      TextInput({ text: this.fUrl, placeholder: 'https://…（可填 Bark / 自建接收端）' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fUrl = value;
        })
      Button('添加')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(this.fName.trim() !== '' && this.fUrl.trim().startsWith('http'))
        .onClick(() => {
          this.vm.addWebhook(this.fName.trim(), this.fUrl.trim()).then((err: string) => {
            if (err === '') {
              this.sheetVisible = false;
              this.fName = '';
              this.fUrl = '';
            } else {
              this.toast(err);
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载告警…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load().catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else {
          Scroll() {
            Column({ space: 4 }) {
              Column() {
                Row() {
                  SectionHeader({ title: `告警策略（${this.vm.policies.length}）· 长按删除` })
                  Blank()
                  Text('＋加策略')
                    .fontSize(13)
                    .fontColor($r('app.color.oc_brand_text'))
                    .padding({ right: 20, top: 16 })
                    .onClick(() => {
                      if (this.vm.webhooks.length === 0) {
                        this.toast('请先添加一个 Webhook 目标');
                        return;
                      }
                      this.pWebhookId = this.vm.webhooks[0].id;
                      this.policySheetVisible = true;
                    })
                }
                .width('100%')

                if (this.vm.policies.length === 0) {
                  Column() {
                    OCEmpty({ symbol: $r('sys.symbol.bell'), title: '暂无告警策略' })
                  }
                  .height(160)
                } else {
                  Column() {
                    ForEach(this.vm.policies, (policy: AlertPolicy) => {
                      Row({ space: 8 }) {
                        Circle({ width: 8, height: 8 })
                          .fill(policy.enabled === true ? '#22C55E' : '#9CA3AF')
                        Column({ space: 2 }) {
                          Text(policy.name ?? policy.id)
                            .fontSize(14)
                            .fontColor($r('sys.color.font_primary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                          Text(policy.alert_type ?? '')
                            .fontSize(11)
                            .fontColor($r('sys.color.font_secondary'))
                        }
                        .alignItems(HorizontalAlign.Start)
                        .layoutWeight(1)
                      }
                      .width('100%')
                      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                      .gesture(LongPressGesture().onAction(() => {
                        this.vm.removePolicy(policy.id).then((err: string) => {
                          this.toast(err === '' ? '已删除' : err);
                        });
                      }))
                    }, (policy: AlertPolicy) => policy.id)
                  }
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(14)
                  .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                  .clip(true)
                  .margin({ left: 16, right: 16 })
                }
              }
              .width('100%')

              Column() {
                Row() {
                  SectionHeader({ title: `Webhook 目标（${this.vm.webhooks.length}）` })
                  Blank()
                  Text('＋加 Webhook')
                    .fontSize(13)
                    .fontColor($r('app.color.oc_brand_text'))
                    .padding({ right: 20, top: 16 })
                    .onClick(() => {
                      this.sheetVisible = true;
                    })
                }
                .width('100%')

                Column() {
                  ForEach(this.vm.webhooks, (webhook: WebhookDestination) => {
                    Column({ space: 2 }) {
                      Text(webhook.name ?? webhook.id)
                        .fontSize(14)
                        .fontColor($r('sys.color.font_primary'))
                        .width('100%')
                      Text(webhook.url ?? '')
                        .fontSize(11)
                        .fontColor($r('sys.color.font_secondary'))
                        .width('100%')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                    .gesture(LongPressGesture().onAction(() => {
                      this.vm.removeWebhook(webhook.id).then((err: string) => {
                        this.toast(err === '' ? '已删除' : err);
                      });
                    }))
                  }, (webhook: WebhookDestination) => webhook.id)
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .clip(true)
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
    .titleBar({ content: { title: { mainTitle: '通知告警' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.sheetVisible, this.webhookSheet(), ocSheet(() => {
      this.sheetVisible = false;
    }))
    .bindSheet(this.policySheetVisible, this.policySheet(), ocSheet(() => {
      this.policySheetVisible = false;
    }))
    .onReady(() => {
      this.vm.load().catch(() => {
      });
    })
  }
}
