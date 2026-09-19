import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { OC_SOFT_LIGHT } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 付费墙（对齐 iOS Views/Paywall/PaywallView）：场景触发推入本页，也可从设置页常驻入口进。
// 价格一律取自 queryProducts 的 Product.price，**不硬编码任何价格**；
// 权益清单只写鸿蒙版真正实现了的能力（Live Activity / 系统「文件」挂载等 iOS 专属项不列）。
import { PaywallParam } from '../../models/Routes';
import { entitlement, EntitlementStore, PurchaseOutcome } from '../../core/purchase/EntitlementStore';
import { GlobalContext } from '../../core/system/GlobalContext';
import { BRAND_ORANGE, BRAND_ORANGE_BG } from '../common/Components';
import { OCLayout, RevealBox } from '../common/Daybreak';
import { OCSkyBackground } from '../common/OCSky';

interface Benefit {
  symbol: Resource;
  title: string;
  subtitle: string;
}

const BENEFITS: Benefit[] = [
  { symbol: $r('sys.symbol.person_2'), title: '多账号切换', subtitle: '同时登录多个 Cloudflare 身份，随时切换' },
  { symbol: $r('sys.symbol.externaldrive'), title: '存储模块', subtitle: 'R2 对象存储 / D1 数据库 / KV 键值全功能' },
  { symbol: $r('sys.symbol.dot_radiowaves_left_and_right'), title: 'Workers 实时日志', subtitle: '边缘请求 tail 实时追踪' },
  { symbol: $r('sys.symbol.checkmark_shield'), title: 'WAF 自定义规则', subtitle: '规则查看、启停与新建' },
  { symbol: $r('sys.symbol.wifi_router'), title: 'Cloudflare Tunnel', subtitle: '隧道状态、路由与连接令牌' },
  { symbol: $r('sys.symbol.histogram'), title: '7 天 / 30 天流量分析', subtitle: '免费版为 24 小时窗口' },
];

const PRIVACY_URL = 'https://o-c.do/privacy';
const TERMS_URL = 'https://o-c.do/terms';

@ComponentV2
export struct PaywallPage {
  @Local store: EntitlementStore = entitlement;
  /// 触发闸门的场景名（空 = 从设置页常驻入口进来）
  @Local feature: string = '';

  aboutToAppear(): void {
    // 环境可能在上次启动时不可用（如当时未登录华为账号），进付费墙再试一次
    this.store.bootstrap().then(() => {
      return this.store.loadProducts();
    }).catch(() => {
    });
  }

  private toast(message: string): void {
    ocSnack(this.getUIContext(), message);
  }

  private handleOutcome(outcome: PurchaseOutcome): void {
    if (outcome === 'purchased') {
      this.toast('已解锁 Orange Cloud Pro，感谢支持！');
    } else if (outcome === 'owned') {
      this.toast(this.store.isPro ? '已恢复此前的购买' : '该商品已购买');
    } else if (outcome === 'failed') {
      this.toast(this.store.error !== '' ? this.store.error : '购买失败，请稍后重试');
    }
    // canceled：用户主动取消，不打扰
  }

  private buyYearly(): void {
    this.store.purchaseYearly().then((outcome: PurchaseOutcome) => {
      this.handleOutcome(outcome);
    }).catch(() => {
      this.toast('购买失败，请稍后重试');
    });
  }

  private buyLifetime(): void {
    this.store.purchaseLifetime().then((outcome: PurchaseOutcome) => {
      this.handleOutcome(outcome);
    }).catch(() => {
      this.toast('购买失败，请稍后重试');
    });
  }

  private restore(): void {
    this.store.restore().then((isPro: boolean) => {
      if (isPro) {
        this.toast('已恢复 Pro 权益');
      } else if (this.store.unavailable !== '') {
        this.toast(this.store.unavailable);
      } else if (this.store.error !== '') {
        // 查询本身失败（带错误码），与「确实没买过」区分开
        this.toast(this.store.error);
      } else {
        // 查不到不等于没买过：直接点购买档位，已购买过的商品华为会免费恢复、不重复扣款。
        // 恢复按钮本身不去拉收银台——没买过的人不该看到付款页。
        this.toast('未查询到购买记录。若此前购买过，可直接点上方档位，已购商品不会重复扣款');
      }
    }).catch(() => {
      this.toast('恢复失败，请稍后重试');
    });
  }

  private openLink(target: string): void {
    GlobalContext.get().openLink(target).catch(() => {
    });
  }

  @Builder
  hero() {
    Column({ space: 10 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.cloud'))
          .fontSize(36)
          .fontColor([$r('app.color.oc_brand_text')])
      }
      .width(76)
      .height(76)
      .backgroundColor($r('app.color.oc_brand_bg'))
      .borderRadius(22)

      Text('Orange Cloud Pro')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
      Text(this.subtitleText())
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .lineHeight(21)
        .padding({ left: 24, right: 24 })
    }
    .width('100%')
    .padding({ top: 8, bottom: 4 })
  }

  private subtitleText(): string {
    if (this.store.isPro) {
      return this.store.hasLifetime ? '终身版已解锁，感谢支持' : '订阅生效中，感谢支持';
    }
    if (this.feature !== '') {
      return `「${this.feature}」是 Pro 功能。解锁后本页所列能力全部可用。`;
    }
    return '解锁多账号、存储、实时日志与更长的分析窗口。';
  }

