// 登录前权限选择半模态（对齐 iOS PermissionSelectionView）：
// 功能模块勾选 + 每模块只读/读写分段 + 快捷预设 + 底部实时 scope 计数与明细 + 继续授权。
// 只负责挑 scope；offline_access 由 AuthManager.buildAuthorizeURL 咽喉点无条件追加。
import { ScopeModule, Scopes } from '../../core/auth/Scopes';
import { BRAND_ORANGE, BRAND_ORANGE_BG } from '../common/Components';
import { OCLayout } from '../common/Daybreak';

@ComponentV2
export struct PermissionSelectionSheet {
  /// 确认回调：参数为选中的 scope 集（已排序去重，不含 offline_access）
  @Param onConfirm: (scopes: string[]) => void = () => {
  };
  @Param confirmLabel: string = '使用 Cloudflare 账号授权';
  /// 授权流进行中（外部传入，置灰按钮避免连点）
  @Param isWorking: boolean = false;

  /// 启用的非必选模块 id（必选模块恒视为启用，不进此列表）
  @Local enabledIds: string[] = [];
  /// 勾选了「读写」的模块 id
  @Local writeIds: string[] = [];
  @Local showScopeDetail: boolean = false;

  aboutToAppear(): void {
    this.applyAllReadOnly();
  }

  // MARK: - 选择状态

  private isEnabled(module: ScopeModule): boolean {
    return module.required || this.enabledIds.includes(module.id);
  }

  private isWrite(module: ScopeModule): boolean {
    return this.writeIds.includes(module.id);
  }

  private toggleModule(module: ScopeModule): void {
    if (module.required) {
      return;
    }
    if (this.enabledIds.includes(module.id)) {
      this.enabledIds = this.enabledIds.filter((id: string) => id !== module.id);
      // 关闭功能时重置为只读（对齐 iOS toggleFeature）
      this.writeIds = this.writeIds.filter((id: string) => id !== module.id);
    } else {
      this.enabledIds = this.enabledIds.concat([module.id]);
    }
  }

  private setWrite(module: ScopeModule, write: boolean): void {
    if (!this.isEnabled(module) || module.writeScopes.length === 0) {
      return;
    }
    if (write && !this.writeIds.includes(module.id)) {
      this.writeIds = this.writeIds.concat([module.id]);
    } else if (!write && this.writeIds.includes(module.id)) {
      this.writeIds = this.writeIds.filter((id: string) => id !== module.id);
    }
  }

  // MARK: - 快捷预设（对齐 iOS applyAllReadOnly / applyAllReadWrite / applyMinimal）

  private applyAllReadOnly(): void {
    const ids: string[] = [];
    for (const module of Scopes.modules) {
      if (!module.required) {
        ids.push(module.id);
      }
    }
    this.enabledIds = ids;
    this.writeIds = [];
  }

  private applyAllReadWrite(): void {
    const ids: string[] = [];
    const writes: string[] = [];
    for (const module of Scopes.modules) {
      if (!module.required) {
        ids.push(module.id);
      }
      if (module.writeScopes.length > 0) {
        writes.push(module.id);
      }
    }
    this.enabledIds = ids;
    this.writeIds = writes;
  }

  private applyMinimal(): void {
    this.enabledIds = [];
    this.writeIds = [];
  }

  private selectedScopes(): string[] {
    return Scopes.buildSelectedScopes(this.enabledIds, this.writeIds);
  }

  // MARK: - UI

