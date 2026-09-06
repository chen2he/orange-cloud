// 登录后的主壳：底部 5 Tab（总览/域名/开发/存储/设置），下钻页共用一条 NavPathStack。
// API 23+ 走 HarmonyOS Design 悬浮式材质页签栏（backgroundBlurStyle 材质 + 圆角内缩 + 阴影，
// 内容从浮栏下方穿过）；低版本回退经典底部 Tab 栏（.tabBar + barHeight）。
import { DashboardView } from './dashboard/DashboardView';
import { ZoneListView } from './zones/ZoneListView';
import { DevHubView } from './devhub/DevHubView';
import { StorageHubView } from './storage/StorageHubView';
import { SettingsView } from './settings/SettingsView';
import { BRAND_ORANGE, BRAND_ORANGE_BG } from './common/Components';
import { OCSkyBackground } from './common/OCSky';
import { USE_FLOATING_TABBAR, FLOATING_BAR_HEIGHT, FLOATING_BAR_BOTTOM_INSET, FLOATING_BAR_SIDE_INSET, TABBAR_CONTENT_CLEARANCE, tabBarScroll } from './common/PlatformCompat';
import { WhatsNewGate, WhatsNewItem, WhatsNewStore } from '../core/whatsnew/WhatsNew';
import { WhatsNewSheet, whatsNewSheetOptions } from './whatsnew/WhatsNewSheet';
import { RatingPrompt } from '../core/rating/RatingPrompt';

interface TabSpec {
  symbol: Resource;
  label: string;
}

const TABS: TabSpec[] = [
  { symbol: $r('sys.symbol.line_3_horizontal'), label: '概览' },
  { symbol: $r('sys.symbol.discover'), label: '域名' },
  { symbol: $r('sys.symbol.code_slash'), label: '开发者' },
  { symbol: $r('sys.symbol.archivebox'), label: '存储' },
  { symbol: $r('sys.symbol.gearshape'), label: '设置' },
];

@ComponentV2
export struct MainShell {
  @Require @Param pathStack: NavPathStack;
  @Local currentTab: number = 0;
  /// 「新功能」：登录后评估一次，有未看过的条目才弹（口径见 core/whatsnew/WhatsNew.ets）
  @Local whatsNewItems: WhatsNewItem[] = [];
  @Local whatsNewVisible: boolean = false;
  private controller: TabsController = new TabsController();

  aboutToAppear(): void {
    // MainShell 只在登录后出现 → 挂载即一次「已登录启动」，作为评分邀请的参与度信号
    RatingPrompt.registerEngagedLaunch().catch(() => {
    });
    WhatsNewStore.evaluate().then((items: WhatsNewItem[]) => {
      if (items.length > 0) {
        this.whatsNewItems = items;
        this.whatsNewVisible = true;
        // 同一启动只出一个打扰：评分邀请本次让路
        WhatsNewGate.presentedThisLaunch = true;
      } else {
        this.scheduleRatingPrompt();
      }
    }).catch(() => {
    });
  }

  /// 评分邀请：等主界面稳定后再问，且本次启动没弹过「新功能」才问。
  /// 华为侧自身还有限频，拉不起来时静默——主动邀请不该给用户看错误。
  private scheduleRatingPrompt(): void {
    setTimeout(() => {
      if (WhatsNewGate.presentedThisLaunch) {
        return;
      }
      RatingPrompt.shouldRequest().then((should: boolean) => {
        if (!should) {
          return;
        }
        WhatsNewGate.presentedThisLaunch = true;
        RatingPrompt.markRequested().catch(() => {
        });
        RatingPrompt.request().catch(() => {
        });
      }).catch(() => {
      });
    }, 4000);
  }

  /// 看完「新功能」：写 lastSeen（同一版本不再弹），随后照常评估评分邀请
  private finishWhatsNew(): void {
    this.whatsNewVisible = false;
    WhatsNewStore.markSeen().catch(() => {
    });
  }

  @Builder
  whatsNewContent() {
    WhatsNewSheet({
      items: this.whatsNewItems,
      onContinue: () => {
        this.finishWhatsNew();
      },
    })
  }