  @Builder
  benefitRow(item: Benefit) {
    Row({ space: 12 }) {
      Stack() {
        SymbolGlyph(item.symbol)
          .fontSize(19)
          .fontColor([$r('app.color.oc_brand_text')])
      }
      .width(36)
      .height(36)
      .backgroundColor($r('app.color.oc_brand_bg'))
      .borderRadius(9)

      Column({ space: 2 }) {
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Text(item.subtitle)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
  }

  /// 购买按钮：主推年度（实心橙），买断为次级（描边）。价格未取到时按钮仍可点，
  /// 由 IAP 收银台展示权威价格。
  @Builder
  purchaseButtons() {
    Column({ space: 10 }) {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Column({ space: 2 }) {
          Text(this.store.yearlyName !== '' ? this.store.yearlyName : 'Pro 年度')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
          Text(this.store.yearlyPrice !== '' ? `${this.store.yearlyPrice} / 年 · 自动续期` : '自动续期订阅')
            .fontSize(12)
            .fontColor('#E6FFFFFF')
        }
        .padding({ top: 10, bottom: 10 })
      }
      .width('100%')
      .backgroundColor($r('app.color.oc_brand_cta'))
      .visualEffect(OC_SOFT_LIGHT)
      .borderRadius(OCLayout.chipRadius)
      .enabled(!this.store.isPurchasing && this.store.unavailable === '')
      .onClick(() => {
        this.buyYearly();
      })

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Column({ space: 2 }) {
          Text(this.store.lifetimeName !== '' ? this.store.lifetimeName : 'Pro 终身')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          Text(this.store.lifetimePrice !== '' ? `${this.store.lifetimePrice} · 一次买断，非订阅` : '一次买断，非订阅')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
        .padding({ top: 10, bottom: 10 })
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .borderRadius(OCLayout.chipRadius)
      .enabled(!this.store.isPurchasing && this.store.unavailable === '')
      .onClick(() => {
        this.buyLifetime();
      })

      if (this.store.isPurchasing) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(BRAND_ORANGE)
          Text('正在处理…')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
      }
      if (this.store.unavailable !== '') {
        Text(this.store.unavailable)
          .fontSize(12)
          .fontColor('#DC2626')
          .textAlign(TextAlign.Center)
          .width('100%')
      }
    }
    .width('100%')
  }

  /// 已解锁：不再展示购买按钮，只留订阅管理与恢复入口
  @Builder
  unlockedPanel() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(18)
          .fontColor([$r('app.color.oc_brand_text')])
        Text(this.store.hasLifetime ? '已持有终身版' : '订阅生效中')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
      }
      if (this.store.hasSubscription) {
        Button('管理订阅')
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .backgroundColor($r('sys.color.comp_background_list_card'))
          .borderRadius(OCLayout.chipRadius)
          .onClick(() => {
            this.store.openManageSubscriptions().catch(() => {
            });
          })
      }
    }
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        Scroll() {
          Column({ space: 18 }) {
            RevealBox({ idx: 0 }) {
              this.hero()
            }

            RevealBox({ idx: 1 }) {
              Column() {
                ForEach(BENEFITS, (item: Benefit, index: number) => {
                  this.benefitRow(item)
                  if (index < BENEFITS.length - 1) {
                    Divider()
                      .strokeWidth(0.5)
                      .color($r('sys.color.comp_divider'))
                      .margin({ left: 62 })
                  }
                }, (item: Benefit) => item.title)
              }
              .width('100%')
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(OCLayout.islandRadius)
              .clip(true)
            }

            RevealBox({ idx: 2 }) {
              if (this.store.isPro) {
                this.unlockedPanel()
              } else {
                this.purchaseButtons()
              }
            }

            RevealBox({ idx: 3 }) {
              Column({ space: 12 }) {
                Button('恢复购买')
                  .width('100%')
                  .height(40)
                  .fontSize(14)
                  .fontColor($r('app.color.oc_brand_text'))
                  .backgroundColor(Color.Transparent)
                  .enabled(!this.store.isRestoring)
                  .onClick(() => {
                    this.restore();
                  })

                Text('订阅按年自动续期，到期前可在「华为账号 → 我的订阅」中随时取消；终身版为一次性买断，不自动续期。免费版始终可用：单账号、域名与 DNS 全功能、24 小时流量分析。')
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
                  .lineHeight(17)
                  .width('100%')

                Row({ space: 16 }) {
                  Text('隐私政策')
                    .fontSize(12)
                    .fontColor($r('app.color.oc_brand_text'))
                    .onClick(() => {
                      this.openLink(PRIVACY_URL);
                    })
                  Text('使用条款')
                    .fontSize(12)
                    .fontColor($r('app.color.oc_brand_text'))
                    .onClick(() => {
                      this.openLink(TERMS_URL);
                    })
                  Blank()
                }
                .width('100%')
              }
              .width('100%')
            }
          }
          .width('100%')
          .padding({
            left: OCLayout.pagePadding,
            right: OCLayout.pagePadding,
            top: 8,
            bottom: 32,
          })
        }
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: 'Orange Cloud Pro' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as PaywallParam | undefined;
      this.feature = param?.feature ?? '';
    })
  }
}
