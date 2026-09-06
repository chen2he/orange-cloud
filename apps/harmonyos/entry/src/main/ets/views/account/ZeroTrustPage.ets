// Zero Trust：Access 应用（建/编辑/删）+ Gateway 规则（建/删），双分区一页（对齐 iOS Views/ZeroTrust）。
import { AccessApp, AccessPolicySummary, GatewayRule } from '../../models/AccountModels';
import { Routes, IdNameParam } from '../../models/Routes';
import { AccountModuleService } from '../../services/AccountModuleService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { formatTimeAgo } from '../../core/util/Format';
import { BRAND_ORANGE, BRAND_ORANGE_BG, InfoRow, OCEmpty, OCError, OCLoading, SectionHeader } from '../common/Components';
import { GlassIsland, OCLayout, SectionTitle } from '../common/Daybreak';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

/// Access 会话时长预设（对齐 iOS AccessSessionDuration）
interface SessionOption {
  label: string;
  value: string;
}

const SESSION_DURATIONS: SessionOption[] = [
  { label: '30 分钟', value: '30m' } as SessionOption,
  { label: '1 小时', value: '1h' } as SessionOption,
  { label: '6 小时', value: '6h' } as SessionOption,
  { label: '24 小时', value: '24h' } as SessionOption,
  { label: '1 周', value: '168h' } as SessionOption,
  { label: '1 个月', value: '730h' } as SessionOption,
];

function sessionIndex(value: string): number {
  for (let i = 0; i < SESSION_DURATIONS.length; i++) {
    if (SESSION_DURATIONS[i].value === value) {
      return i;
    }
  }
  return -1;
}

/// 预设给中文标签，非预设原值（如 12h）原样显示、保存时也原样回写
function sessionLabel(value: string): string {
  const index = sessionIndex(value);
  return index >= 0 ? SESSION_DURATIONS[index].label : value;
}

