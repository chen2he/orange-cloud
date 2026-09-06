// 域名 Tab（对照 iOS ZoneListView）：大标题「域名」+ 副标题统计 + 搜索 +
// 每个域名一张独立玻璃岛卡片（字母头像 + 名字 + 套餐徽章 + 状态点 + chevron）。
import { Zone, zoneDisplayStatus } from '../../models/Models';
import { tabBarScroll } from '../common/PlatformCompat';
import { Routes, ZoneRouteParam } from '../../models/Routes';
import { AccountStore, accountStore } from '../../core/store/AccountStore';
import { ZoneListViewModel } from '../../viewmodels/ZoneListViewModel';
import { BRAND_ORANGE, OCEmpty, OCError, OCLoading } from '../common/Components';
import { ZoneAvatar, PlanBadge, StatusDot } from '../common/ZoneComponents';
import { OCLayout, RevealBox } from '../common/Daybreak';
import { ocSheet } from '../common/Sheets';
import { pasteboard } from '@kit.BasicServicesKit';
import { pinnedZones, PinnedZonesStore } from '../../core/system/AppPrefs';

@ComponentV2
export struct ZoneListView {
  @Require @Param pathStack: NavPathStack;
  @Local vm: ZoneListViewModel = new ZoneListViewModel();
  @Local store: AccountStore = accountStore;
  @Local pins: PinnedZonesStore = pinnedZones;
  @Local showAddSheet: boolean = false;
  /// 添加成功后的 NS 结果引导（对齐 iOS AddZoneView 的完成页）
  @Local showNsResult: boolean = false;
  @Local newZoneName: string = '';
  @Local refreshing: boolean = false;

  aboutToAppear(): void {
    accountStore.loadIfNeeded().then(() => {
      pinnedZones.loadFor(accountStore.selectedId).catch(() => {
      });
      this.vm.load(accountStore.selectedId).catch(() => {
      });
    }).catch(() => {
    });
  }

  @Monitor('store.selectedId')
  onAccountChange(): void {
    pinnedZones.loadFor(this.store.selectedId).catch(() => {
    });
    this.vm.load(this.store.selectedId, true).catch(() => {
    });
  }

  // 注：不能叫 activeCount——@ComponentV2 保留名，编译警告
  private enabledZoneCount(): number {
    return this.vm.zones.filter((z: Zone) => zoneDisplayStatus(z) === 'active').length;
  }

  @Builder
  zoneCard(zone: Zone) {
    Row({ space: 12 }) {
      ZoneAvatar({ domain: zone.name, dim: 36 })

      Column({ space: 3 }) {
        Row({ space: 8 }) {
          Text(zone.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.pins.isPinned(zone.id)) {
            // 已固定到首页的小图钉标识
            SymbolGlyph($r('sys.symbol.pin_fill'))
              .fontSize(11)
              .fontColor([$r('app.color.oc_brand_text')])
          }
          if (zone.plan?.name) {
            PlanBadge({ planName: zone.plan!.name! })
          }
        }
        Text(this.store.selectedName)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      StatusDot({ status: zoneDisplayStatus(zone) })
      Image($r('sys.media.ohos_ic_public_arrow_right'))
        .width(14)
        .height(14)
        .fillColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .padding(OCLayout.islandPadding)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(OCLayout.islandRadius)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
    .onClick(() => {
      const param: ZoneRouteParam = { zoneId: zone.id, zoneName: zone.name };
      this.pathStack.pushPathByName(Routes.ZONE_DETAIL, param);
    })
  }

  private copyText(text: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.getUIContext().getPromptAction().showToast({ message: '已复制' });
    }).catch(() => {
    });
  }

