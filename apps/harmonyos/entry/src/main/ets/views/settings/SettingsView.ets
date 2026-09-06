import { ocSnack } from '../common/Snack';
// 设置 Tab：身份管理（切换/添加/详情）+ 偏好（外观/用量口径）+ 帮助与反馈 + 关于
//（对齐 iOS SettingsView 的分区结构）。
import { ConfigurationConstant, Want } from '@kit.AbilityKit';
import { deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { PaywallParam, Routes } from '../../models/Routes';
import { tabBarScroll } from '../common/PlatformCompat';
import { authManager, AuthSessionMeta } from '../../core/auth/AuthManager';
import { GlobalContext } from '../../core/system/GlobalContext';
import { AppPrefs } from '../../core/system/AppPrefs';
import { BRAND_ORANGE, BRAND_ORANGE_BG, NavRow, SectionHeader, ToggleRow } from '../common/Components';
import { motionPrefs } from '../common/Daybreak';
import { appVersionName } from '../../core/system/AppVersion';
import { RatingPrompt } from '../../core/rating/RatingPrompt';
import { entitlement, EntitlementStore } from '../../core/purchase/EntitlementStore';
import { requirePro } from '../paywall/ProGate';

/// 版本号运行时读取（与「新功能」「评分邀请」的版本门控同源，避免手改常量漏改）
const APP_VERSION: string = appVersionName();
const FEEDBACK_EMAIL = 'support@zhe.ltd';

interface LinkEntry {
  title: string;
  url: string;
}

/// 分段选择器的一个选项（外观 / 日界口径共用）
interface SegOption {
  value: string;
  label: string;
}

const APPEARANCE_OPTIONS: SegOption[] = [
  { value: 'system', label: '跟随系统' },
  { value: 'light', label: '浅色' },
  { value: 'dark', label: '深色' },
];

const DAY_BOUNDARY_OPTIONS: SegOption[] = [
  { value: 'utc', label: 'UTC' },
  { value: 'local', label: '本地时间' },
];

interface ToolEntry {
  symbol: Resource;
  title: string;
  subtitle: string;
  route: string;
}

const ACCOUNT_TOOL_ENTRIES: ToolEntry[] = [
  { symbol: $r('sys.symbol.checkmark_circle'), title: 'Cloudflare 状态', subtitle: '官方服务健康状况', route: Routes.STATUS },
  { symbol: $r('sys.symbol.wrench_and_screwdriver'), title: '工具箱', subtitle: 'whois / DNS / SSL 等 7 件套', route: Routes.TOOLBOX },
  { symbol: $r('sys.symbol.doc_text'), title: '审计日志', subtitle: '账户操作记录', route: Routes.AUDIT },
  { symbol: $r('sys.symbol.bell'), title: '通知告警', subtitle: 'Cloudflare Alerting 策略', route: Routes.ALERTING },
];

const ABOUT_LINKS: LinkEntry[] = [
  { title: '官网', url: 'https://o-c.do' },
  { title: '隐私政策', url: 'https://o-c.do/privacy' },
  { title: '使用条款', url: 'https://o-c.do/terms' },
  { title: 'Telegram 频道', url: 'https://t.me/orange_cloud_channel' },
];

@ComponentV2
export struct SettingsView {
  @Require @Param pathStack: NavPathStack;
  /// 外观模式：'system' | 'light' | 'dark'
  @Local appearanceMode: string = 'system';
  /// 用量「今日」日界口径：'utc' | 'local'
  @Local dayBoundary: string = 'utc';
  /// 减少动画：开启后页面浮现等过渡一步到位
  @Local reduceMotion: boolean = false;
  /// 观察权益：Pro 常驻行的状态与「添加账号」的闸门标记随购买即时联动
  @Local entitlements: EntitlementStore = entitlement;

  aboutToAppear(): void {
    AppPrefs.getAppearanceMode().then((mode: string) => {
      this.appearanceMode = mode;
    }).catch(() => {
    });
    AppPrefs.getDayBoundary().then((value: string) => {
      this.dayBoundary = value;
    }).catch(() => {
    });
    AppPrefs.getReduceMotion().then((on: boolean) => {
      this.reduceMotion = on;
      motionPrefs.reduced = on;
    }).catch(() => {
    });
  }

  /// Pro 常驻行副标题：已解锁说明来源（买断 / 订阅），未解锁给一句卖点
  private proSubtitle(): string {
    if (this.entitlements.hasLifetime) {
      return '终身版 · 感谢支持';
    }
    if (this.entitlements.hasSubscription) {
      return '订阅生效中 · 可在此管理';
    }
    return '多账号 / 存储 / 实时日志 / 长窗口分析';
  }

  /// 手动评分入口：拉起应用市场的应用内评价弹窗。
  /// 与启动时的主动邀请是两条路径，互不影响；华为侧的限频原因这里如实 toast 出来。
  private requestRating(): void {
    RatingPrompt.request().then((err: string) => {
      if (err !== '') {
        ocSnack(this.getUIContext(), err);
      }
    }).catch(() => {
    });
  }

  private openLink(target: string): void {
    GlobalContext.get().openLink(target).catch(() => {
    });
  }

  /// 切换外观：持久化偏好 + ApplicationContext.setColorMode 即时生效（启动时由 EntryAbility 读取应用）
  private applyAppearance(mode: string): void {
    this.appearanceMode = mode;
    AppPrefs.setAppearanceMode(mode).catch(() => {
    });
    try {
      let colorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      if (mode === 'light') {
        colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      } else if (mode === 'dark') {
        colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      }
      GlobalContext.get().getApplicationContext().setColorMode(colorMode);
    } catch (e) {
    }
  }

  private applyDayBoundary(value: string): void {
    this.dayBoundary = value;
    AppPrefs.setDayBoundary(value).catch(() => {
    });
  }

  /// 减少动画：立即作用于全局（各页 RevealBox 读同一个可观察单例）并持久化
  private applyReduceMotion(on: boolean): void {
    this.reduceMotion = on;
    motionPrefs.reduced = on;
    AppPrefs.setReduceMotion(on).catch(() => {
    });
  }

  /// 帮助与反馈：隐式 mailto 拉起邮件客户端（subject 带版本与设备信息），
  /// 无邮件客户端时回退复制邮箱地址到剪贴板 + toast。
  private sendFeedback(): void {
    const device = `${deviceInfo.marketName} · ${deviceInfo.osFullName} · API ${deviceInfo.sdkApiVersion}`;
    const subject = `Orange Cloud HarmonyOS ${APP_VERSION} 反馈（${device}）`;
    const uri = `mailto:${FEEDBACK_EMAIL}?subject=${encodeURIComponent(subject)}`;
    const want: Want = {
      action: 'ohos.want.action.sendToData',
      uri: uri,
    };
    GlobalContext.get().startAbility(want).catch(() => {
      this.copyFeedbackEmail();
    });
  }

  private copyFeedbackEmail(): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, FEEDBACK_EMAIL);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      ocSnack(this.getUIContext(), '未找到邮件应用，已复制邮箱地址');
    }).catch(() => {
    });
  }

  /// 添加第二个身份是 Pro 功能（首个身份走登录页，不经此处，永远免费）
  private addAccount(): void {
    if (authManager.sessions.length >= 1 && !requirePro(this.pathStack, '多账号切换')) {
      return;
    }
    authManager.buildAuthorizeURL().then((authURL: string) => {
      this.pathStack.pushPathByName(Routes.WEB_AUTH, authURL);
    });
  }

  private confirmLogoutAll(): void {
    this.getUIContext().showAlertDialog({
      title: '退出全部账号',
      message: '将撤销所有身份的授权并清除本机 Token。',
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '全部退出',
        fontColor: '#DC2626',
        action: () => {
          authManager.logoutAll().catch(() => {
          });
        },
      },
    });
  }

  @Builder
  identityRow(session: AuthSessionMeta) {
    Row({ space: 12 }) {
      Text(session.label.substring(0, 1).toUpperCase())
        .width(38)
        .height(38)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.oc_brand_text'))
        .textAlign(TextAlign.Center)
        .backgroundColor($r('app.color.oc_brand_bg'))
        .borderRadius(10)
      Column({ space: 2 }) {
        Text(session.label)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(session.id === authManager.currentSessionId ? '当前身份' : '点按切换')
          .fontSize(12)
          .fontColor(session.id === authManager.currentSessionId ? BRAND_ORANGE : $r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('sys.media.ohos_ic_public_arrow_right'))
        .width(16)
        .height(16)
        .fillColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 10, bottom: 10 })
    .onClick(() => {
      if (session.id !== authManager.currentSessionId) {
        authManager.switchSession(session.id).catch(() => {
        });
      } else {
        this.pathStack.pushPathByName(Routes.IDENTITY_DETAIL, session.id);
      }
    })
    .gesture(LongPressGesture().onAction(() => {
      this.pathStack.pushPathByName(Routes.IDENTITY_DETAIL, session.id);
    }))
  }

  /// 分段当前值：**必须由 Builder 内部现读**，不能把选中值当参数传进去——
  /// @Builder 的值参数是静态的，参数变了不会重绘，那样点了分段界面不动（同 PermissionSelectionSheet 已修的 bug）。
  private segSelected(kind: string): string {
    return kind === 'appearance' ? this.appearanceMode : this.dayBoundary;
  }

  /// 分段选择行：左侧图标 + 标题，右侧胶囊分段（选中项橙底白字）
  /// kind 只用于指明这一行读哪个偏好（'appearance' / 'dayBoundary'），本身不随交互变化。
  @Builder
  segRow(symbol: Resource, title: string, options: SegOption[], kind: string, onPick: (value: string) => void) {
    Row({ space: 12 }) {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([$r('app.color.oc_brand_text')])
      Text(title)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
      Blank()
      Row({ space: 4 }) {
        ForEach(options, (opt: SegOption) => {
          Text(opt.label)
            .fontSize(12)
            .fontWeight(this.segSelected(kind) === opt.value ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.segSelected(kind) === opt.value ? $r('app.color.oc_brand_text') : $r('sys.color.font_secondary'))
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor(this.segSelected(kind) === opt.value ? $r('app.color.oc_brand_bg') : Color.Transparent)
            .borderRadius(13)
            .animation({ duration: 150, curve: Curve.EaseOut })
            .onClick(() => {
              onPick(opt.value);
            })
        }, (opt: SegOption) => opt.value)
      }
      .padding(2)
      .backgroundColor($r('app.color.oc_brand_bg'))
      .borderRadius(15)
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 10, bottom: 10 })
  }

  build() {
    Column() {
      Row() {
        Text('设置')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Blank()
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 8 })
      // 大标题上滑收起
      .height(tabBarScroll.hidden ? 0 : 50)
      .opacity(tabBarScroll.hidden ? 0 : 1)
      .clip(true)
      .animation({ duration: 250, curve: Curve.EaseInOut })

      Scroll() {
        Column({ space: 4 }) {
          Column() {
            SectionHeader({ title: '身份（点按切换，长按管理）' })
            Column() {
              ForEach(authManager.sessions, (session: AuthSessionMeta) => {
                this.identityRow(session)
              }, (session: AuthSessionMeta) => session.id)
              NavRow({
                symbol: $r('sys.symbol.plus'),
                title: '添加账号',
                subtitle: '无痕授权登录另一个 Cloudflare 账号',
                locked: authManager.sessions.length >= 1 && !this.entitlements.isPro,
                onNav: () => {
                  this.addAccount();
                },
              })
            }
            .backgroundColor($r('sys.color.comp_background_list_card'))
            .borderRadius(16)
            .clip(true)
            .margin({ left: 16, right: 16 })
          }
          .width('100%')

          Column() {
            SectionHeader({ title: 'Orange Cloud Pro' })
            Column() {
              NavRow({
                symbol: $r('sys.symbol.cloud'),
                title: this.entitlements.isPro ? '已解锁 Pro' : 'Orange Cloud Pro',
                subtitle: this.proSubtitle(),
                onNav: () => {
                  const param: PaywallParam = { feature: '' };
                  this.pathStack.pushPathByName(Routes.PAYWALL, param);
                },
              })
            }
            .backgroundColor($r('sys.color.comp_background_list_card'))
            .borderRadius(16)
            .clip(true)
            .margin({ left: 16, right: 16 })
          }
          .width('100%')

          Column() {
            SectionHeader({ title: '偏好' })
            Column() {
              this.segRow(
                $r('sys.symbol.circle_lefthalf_inset_filled'),
                '外观',
                APPEARANCE_OPTIONS,
                'appearance',
                (value: string) => {
                  this.applyAppearance(value);
                }
              )
              Divider()
                .strokeWidth(0.5)
                .color($r('sys.color.comp_divider'))
                .margin({ left: 48 })
              this.segRow(
                $r('sys.symbol.clock'),
                '「今日」按',
                DAY_BOUNDARY_OPTIONS,
                'dayBoundary',
                (value: string) => {
                  this.applyDayBoundary(value);
                }
              )
              Text('决定用量统计里「今日」从哪个零点起算。选「本地时间」只改 App 的统计窗口，不改变 Cloudflare 免费额度按 UTC 重置的时刻；D1 / KV 受接口按 UTC 天聚合的限制，始终按 UTC 统计。')
                .fontSize(11)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 10 })
              Divider()
                .strokeWidth(0.5)
                .color($r('sys.color.comp_divider'))
                .margin({ left: 48 })
              ToggleRow({
                title: '减少动画',
                subtitle: '页面切换与卡片浮现省去过渡，操作更跟手',
                isOn: this.reduceMotion,
                onToggle: (on: boolean) => {
                  this.applyReduceMotion(on);
                },
              })
            }
            .backgroundColor($r('sys.color.comp_background_list_card'))
            .borderRadius(16)
            .clip(true)
            .margin({ left: 16, right: 16 })
          }
          .width('100%')

          Column() {
            SectionHeader({ title: '工具与记录' })
            Column() {
              ForEach(ACCOUNT_TOOL_ENTRIES, (entry: ToolEntry) => {
                NavRow({
                  symbol: entry.symbol,
                  title: entry.title,
                  subtitle: entry.subtitle,
                  onNav: () => {
                    this.pathStack.pushPathByName(entry.route, null);
                  },
                })
              }, (entry: ToolEntry) => entry.route)
            }
            .backgroundColor($r('sys.color.comp_background_list_card'))
            .borderRadius(16)
            .clip(true)
            .margin({ left: 16, right: 16 })
          }
          .width('100%')

          Column() {
            SectionHeader({ title: '帮助与反馈' })
            Column() {
              NavRow({
                symbol: $r('sys.symbol.envelope'),
                title: '发送反馈',
                subtitle: `邮件联系 ${FEEDBACK_EMAIL}，主题自动附带版本与设备信息`,
                onNav: () => {
                  this.sendFeedback();
                },
              })
            }
            .backgroundColor($r('sys.color.comp_background_list_card'))
            .borderRadius(16)
            .clip(true)
            .margin({ left: 16, right: 16 })
          }
          .width('100%')

          Column() {
            SectionHeader({ title: '关于' })
            Column() {
              NavRow({
                symbol: $r('sys.symbol.star'),
                title: '给 Orange Cloud 评分',
                subtitle: '在应用市场里留一句评价',
                onNav: () => {
                  this.requestRating();
                },
              })
              ForEach(ABOUT_LINKS, (link: LinkEntry) => {
                NavRow({
                  symbol: $r('sys.symbol.link'),
                  title: link.title,
                  subtitle: link.url,
                  onNav: () => {
                    this.openLink(link.url);
                  },
                })
              }, (link: LinkEntry) => link.title)
              Row({ space: 12 }) {
                Text('版本')
                  .fontSize(14)
                  .fontColor($r('sys.color.font_secondary'))
                Blank()
                Text(`${APP_VERSION} (HarmonyOS)`)
                  .fontSize(14)
                  .fontColor($r('sys.color.font_primary'))
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            }
            .backgroundColor($r('sys.color.comp_background_list_card'))
            .borderRadius(16)
            .clip(true)
            .margin({ left: 16, right: 16 })
          }
          .width('100%')

          Button('退出全部账号')
            .width('90%')
            .height(44)
            .fontSize(15)
            .fontColor('#DC2626')
            .backgroundColor($r('sys.color.comp_background_list_card'))
            .margin({ top: 20, bottom: 32 })
            .onClick(() => {
              this.confirmLogoutAll();
            })
        }
        .width('100%')
      }
      .align(Alignment.Top)
      .onDidScroll((dx: number, dy: number) => { tabBarScroll.notifyScroll(dy); })
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