  @Builder
  presetChip(title: string, onTap: () => void) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.oc_brand_text'))
      .textAlign(TextAlign.Center)
      .padding({ top: 9, bottom: 9 })
      .layoutWeight(1)
      .backgroundColor($r('app.color.oc_brand_bg'))
      .borderRadius(10)
      .onClick(() => {
        onTap();
      })
  }

  /// 读写级别分段的一格。**选中态必须在 Builder 内部读 this.writeIds 算**，不能由调用方
  /// 把 active 当参数传进来——@Builder 的值参数是静态的，参数变了不会触发重绘，
  /// 那样点「读写」时状态已改、界面却不动，看起来像按钮点不动（已修的 bug）。
  @Builder
  levelChip(module: ScopeModule, write: boolean) {
    Text(write ? '读写' : '只读')
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.isWrite(module) === write ? $r('app.color.oc_brand_text') : $r('sys.color.font_secondary'))
      .textAlign(TextAlign.Center)
      .padding({ top: 5, bottom: 5 })
      .layoutWeight(1)
      .backgroundColor(this.isWrite(module) === write ? $r('app.color.oc_brand_bg') : Color.Transparent)
      .borderRadius(8)
      .onClick(() => {
        this.setWrite(module, write);
      })
  }

  @Builder
  moduleRow(module: ScopeModule) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Text(module.icon)
          .fontSize(17)
          .width(26)
          .textAlign(TextAlign.Center)
        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text(module.title)
              .fontSize(15)
              .fontColor($r('sys.color.font_primary'))
            if (module.required) {
              Text('必选')
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.oc_brand_text'))
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor($r('app.color.oc_brand_bg'))
                .borderRadius(8)
            }
          }

          Text(module.desc)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.isEnabled(module) })
          .selectedColor($r('app.color.oc_brand'))
          .enabled(!module.required)
          .onChange((isOn: boolean) => {
            if (isOn !== this.isEnabled(module)) {
              this.toggleModule(module);
            }
          })
      }
      .width('100%')

      // 读写级别分段（仅功能开启且支持编辑时显示）
      if (this.isEnabled(module) && module.writeScopes.length > 0) {
        Row({ space: 2 }) {
          this.levelChip(module, false)
          this.levelChip(module, true)
        }
        .width('100%')
        .padding(2)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(10)
        .margin({ left: 36 })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .opacity(this.isEnabled(module) ? 1 : 0.45)
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: OCLayout.islandGap }) {
          // 说明
          Column({ space: 6 }) {
            Text('🔐 选择授权范围')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font_primary'))
            Text('只申请你需要的权限。授权后可在 Cloudflare Dashboard 随时撤销。')
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          // 快捷预设
          Row({ space: 8 }) {
            this.presetChip('全部只读', () => {
              this.applyAllReadOnly();
            })
            this.presetChip('全部读写', () => {
              this.applyAllReadWrite();
            })
            this.presetChip('仅必选', () => {
              this.applyMinimal();
            })
          }
          .width('100%')

          // 功能模块列表
          Column() {
            ForEach(Scopes.modules, (module: ScopeModule, index: number) => {
              this.moduleRow(module)
              if (index < Scopes.modules.length - 1) {
                Divider()
                  .strokeWidth(0.5)
                  .color($r('sys.color.comp_divider'))
                  .margin({ left: 50 })
              }
            }, (module: ScopeModule) => module.id)
          }
          .width('100%')
          .backgroundColor($r('sys.color.comp_background_list_card'))
          .borderRadius(OCLayout.islandRadius)
          .clip(true)

          // scope 计数与展开明细
          Column() {
            Row({ space: 8 }) {
              Text(`已选 ${this.selectedScopes().length} 个权限`)
                .fontSize(13)
                .fontColor($r('sys.color.font_primary'))
              Blank()
              Text(this.showScopeDetail ? '收起 ▲' : '明细 ▼')
                .fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })
            .onClick(() => {
              this.showScopeDetail = !this.showScopeDetail;
            })

            if (this.showScopeDetail) {
              Column({ space: 4 }) {
                ForEach(this.selectedScopes(), (scope: string) => {
                  Text(scope)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_secondary'))
                    .width('100%')
                }, (scope: string) => scope)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: 14, right: 14, bottom: 12 })
            }
          }
          .width('100%')
          .backgroundColor($r('sys.color.comp_background_list_card'))
          .borderRadius(OCLayout.islandRadius)
          .clip(true)
        }
        .width('100%')
        .padding({
          left: OCLayout.pagePadding,
          right: OCLayout.pagePadding,
          top: 8,
          bottom: 16,
        })
      }
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .layoutWeight(1)

      // 底部固定授权按钮
      Column() {
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'))
        Button(this.confirmLabel)
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.oc_brand_cta'))
          .enabled(!this.isWorking)
          .margin({ top: 12 })
          .onClick(() => {
            this.onConfirm(this.selectedScopes());
          })
      }
      .width('100%')
      .padding({
        left: OCLayout.pagePadding,
        right: OCLayout.pagePadding,
        bottom: 12,
      })
    }
    .width('100%')
    .height('100%')
  }
}
