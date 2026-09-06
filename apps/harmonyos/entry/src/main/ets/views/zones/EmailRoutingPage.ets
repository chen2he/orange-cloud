import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 邮件路由：状态开关 + 路由规则（自定义地址 → 转发/丢弃）+ 目标地址管理。
// 对齐 Android EmailRoutingScreen。
import {
  EmailAction,
  EmailDestinationAddress,
  EmailMatcher,
  EmailRoutingRule,
  EmailRoutingService,
  EmailRuleInput, EmailSuppression, suppressionReasonLabel } from '../../services/EmailRoutingService';
import { promptAction } from '@kit.ArkUI';
import { ZoneRouteParam } from '../../models/Routes';
import { accountStore } from '../../core/store/AccountStore';
import { BRAND_ORANGE, OCError, OCLoading, SectionHeader, ToggleRow } from '../common/Components';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

@ObservedV2
class EmailVM {
  @Trace enabled: boolean = false;
  @Trace statusText: string = '';
  @Trace rules: EmailRoutingRule[] = [];
  @Trace addresses: EmailDestinationAddress[] = [];
  // 抑制列表：独立 scope，读不到不连累主加载
  @Trace suppressions: EmailSuppression[] = [];
  @Trace suppressionsAvailable: boolean = false;
  @Trace catchAllRule: EmailRoutingRule | null = null;
  @Trace isLoading: boolean = false;
  @Trace error: string = '';

  private service: EmailRoutingService = new EmailRoutingService();

  /// 解除抑制。成功后本地移除，不必整页重载。
  async removeSuppression(zoneId: string, item: EmailSuppression): Promise<string> {
    try {
      await this.service.deleteSuppression(zoneId, item.id);
      this.suppressions = this.suppressions.filter((x: EmailSuppression) => x.id !== item.id);
      return '';
    } catch (e) {
      return (e as Error).message ?? '解除失败';
    }
  }