  // 经典栏（<23 回退）的单项
  @Builder
  tabBarItem(index: number) {
    Column({ space: 2 }) {
      SymbolGlyph(TABS[index].symbol)
        .fontSize(22)
        .fontColor([this.currentTab === index ? BRAND_ORANGE : $r('sys.color.font_secondary')])
      Text(TABS[index].label)
        .fontSize(10)
        .fontWeight(this.currentTab === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentTab === index ? BRAND_ORANGE : $r('sys.color.font_secondary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  // HarmonyOS Design 悬浮式材质页签栏（API 23+）
  @Builder
  floatingBar() {
    Row() {
      ForEach(TABS, (tab: TabSpec, index: number) => {
        // 外层占权重、居中；内层「胶囊」随内容收缩，选中时染品牌橙底
        Column() {
          Column({ space: 3 }) {
            SymbolGlyph(tab.symbol)
              .fontSize(23)
              .fontColor([this.currentTab === index ? BRAND_ORANGE : $r('sys.color.font_secondary')])
            Text(tab.label)
              .fontSize(10)
              .fontWeight(this.currentTab === index ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.currentTab === index ? BRAND_ORANGE : $r('sys.color.font_secondary'))
          }
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .borderRadius(20)
          .backgroundColor(this.currentTab === index ? BRAND_ORANGE_BG : Color.Transparent)
          .animation({ duration: 200, curve: Curve.EaseOut })
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.currentTab = index;
          this.controller.changeIndex(index);
        })
      }, (tab: TabSpec) => tab.label)
    }
    .height(FLOATING_BAR_HEIGHT)
    .margin({
      left: FLOATING_BAR_SIDE_INSET,
      right: FLOATING_BAR_SIDE_INSET,
      bottom: FLOATING_BAR_BOTTOM_INSET,
    })
    .borderRadius(FLOATING_BAR_HEIGHT / 2)
    // 材质：组件级厚材质，内容从浮栏下方透出（毛玻璃）
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 24, color: '#26000000', offsetY: 8 })
    .clip(true)
    // 动态显隐：下滑平移出屏 + 淡出，上滑/回顶复位
    .translate({ y: tabBarScroll.hidden ? (FLOATING_BAR_HEIGHT + FLOATING_BAR_BOTTOM_INSET + 8) : 0 })
    .opacity(tabBarScroll.hidden ? 0 : 1)
    .animation({ duration: 250, curve: Curve.EaseInOut })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 晨昏天色背景（暖 surface + 双辉光），Tab 内容透明让其透出
      OCSkyBackground()

      Tabs({ barPosition: BarPosition.End, index: this.currentTab, controller: this.controller }) {
        TabContent() {
          DashboardView({ pathStack: this.pathStack })
        }
        .tabBar(this.tabBarItem(0))

        TabContent() {
          ZoneListView({ pathStack: this.pathStack })
        }
        .tabBar(this.tabBarItem(1))

        TabContent() {
          DevHubView({ pathStack: this.pathStack })
        }
        .tabBar(this.tabBarItem(2))

        TabContent() {
          StorageHubView({ pathStack: this.pathStack })
        }
        .tabBar(this.tabBarItem(3))

        TabContent() {
          SettingsView({ pathStack: this.pathStack })
        }
        .tabBar(this.tabBarItem(4))
      }
      .scrollable(false)
      .animationDuration(0)
      // 悬浮模式：隐藏内置栏（barHeight 0）、内容占满、让浮栏叠在其上；经典模式保留内置栏
      .barHeight(USE_FLOATING_TABBAR ? 0 : 56)
      .barBackgroundColor(USE_FLOATING_TABBAR ? Color.Transparent : $r('sys.color.background_secondary'))
      .onChange((index: number) => {
        this.currentTab = index;
        tabBarScroll.reveal();
      })
      // 悬浮模式给内容预留底部净空，让最后一行不被浮栏盖住（浮栏叠在这段留白上）
      .padding({ bottom: TABBAR_CONTENT_CLEARANCE })
      .width('100%')
      .height('100%')

      if (USE_FLOATING_TABBAR) {
        this.floatingBar()
      }
    }
    .width('100%')
    .height('100%')
    // 「新功能」：下拉收起也算看过（onDisappear 里写 lastSeen），不靠按钮保证只弹一次
    .bindSheet(this.whatsNewVisible, this.whatsNewContent(), whatsNewSheetOptions(() => {
      this.whatsNewVisible = false;
      WhatsNewStore.markSeen().catch(() => {
      });
    }))
  }
}