@ObservedV2
class ZeroTrustVM {
  @Trace apps: AccessApp[] = [];
  @Trace rules: GatewayRule[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  private service: AccountModuleService = new AccountModuleService();

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    const accountId = accountStore.selectedId;
    try {
      try {
        this.apps = await this.service.accessApps(accountId);
      } catch (e) {
        this.apps = [];
      }
      try {
        this.rules = await this.service.gatewayRules(accountId);
      } catch (e) {
        this.rules = [];
      }
      if (this.apps.length === 0 && this.rules.length === 0) {
        // 两个都空可能是无 Zero Trust 组织，给个温和提示而非错误
      }
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async removeApp(appId: string): Promise<string> {
    try {
      await this.service.deleteAccessApp(accountStore.selectedId, appId);
      this.apps = this.apps.filter((a: AccessApp) => a.id !== appId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }

  async addApp(name: string, domain: string, includeType: string, includeValue: string): Promise<string> {
    try {
      const created = await this.service.createAccessApp(accountStore.selectedId, name, domain,
        includeType, includeValue);
      this.apps = this.apps.concat([created]);
      return '';
    } catch (e) {
      return (e as Error).message ?? '创建失败';
    }
  }

  /// 编辑 Access 应用（名称/域名/会话时长；策略与目标由 Service 全量回写保住）
  async editApp(appId: string, name: string, domain: string, sessionDuration: string): Promise<string> {
    try {
      const updated = await this.service.updateAccessApp(accountStore.selectedId, appId, name,
        domain, sessionDuration);
      this.apps = this.apps.map((a: AccessApp) => a.id === appId ? updated : a);
      return '';
    } catch (e) {
      return (e as Error).message ?? '保存失败';
    }
  }

  /// 编辑前取详情（列表条目缺 session_duration 等字段），失败静默返回 null
  async detail(appId: string): Promise<AccessApp | null> {
    try {
      return await this.service.accessApp(accountStore.selectedId, appId);
    } catch (e) {
      return null;
    }
  }

  async removeRule(ruleId: string): Promise<string> {
    try {
      await this.service.deleteGatewayRule(accountStore.selectedId, ruleId);
      this.rules = this.rules.filter((r: GatewayRule) => r.id !== ruleId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }

  async addRule(name: string, action: string, traffic: string): Promise<string> {
    try {
      const created = await this.service.createGatewayRule(accountStore.selectedId, name, action, traffic);
      this.rules = this.rules.concat([created]);
      return '';
    } catch (e) {
      return (e as Error).message ?? '创建失败';
    }
  }
}

const GATEWAY_ACTIONS: string[] = ['block', 'allow', 'safesearch', 'noscan'];

@ComponentV2
export struct ZeroTrustPage {
  @Local vm: ZeroTrustVM = new ZeroTrustVM();
  @Local ruleSheetVisible: boolean = false;
  @Local fName: string = '';
  @Local fActionIndex: number = 0;
  @Local fTraffic: string = '';
  @Local appSheetVisible: boolean = false;
  @Local aName: string = '';
  @Local aDomain: string = '';
  @Local aIncludeEveryone: boolean = true;
  @Local aEmailDomain: string = '';
  // 编辑态（'' = 新建）：复用新建表单 sheet，预填名称/域名/会话时长
  @Local editingAppId: string = '';
  @Local aSession: string = '24h';
  @Local canWriteAccess: boolean = false;
  private pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  private openCreateApp(): void {
    this.editingAppId = '';
    this.aSession = '24h';
    this.appSheetVisible = true;
  }

  private openEditApp(app: AccessApp): void {
    this.editingAppId = app.id;
    this.aName = app.name ?? '';
    this.aDomain = app.domain ?? '';
    this.aSession = app.session_duration ?? '24h';
    this.appSheetVisible = true;
    // 列表条目通常缺 session_duration，取详情异步回填
    this.vm.detail(app.id).then((detail: AccessApp | null) => {
      if (detail !== null && this.editingAppId === app.id && this.appSheetVisible) {
        this.aName = detail.name ?? this.aName;
        this.aDomain = detail.domain ?? this.aDomain;
        this.aSession = detail.session_duration ?? this.aSession;
      }
    });
  }

  private confirmDeleteApp(app: AccessApp): void {
    this.getUIContext().showAlertDialog({
      title: '删除 Access 应用',
      message: `确定删除「${app.name ?? app.domain ?? app.id}」？该应用的访问保护会立即失效。`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.removeApp(app.id).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  private confirmDeleteRule(rule: GatewayRule): void {
    this.getUIContext().showAlertDialog({
      title: '删除 Gateway 规则',
      message: `确定删除「${rule.name ?? rule.id}」？`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.removeRule(rule.id).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  @Builder
  appSheet() {
    Column({ space: 12 }) {
      Text(this.editingAppId !== '' ? '编辑 Access 应用' : '新建 Access 应用')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.aName, placeholder: '应用名称' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.aName = value;
        })
      TextInput({ text: this.aDomain, placeholder: '受保护域名，如 app.example.com' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.aDomain = value;
        })
      if (this.editingAppId !== '') {
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text('会话时长')
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
            Text('通过验证后免重新登录的时间')
              .fontSize(11)
              .fontColor($r('sys.color.font_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Select(SESSION_DURATIONS.map((s: SessionOption): SelectOption => ({ value: s.label })))
            .selected(sessionIndex(this.aSession))
            .value(sessionLabel(this.aSession))
            .font({ size: 14 })
            .onSelect((index: number) => {
              this.aSession = SESSION_DURATIONS[index].value;
            })
        }
        .width('100%')
        Text('访问策略与其余高级配置保持不变')
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      } else {
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text(this.aIncludeEveryone ? '允许所有人' : '限指定邮箱域名')
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
            Text(this.aIncludeEveryone ? '策略 include: everyone' : '策略 include: email_domain')
              .fontSize(11)
              .fontColor($r('sys.color.font_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.aIncludeEveryone })
            .selectedColor('#F48120')
            .onChange((isOn: boolean) => {
              this.aIncludeEveryone = isOn;
            })
        }
        .width('100%')
        if (!this.aIncludeEveryone) {
          TextInput({ text: this.aEmailDomain, placeholder: '邮箱域名，如 example.com' })
            .fontSize(14)
            .width('100%')
            .onChange((value: string) => {
              this.aEmailDomain = value;
            })
        }
      }
      Button(this.editingAppId !== '' ? '保存' : '创建')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor('#F48120')
        .enabled(this.aName.trim() !== '' && this.aDomain.trim() !== '' &&
          (this.editingAppId !== '' || this.aIncludeEveryone || this.aEmailDomain.trim() !== ''))
        .onClick(() => {
          if (this.editingAppId !== '') {
            this.vm.editApp(this.editingAppId, this.aName.trim(), this.aDomain.trim(), this.aSession)
              .then((err: string) => {
                if (err === '') {
                  this.appSheetVisible = false;
                  this.editingAppId = '';
                  this.aName = '';
                  this.aDomain = '';
                  this.toast('已保存');
                } else {
                  this.toast(err);
                }
              });
            return;
          }
          this.vm.addApp(this.aName.trim(), this.aDomain.trim(),
            this.aIncludeEveryone ? 'everyone' : 'email_domain', this.aEmailDomain.trim())
            .then((err: string) => {
              if (err === '') {
                this.appSheetVisible = false;
                this.aName = '';
                this.aDomain = '';
                this.aEmailDomain = '';
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
  ruleSheet() {
    Column({ space: 12 }) {
      Text('新建 Gateway 规则（DNS）')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.fName, placeholder: '规则名称' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fName = value;
        })
      Row({ space: 12 }) {
        Text('动作')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Select(GATEWAY_ACTIONS.map((a: string): SelectOption => ({ value: a })))
          .selected(this.fActionIndex)
          .value(GATEWAY_ACTIONS[this.fActionIndex])
          .font({ size: 14 })
          .onSelect((index: number) => {
            this.fActionIndex = index;
          })
      }
      .width('100%')
      TextArea({ text: this.fTraffic, placeholder: '流量表达式，如 dns.domains[*] == "example.com"' })
        .fontSize(12)
        .height(80)
        .width('100%')
        .onChange((value: string) => {
          this.fTraffic = value;
        })
      Button('创建')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor('#F48120')
        .enabled(this.fName.trim() !== '' && this.fTraffic.trim() !== '')
        .onClick(() => {
          this.vm.addRule(this.fName.trim(), GATEWAY_ACTIONS[this.fActionIndex], this.fTraffic.trim())
            .then((err: string) => {
              if (err === '') {
                this.ruleSheetVisible = false;
                this.fName = '';
                this.fTraffic = '';
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
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载 Zero Trust…' })
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
        } else if (this.vm.apps.length === 0 && this.vm.rules.length === 0) {
          Column({ space: 12 }) {
            Text('🛡️')
              .fontSize(40)
            Text('暂无 Zero Trust 配置')
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
            Text('可新建 Access 应用或 Gateway 规则')
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
            Row({ space: 12 }) {
              Button('＋ Access 应用')
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor('#F48120')
                .onClick(() => {
                  this.openCreateApp();
                })
              Button('＋ Gateway 规则')
                .fontSize(14)
                .fontColor('#F48120')
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .onClick(() => {
                  this.ruleSheetVisible = true;
                })
            }
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 4 }) {
              Column() {
                Row() {
                  SectionHeader({ title: `Access 应用（${this.vm.apps.length}）· 长按删除` })
                  Blank()
                  Text('＋加应用')
                    .fontSize(13)
                    .fontColor('#F48120')
                    .padding({ right: 20, top: 16 })
                    .onClick(() => {
                      this.openCreateApp();
                    })
                }
                .width('100%')

                Column() {
                  ForEach(this.vm.apps, (app: AccessApp) => {
                    Row({ space: 8 }) {
                      Column({ space: 2 }) {
                        Text(app.name ?? app.id)
                          .fontSize(14)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('sys.color.font_primary'))
                          .width('100%')
                        Text(app.domain ?? app.type ?? '')
                          .fontSize(11)
                          .fontColor($r('sys.color.font_secondary'))
                          .width('100%')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)
                      if (this.canWriteAccess) {
                        Text('编辑')
                          .fontSize(12)
                          .fontColor('#F48120')
                          .padding({ left: 8, right: 4, top: 6, bottom: 6 })
                          .onClick(() => {
                            this.openEditApp(app);
                          })
                      }
                    }
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                    .onClick(() => {
                      const param: IdNameParam = { id: app.id, name: app.name ?? app.domain ?? app.id };
                      this.pathStack?.pushPathByName(Routes.ACCESS_APP_DETAIL, param);
                    })
                    .gesture(LongPressGesture().onAction(() => {
                      this.confirmDeleteApp(app);
                    }))
                  }, (app: AccessApp) => app.id)
                }
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .clip(true)
                .margin({ left: 16, right: 16 })
              }
              .width('100%')

              Column() {
                Row() {
                  SectionHeader({ title: `Gateway 规则（${this.vm.rules.length}）· 长按删除` })
                  Blank()
                  Text('＋加规则')
                    .fontSize(13)
                    .fontColor('#F48120')
                    .padding({ right: 20, top: 16 })
                    .onClick(() => {
                      this.ruleSheetVisible = true;
                    })
                }
                .width('100%')

                Column() {
                  ForEach(this.vm.rules, (rule: GatewayRule) => {
                    Row({ space: 8 }) {
                      Text(rule.action ?? '')
                        .fontSize(10)
                        .fontColor('#F48120')
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .backgroundColor('#1AF48120')
                        .borderRadius(4)
                      Column({ space: 2 }) {
                        Text(rule.name ?? rule.id)
                          .fontSize(14)
                          .fontColor($r('sys.color.font_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(rule.enabled === true ? '已启用' : '已停用')
                          .fontSize(11)
                          .fontColor(rule.enabled === true ? '#22C55E' : $r('sys.color.font_tertiary'))
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)
                    }
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                    .gesture(LongPressGesture().onAction(() => {
                      this.confirmDeleteRule(rule);
                    }))
                  }, (rule: GatewayRule) => rule.id)
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
    .title('Zero Trust')
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.ruleSheetVisible, this.ruleSheet(), ocSheet(() => {
      this.ruleSheetVisible = false;
    }))
    .bindSheet(this.appSheetVisible, this.appSheet(), ocSheet(() => {
      this.appSheetVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.canWriteAccess = authManager.hasScope(Scopes.ACCESS_WRITE);
      this.vm.load().catch(() => {
      });
    })
  }
}

// ---------- Access 应用详情 ----------
@ObservedV2
class AccessAppDetailVM {
  @Trace app: AccessApp | null = null;
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  private service: AccountModuleService = new AccountModuleService();

  async load(appId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.app = await this.service.accessApp(accountStore.selectedId, appId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  static typeLabel(type: string | undefined): string {
    switch (type ?? '') {
      case 'self_hosted':
        return '自托管';
      case 'saas':
        return 'SaaS';
      case 'ssh':
        return 'SSH';
      case 'vnc':
        return 'VNC';
      case 'app_launcher':
        return '应用启动台';
      case 'warp':
        return 'WARP';
      case 'bookmark':
        return '书签';
      case 'dash_sso':
        return 'Dash SSO';
      case '':
        return '应用';
      default:
        return type ?? '应用';
    }
  }
}

@ComponentV2
export struct AccessAppDetailPage {
  @Local vm: AccessAppDetailVM = new AccessAppDetailVM();
  @Local appId: string = '';
  @Local appName: string = '';

  /// Hero 卡（对照样板 ZoneDetailPage.heroCard）：Access 图标 + 应用名大字 + 类型徽章·受保护域名
  @Builder
  heroCard() {
    Column({ space: 10 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.lock_shield'))
          .fontSize(26)
          .fontColor([$r('app.color.oc_brand_text')])
      }
      .width(52)
      .height(52)
      .backgroundColor($r('app.color.oc_brand_bg'))
      .borderRadius(14)

      Text(this.vm.app?.name ?? this.appName)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 8 }) {
        Text(AccessAppDetailVM.typeLabel(this.vm.app?.type))
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.oc_brand_text'))
          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .backgroundColor($r('app.color.oc_brand_bg'))
          .borderRadius(20)
        if ((this.vm.app?.domain ?? '') !== '') {
          Text(this.vm.app?.domain ?? '')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
    }
    .width('100%')
    .padding(OCLayout.islandPadding)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(OCLayout.islandRadius)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载应用…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load(this.appId).catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.app !== null) {
          Scroll() {
            Column({ space: 16 }) {
              this.heroCard()

              // 概览
              Column({ space: 8 }) {
                SectionTitle({ title: '概览' })
                GlassIsland({ pad: 0 }) {
                  Column() {
                    InfoRow({ label: '名称', value: this.vm.app!.name ?? this.vm.app!.id })
                    if ((this.vm.app!.domain ?? '') !== '') {
                      InfoRow({ label: '域名', value: this.vm.app!.domain ?? '' })
                    }
                    InfoRow({ label: '类型', value: AccessAppDetailVM.typeLabel(this.vm.app!.type) })
                    if ((this.vm.app!.session_duration ?? '') !== '') {
                      InfoRow({ label: '会话时长', value: this.vm.app!.session_duration ?? '' })
                    }
                    if ((this.vm.app!.aud ?? '') !== '') {
                      InfoRow({ label: 'AUD 标签', value: this.vm.app!.aud ?? '' })
                    }
                  }
                  .width('100%')
                }
              }
              .width('100%')

              // 身份与策略
              Column({ space: 8 }) {
                SectionTitle({ title: '身份与策略' })
                GlassIsland({ pad: 0 }) {
                  Column() {
                    InfoRow({
                      label: '登录后自动跳转 IdP',
                      value: this.vm.app!.auto_redirect_to_identity === true ? '是' : '否',
                    })
                    if ((this.vm.app!.allowed_idps?.length ?? 0) > 0) {
                      InfoRow({
                        label: '允许的 IdP',
                        value: `${this.vm.app!.allowed_idps?.length ?? 0} 个`,
                      })
                    }
                    if ((this.vm.app!.policies?.length ?? 0) > 0) {
                      ForEach(this.vm.app!.policies, (p: AccessPolicySummary, index: number) => {
                        InfoRow({
                          label: p.name ?? `策略 ${index + 1}`,
                          value: p.decision ?? '',
                        })
                      }, (p: AccessPolicySummary, index: number) => `${index}`)
                    } else {
                      Text('无关联策略')
                        .fontSize(14)
                        .fontColor($r('sys.color.font_secondary'))
                        .width('100%')
                        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                    }
                  }
                  .width('100%')
                }
              }
              .width('100%')

              // 时间
              if ((this.vm.app!.created_at ?? '') !== '' || (this.vm.app!.updated_at ?? '') !== '') {
                Column({ space: 8 }) {
                  SectionTitle({ title: '时间' })
                  GlassIsland({ pad: 0 }) {
                    Column() {
                      if ((this.vm.app!.created_at ?? '') !== '') {
                        InfoRow({ label: '创建于', value: formatTimeAgo(this.vm.app!.created_at ?? '') })
                      }
                      if ((this.vm.app!.updated_at ?? '') !== '') {
                        InfoRow({ label: '更新于', value: formatTimeAgo(this.vm.app!.updated_at ?? '') })
                      }
                    }
                    .width('100%')
                  }
                }
                .width('100%')
              }
            }
            .width('100%')
            .padding(OCLayout.pagePadding)
          }
          .scrollBar(BarState.Off)
          .width('100%')
          .height('100%')
          .align(Alignment.Top)
        }
      }
      .width('100%')
      .height('100%')
    }
    .title(this.appName !== '' ? this.appName : 'Access 应用')
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as IdNameParam;
      this.appId = param.id;
      this.appName = param.name;
      this.vm.load(this.appId).catch(() => {
      });
    })
  }
}