  async load(zoneId: string, accountId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      const status = await this.service.status(zoneId);
      this.enabled = status.enabled === true;
      this.statusText = status.status ?? '';
      try {
        this.rules = await this.service.rules(zoneId);
      } catch (e) {
        this.rules = [];
      }
      try {
        this.addresses = await this.service.addresses(accountId);
      } catch (e) {
        this.addresses = [];
      }
      try {
        this.catchAllRule = await this.service.catchAll(zoneId);
      } catch (e) {
        this.catchAllRule = null;
      }
      try {
        this.suppressions = await this.service.suppressions(zoneId);
        this.suppressionsAvailable = true;
      } catch (e) {
        this.suppressionsAvailable = false;
      }
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async setEnabled(zoneId: string, on: boolean): Promise<string> {
    try {
      await this.service.setEnabled(zoneId, on);
      this.enabled = on;
      return '';
    } catch (e) {
      return (e as Error).message ?? '操作失败';
    }
  }

  /// 新建或更新规则（ruleId 空 = 新建）
  async saveRule(zoneId: string, ruleId: string, customAddress: string, forwardTo: string): Promise<string> {
    const matcher: EmailMatcher = { type: 'literal', field: 'to', value: customAddress };
    const action: EmailAction = forwardTo === ''
      ? { type: 'drop' }
      : { type: 'forward', value: [forwardTo] };
    const input: EmailRuleInput = {
      name: `规则 ${customAddress}`,
      enabled: true,
      matchers: [matcher],
      actions: [action],
    };
    try {
      if (ruleId === '') {
        const created = await this.service.createRule(zoneId, input);
        this.rules = this.rules.concat([created]);
      } else {
        const updated = await this.service.updateRule(zoneId, ruleId, input);
        this.rules = this.rules.map((r: EmailRoutingRule) => r.id === ruleId ? updated : r);
      }
      return '';
    } catch (e) {
      return (e as Error).message ?? '保存失败';
    }
  }

  async removeRule(zoneId: string, ruleId: string): Promise<string> {
    try {
      await this.service.deleteRule(zoneId, ruleId);
      this.rules = this.rules.filter((r: EmailRoutingRule) => r.id !== ruleId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }

  /// 仅启停规则（整条 PUT 回写，保留 matchers/actions/name）
  async setRuleEnabled(zoneId: string, rule: EmailRoutingRule, on: boolean): Promise<string> {
    const input: EmailRuleInput = {
      name: rule.name,
      enabled: on,
      matchers: rule.matchers ?? [{ type: 'all' } as EmailMatcher],
      actions: rule.actions ?? [{ type: 'drop' } as EmailAction],
    };
    try {
      const updated = await this.service.updateRule(zoneId, rule.id, input);
      this.rules = this.rules.map((r: EmailRoutingRule) => r.id === rule.id ? updated : r);
      return '';
    } catch (e) {
      return (e as Error).message ?? '操作失败';
    }
  }

  /// catch-all 当前是否为「转发」动作；返回转发目标（丢弃 / 未设置返回 ''）
  get catchAllForwardTo(): string {
    const action = (this.catchAllRule?.actions ?? [])[0];
    if (action !== undefined && action.type === 'forward') {
      return (action.value ?? [''])[0];
    }
    return '';
  }

  /// 构造 catch-all 整条回写体（matcher 固定 type=all）
  private catchAllInput(enabled: boolean, forwardTo: string): EmailRuleInput {
    const action: EmailAction = forwardTo === ''
      ? { type: 'drop' }
      : { type: 'forward', value: [forwardTo] };
    const input: EmailRuleInput = {
      name: this.catchAllRule?.name ?? 'Catch-all 规则',
      enabled: enabled,
      matchers: [{ type: 'all' } as EmailMatcher],
      actions: [action],
    };
    return input;
  }

  /// 启停 catch-all（保留现有动作整条 PUT 回写）
  async setCatchAllEnabled(zoneId: string, on: boolean): Promise<string> {
    try {
      const updated = await this.service.updateCatchAll(zoneId, this.catchAllInput(on, this.catchAllForwardTo));
      this.catchAllRule = updated;
      return '';
    } catch (e) {
      return (e as Error).message ?? '操作失败';
    }
  }

  /// 改 catch-all 动作（forwardTo 空 = 丢弃；保持现有启停状态）
  async setCatchAllAction(zoneId: string, forwardTo: string): Promise<string> {
    const enabled = this.catchAllRule?.enabled === true;
    try {
      const updated = await this.service.updateCatchAll(zoneId, this.catchAllInput(enabled, forwardTo));
      this.catchAllRule = updated;
      return '';
    } catch (e) {
      return (e as Error).message ?? '操作失败';
    }
  }

  /// 已验证的目标地址（verified 为时间戳字符串即视为已验证）
  get verifiedAddresses(): EmailDestinationAddress[] {
    return this.addresses.filter((a: EmailDestinationAddress) =>
      a.verified !== undefined && a.verified !== null && a.verified !== '');
  }

  async addAddress(accountId: string, email: string): Promise<string> {
    try {
      const created = await this.service.createAddress(accountId, email);
      this.addresses = this.addresses.concat([created]);
      return '';
    } catch (e) {
      return (e as Error).message ?? '添加失败';
    }
  }

  async removeAddress(accountId: string, addressId: string): Promise<string> {
    try {
      await this.service.deleteAddress(accountId, addressId);
      this.addresses = this.addresses.filter((a: EmailDestinationAddress) => a.id !== addressId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

function isAddressVerified(address: EmailDestinationAddress): boolean {
  return address.verified !== undefined && address.verified !== null && address.verified !== '';
}

function ruleSummary(rule: EmailRoutingRule): string {
  const matcher = (rule.matchers ?? []).find((m: EmailMatcher) => m.value !== undefined);
  const action = (rule.actions ?? [])[0];
  const from = matcher?.value ?? '（全部）';
  if (action === undefined) {
    return from;
  }
  if (action.type === 'drop') {
    return `${from} → 丢弃`;
  }
  return `${from} → ${(action.value ?? []).join('，')}`;
}

@ComponentV2
export struct EmailRoutingPage {
  @Local vm: EmailVM = new EmailVM();
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local ruleSheetVisible: boolean = false;
  @Local editingRuleId: string = '';
  @Local fCustomLocal: string = '';
  @Local fForwardTo: string = '';
  @Local addressSheetVisible: boolean = false;
  @Local fNewAddress: string = '';

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  private openRuleEditor(rule: EmailRoutingRule | null): void {
    if (rule) {
      this.editingRuleId = rule.id;
      const matcher = (rule.matchers ?? []).find((m: EmailMatcher) => m.value !== undefined);
      const full = matcher?.value ?? '';
      const at = full.indexOf('@');
      this.fCustomLocal = at > 0 ? full.substring(0, at) : full;
      const action = (rule.actions ?? [])[0];
      this.fForwardTo = (action !== undefined && action.type === 'forward') ? (action.value ?? [''])[0] : '';
    } else {
      this.editingRuleId = '';
      this.fCustomLocal = '';
      const verified = this.vm.verifiedAddresses;
      this.fForwardTo = verified.length > 0 ? verified[0].email : '';
    }
    this.ruleSheetVisible = true;
  }

  private confirmDeleteRule(rule: EmailRoutingRule): void {
    this.getUIContext().showAlertDialog({
      title: '删除路由规则',
      message: `确定删除「${ruleSummary(rule)}」？此操作不可撤销。`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.removeRule(this.zoneId, rule.id).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  private confirmDeleteAddress(address: EmailDestinationAddress): void {
    this.getUIContext().showAlertDialog({
      title: '删除目标地址',
      message: `确定删除「${address.email}」？引用它的规则将失效。`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.removeAddress(accountStore.selectedId, address.id).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  @Builder
  addRuleSheet() {
    Column({ space: 12 }) {
      Text(this.editingRuleId === '' ? '新建路由规则' : '编辑路由规则')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })

      Row({ space: 6 }) {
        TextInput({ text: this.fCustomLocal, placeholder: '自定义前缀，如 hello' })
          .fontSize(14)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.fCustomLocal = value;
          })
        Text(`@${this.zoneName}`)
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')

      Row({ space: 12 }) {
        Text('转发到')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Select([{ value: '丢弃' } as SelectOption]
          .concat(this.vm.verifiedAddresses.map((a: EmailDestinationAddress): SelectOption => ({ value: a.email }))))
          .selected(this.fForwardTo === '' ? 0 :
          this.vm.verifiedAddresses.findIndex((a: EmailDestinationAddress) => a.email === this.fForwardTo) + 1)
          .value(this.fForwardTo === '' ? '丢弃' : this.fForwardTo)
          .font({ size: 14 })
          .onSelect((index: number) => {
            this.fForwardTo = index === 0 ? '' : this.vm.verifiedAddresses[index - 1].email;
          })
      }
      .width('100%')

      Button(this.editingRuleId === '' ? '创建' : '保存')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(this.fCustomLocal.trim() !== '')
        .onClick(() => {
          const address = `${this.fCustomLocal.trim()}@${this.zoneName}`;
          this.vm.saveRule(this.zoneId, this.editingRuleId, address, this.fForwardTo).then((err: string) => {
            if (err === '') {
              this.ruleSheetVisible = false;
              this.fCustomLocal = '';
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
  addAddressSheet() {
    Column({ space: 12 }) {
      Text('添加目标地址')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      Text('添加后 Cloudflare 会发验证邮件，验证通过才能作为转发目标。')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ text: this.fNewAddress, placeholder: 'name@example.com' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fNewAddress = value;
        })
      Button('添加')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(this.fNewAddress.trim().includes('@'))
        .onClick(() => {
          this.vm.addAddress(accountStore.selectedId, this.fNewAddress.trim()).then((err: string) => {
            if (err === '') {
              this.addressSheetVisible = false;
              this.fNewAddress = '';
              this.toast('已发送验证邮件');
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
            OCLoading({ text: '正在加载邮件路由…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load(this.zoneId, accountStore.selectedId).catch(() => {
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
                SectionHeader({ title: '状态' })
                Column() {
                  ToggleRow({
                    title: '邮件路由',
                    subtitle: this.vm.statusText !== '' ? `状态：${this.vm.statusText}` : '为该域名启用收件路由',
                    isOn: this.vm.enabled,
                    onToggle: (on: boolean) => {
                      this.vm.setEnabled(this.zoneId, on).then((err: string) => {
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

              if (this.vm.catchAllRule !== null) {
                Column() {
                  SectionHeader({ title: '兜底规则（Catch-All）' })
                  Column() {
                    ToggleRow({
                      title: '接收未命中的邮件',
                      subtitle: this.vm.catchAllForwardTo === ''
                        ? '当前动作：丢弃'
                        : `当前动作：转发到 ${this.vm.catchAllForwardTo}`,
                      isOn: this.vm.catchAllRule?.enabled === true,
                      onToggle: (on: boolean) => {
                        this.vm.setCatchAllEnabled(this.zoneId, on).then((err: string) => {
                          this.toast(err === '' ? (on ? '已启用兜底规则' : '已停用兜底规则') : err);
                        });
                      },
                    })
                    Row({ space: 12 }) {
                      Text('未命中时')
                        .fontSize(14)
                        .fontColor($r('sys.color.font_primary'))
                      Blank()
                      Select([{ value: '丢弃' } as SelectOption]
                        .concat(this.vm.verifiedAddresses.map((a: EmailDestinationAddress): SelectOption =>
                          ({ value: a.email }))))
                        .selected(this.vm.catchAllForwardTo === '' ? 0 :
                        this.vm.verifiedAddresses.findIndex((a: EmailDestinationAddress) =>
                          a.email === this.vm.catchAllForwardTo) + 1)
                        .value(this.vm.catchAllForwardTo === '' ? '丢弃' : this.vm.catchAllForwardTo)
                        .font({ size: 14 })
                        .onSelect((index: number) => {
                          const target = index === 0 ? '' : this.vm.verifiedAddresses[index - 1].email;
                          this.vm.setCatchAllAction(this.zoneId, target).then((err: string) => {
                            this.toast(err === '' ? '已更新兜底动作' : err);
                          });
                        })
                    }
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 8, bottom: 10 })
                  }
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(14)
                  .clip(true)
                  .margin({ left: 16, right: 16 })

                  Text('兜底规则接住所有未被上面路由规则命中的来信；转发目标需为已验证地址。')
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .width('100%')
                    .padding({ left: 20, right: 20, top: 8 })
                }
                .width('100%')
              }

              Column() {
                Row() {
                  SectionHeader({ title: `路由规则（${this.vm.rules.length}）· 点按编辑，长按删除` })
                  Blank()
                  Text('＋加规则')
                    .fontSize(13)
                    .fontColor(this.vm.verifiedAddresses.length > 0 ? BRAND_ORANGE : $r('sys.color.font_tertiary'))
                    .padding({ right: 20, top: 16 })
                    .enabled(this.vm.verifiedAddresses.length > 0)
                    .onClick(() => {
                      if (this.vm.verifiedAddresses.length > 0) {
                        this.openRuleEditor(null);
                      }
                    })
                }
                .width('100%')

                Column() {
                  ForEach(this.vm.rules, (rule: EmailRoutingRule) => {
                    Row({ space: 10 }) {
                      Text('📮')
                        .fontSize(16)
                      Column({ space: 2 }) {
                        Text(ruleSummary(rule))
                          .fontSize(13)
                          .fontColor($r('sys.color.font_primary'))
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(rule.enabled === true ? '已启用' : '已停用')
                          .fontSize(11)
                          .fontColor(rule.enabled === true ? '#22C55E' : $r('sys.color.font_tertiary'))
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)
                      .onClick(() => {
                        this.openRuleEditor(rule);
                      })
                      Toggle({ type: ToggleType.Switch, isOn: rule.enabled === true })
                        .selectedColor($r('app.color.oc_brand'))
                        .onChange((on: boolean) => {
                          if (on !== (rule.enabled === true)) {
                            this.vm.setRuleEnabled(this.zoneId, rule, on).then((err: string) => {
                              this.toast(err);
                            });
                          }
                        })
                    }
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                    .gesture(LongPressGesture().onAction(() => {
                      this.confirmDeleteRule(rule);
                    }))
                  }, (rule: EmailRoutingRule) => rule.id)
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .clip(true)
                .margin({ left: 16, right: 16 })

                if (this.vm.verifiedAddresses.length === 0) {
                  Text('需先添加并验证至少一个目标地址')
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .width('100%')
                    .padding({ left: 20, right: 20, top: 8 })
                }
              }
              .width('100%')

              // 规则决定往哪转，抑制决定不往哪转——
              // 「规则配了却收不到」多半就是命中了这里，所以要能看见
              if (this.vm.suppressionsAvailable) {
                Column() {
                  SectionHeader({ title: `已抑制地址（${this.vm.suppressions.length}）· 长按解除` })
                  Column() {
                    if (this.vm.suppressions.length === 0) {
                      Text('没有被抑制的地址。')
                        .fontSize(13)
                        .fontColor($r('sys.color.font_secondary'))
                        .width('100%')
                        .padding(14)
                    } else {
                      ForEach(this.vm.suppressions, (item: EmailSuppression) => {
                        Column({ space: 2 }) {
                          Text(item.email ?? item.id)
                            .fontSize(14)
                            .fontColor($r('sys.color.font_primary'))
                            .width('100%')
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                          Text(suppressionReasonLabel(item.reason ?? ''))
                            .fontSize(11)
                            .fontColor($r('sys.color.font_secondary'))
                            .width('100%')
                        }
                        .width('100%')
                        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                        .gesture(LongPressGesture().onAction(() => {
                          this.vm.removeSuppression(this.zoneId, item).then((err: string) => {
                            if (err !== '') {
                              ocSnack(this.getUIContext(), err);
                            }
                          });
                        }))
                      }, (item: EmailSuppression) => item.id)
                    }
                  }
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(14)
                  .clip(true)
                  .margin({ left: 16, right: 16 })

                  Text('这些地址退信或投诉过，Cloudflare 已停止向其转发。长按可解除。')
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .padding({ left: 20, right: 20, top: 8 })
                }
                .width('100%')
              }

              Column() {
                Row() {
                  SectionHeader({ title: `目标地址（${this.vm.addresses.length}）· 长按删除` })
                  Blank()
                  Text('＋加地址')
                    .fontSize(13)
                    .fontColor($r('app.color.oc_brand_text'))
                    .padding({ right: 20, top: 16 })
                    .onClick(() => {
                      this.addressSheetVisible = true;
                    })
                }
                .width('100%')

                Column() {
                  ForEach(this.vm.addresses, (address: EmailDestinationAddress) => {
                    Row({ space: 10 }) {
                      Text(address.email)
                        .fontSize(13)
                        .fontColor($r('sys.color.font_primary'))
                        .layoutWeight(1)
                      Text(isAddressVerified(address) ? '已验证' : '待验证')
                        .fontSize(11)
                        .fontColor(isAddressVerified(address) ? '#22C55E' : '#EAB308')
                    }
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                    .gesture(LongPressGesture().onAction(() => {
                      this.confirmDeleteAddress(address);
                    }))
                  }, (address: EmailDestinationAddress) => address.id)
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
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
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: `${this.zoneName} · 邮件路由` } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.ruleSheetVisible, this.addRuleSheet(), ocSheet(() => {
      this.ruleSheetVisible = false;
    }))
    .bindSheet(this.addressSheetVisible, this.addAddressSheet(), ocSheet(() => {
      this.addressSheetVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      this.vm.load(param.zoneId, accountStore.selectedId).catch(() => {
      });
    })
  }
}