  /// 添加成功后的 NS 结果页：域名要激活，得先去注册商把 NS 改成这两条（对齐 iOS AddZoneView 完成页）
  @Builder
  nsResultSheet() {
    Column({ space: 14 }) {
      Text('域名已添加')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      Text(`${this.vm.createdZoneName} 处于「待激活」。登录你的域名注册商，把名称服务器改成下面两条，Cloudflare 检测到后会自动激活（通常几分钟到 24 小时）。`)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      Column() {
        ForEach(this.vm.createdNameServers, (server: string, index: number) => {
          Row({ space: 10 }) {
            Text(server)
              .fontSize(13)
              .fontFamily('monospace')
              .fontColor($r('sys.color.font_primary'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('复制')
              .fontSize(12)
              .fontColor($r('app.color.oc_brand_text'))
              .onClick(() => {
                this.copyText(server);
              })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 11, bottom: 11 })
          if (index < this.vm.createdNameServers.length - 1) {
            Divider()
              .strokeWidth(0.5)
              .color($r('sys.color.comp_divider'))
              .margin({ left: 14 })
          }
        }, (server: string) => server)
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .borderRadius(OCLayout.chipRadius)
      .border({ width: 0.5, color: $r('sys.color.comp_divider') })
      .clip(true)

      Button('复制两条 NS')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor($r('app.color.oc_brand_text'))
        .backgroundColor($r('sys.color.comp_background_list_card'))
        .borderRadius(OCLayout.chipRadius)
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })
        .onClick(() => {
          this.copyText(this.vm.createdNameServers.join('\n'));
        })

      Button('完成')
        .width('100%')
        .height(46)
        .fontSize(16)
        .fontColor(Color.White)
        .backgroundColor(BRAND_ORANGE)
        .onClick(() => {
          this.showNsResult = false;
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  @Builder
  addZoneSheet() {
    Column({ space: 14 }) {
      Text('添加域名')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      Text(`将添加到账户「${this.store.selectedName}」，完成后需在注册商把 NS 指向 Cloudflare。`)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ text: this.newZoneName, placeholder: '例如 example.com' })
        .fontSize(15)
        .width('100%')
        .onChange((value: string) => {
          this.newZoneName = value;
        })
      if (this.vm.createError !== '') {
        Text(this.vm.createError)
          .fontSize(13)
          .fontColor('#DC2626')
          .width('100%')
      }
      Button(this.vm.isCreating ? '正在添加…' : '添加')
        .width('100%')
        .height(46)
        .fontSize(16)
        .fontColor(Color.White)
        .backgroundColor(BRAND_ORANGE)
        .enabled(!this.vm.isCreating && this.newZoneName.trim().includes('.'))
        .onClick(() => {
          this.vm.create(this.store.selectedId, this.newZoneName.trim()).then((ok: boolean) => {
            if (ok) {
              this.showAddSheet = false;
              this.newZoneName = '';
              // 分配到 NS 才值得弹结果页；接口没返回时静默（详情页仍可查看）
              if (this.vm.createdNameServers.length > 0) {
                this.showNsResult = true;
              }
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // 大标题 + 副标题（对照 iOS navigationTitle + oc-subtitle）
        Column({ space: 2 }) {
          Text('域名')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
          if (this.vm.zones.length > 0) {
            Text(`${this.vm.zones.length} 个域名 · ${this.enabledZoneCount()} 个已启用`)
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: OCLayout.pagePadding, right: OCLayout.pagePadding, top: 8, bottom: 8 })
        // 大标题上滑收起（保留下方搜索框）
        .height(tabBarScroll.hidden ? 0 : 72)
        .opacity(tabBarScroll.hidden ? 0 : 1)
        .clip(true)
        .animation({ duration: 250, curve: Curve.EaseInOut })

        Search({ placeholder: '搜索域名', value: this.vm.keyword })
          .width('92%')
          .backgroundColor($r('sys.color.comp_background_list_card'))
          .onChange((value: string) => {
            this.vm.keyword = value;
          })

        if (this.vm.isLoading && this.vm.zones.length === 0) {
          OCLoading({ text: '正在加载域名…' })
        } else if (this.vm.error !== '') {
          OCError({
            message: this.vm.error,
            onRetry: () => {
              this.vm.load(this.store.selectedId, true).catch(() => {
              });
            },
          })
        } else if (this.vm.filtered().length === 0) {
          OCEmpty({
            symbol: $r('sys.symbol.discover'),
            title: this.vm.keyword === '' ? '暂无域名' : '没有匹配的域名',
            subtitle: this.vm.keyword === '' ? '点右下角 + 添加第一个域名' : '',
          })
        } else {
          Refresh({ refreshing: this.refreshing }) {
            Scroll() {
              Column({ space: OCLayout.islandGap }) {
                // 前 8 张错峰浮现，之后的档位封顶（长列表尾部不再叠加延迟）
                ForEach(this.vm.filtered(), (zone: Zone, index: number) => {
                  RevealBox({ idx: Math.min(index, 7) }) {
                    this.zoneCard(zone)
                  }
                }, (zone: Zone) => zone.id)
              }
              .width('100%')
              .padding(OCLayout.pagePadding)
            }
            .align(Alignment.Top)
            .onDidScroll((dx: number, dy: number) => { tabBarScroll.notifyScroll(dy); })
            .scrollBar(BarState.Off)
            .width('100%')
            .height('100%')
          }
          .onRefreshing(() => {
            // 手势回调只置状态，加载在 VM 的独立异步链路完成后收尾
            this.refreshing = true;
            this.vm.load(this.store.selectedId, true).then(() => {
              this.refreshing = false;
            }).catch(() => {
              this.refreshing = false;
            });
          })
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')

      Button('+')
        .width(52)
        .height(52)
        .fontSize(26)
        .fontColor(Color.White)
        .backgroundColor(BRAND_ORANGE)
        .borderRadius(26)
        .shadow({ radius: 12, color: '#40000000', offsetY: 4 })
        .margin({ right: 20, bottom: 28 })
        .onClick(() => {
          this.vm.createError = '';
          this.showAddSheet = true;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .bindSheet(this.showNsResult, this.nsResultSheet(), ocSheet(() => {
      this.showNsResult = false;
    }))
    .bindSheet(this.showAddSheet, this.addZoneSheet(), ocSheet(() => {
      this.showAddSheet = false;
    }))
  }
}
