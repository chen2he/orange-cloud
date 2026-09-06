// Page Rules（传统）：列表 + 启停（PATCH status）+ 长按删除，不做新建编辑（与 iOS 一致）。
// Cloudflare 建议迁移到新的规则产品，已有规则在此查看维护。
import { PageRule } from '../../models/RulesetModels';
import { ZoneRouteParam } from '../../models/Routes';
import { RulesetService } from '../../services/RulesetService';
import { authManager } from '../../core/auth/AuthManager';
import { BRAND_ORANGE, OCEmpty, OCError, OCLoading } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';

const PAGE_RULES_WRITE_SCOPE = 'page-rules.write';

function targetLabel(rule: PageRule): string {
  const targets = rule.targets ?? [];
  if (targets.length > 0) {
    const value = targets[0].constraint?.value;
    if (value !== undefined && value !== '') {
      return value;
    }
  }
  return rule.id;
}

function actionsLabel(rule: PageRule): string {
  const names: string[] = [];
  for (const action of rule.actions ?? []) {
    names.push(action.id);
  }
  return names.length === 0 ? '无动作' : names.join(' · ');
}

@ObservedV2
class PageRulesVM {
  @Trace rules: PageRule[] = [];
  @Trace isLoading: boolean = false;
  @Trace isMutating: boolean = false;
  @Trace error: string = '';

  private service: RulesetService = new RulesetService();

  async load(zoneId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.rules = await this.service.listPageRules(zoneId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async setActive(zoneId: string, ruleId: string, active: boolean): Promise<string> {
    this.isMutating = true;
    try {
      const updated = await this.service.setPageRuleStatus(zoneId, ruleId, active);
      this.rules = this.rules.map((rule: PageRule) => rule.id === ruleId ? updated : rule);
      return '';
    } catch (e) {
      return (e as Error).message ?? '操作失败';
    } finally {
      this.isMutating = false;
    }
  }

  async remove(zoneId: string, ruleId: string): Promise<string> {
    this.isMutating = true;
    try {
      await this.service.deletePageRule(zoneId, ruleId);
      this.rules = this.rules.filter((rule: PageRule) => rule.id !== ruleId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    } finally {
      this.isMutating = false;
    }
  }
}

@ComponentV2
export struct PageRulesPage {
  @Local vm: PageRulesVM = new PageRulesVM();
  @Local zoneId: string = '';
  @Local zoneName: string = '';

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  private guardWrite(): boolean {
    if (!authManager.hasScope(PAGE_RULES_WRITE_SCOPE)) {
      this.toast(`当前授权未包含编辑权限（${PAGE_RULES_WRITE_SCOPE}）`);
      return false;
    }
    return true;
  }

  private confirmDelete(rule: PageRule): void {
    this.getUIContext().showAlertDialog({
      title: '删除 Page Rule',
      message: `确定删除「${targetLabel(rule)}」？此操作不可撤销，规则将立即停止生效。`,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.remove(this.zoneId, rule.id).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  @Builder
  ruleRow(rule: PageRule) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(targetLabel(rule))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .fontFamily('monospace')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(actionsLabel(rule))
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: rule.status === 'active' })
        .selectedColor(BRAND_ORANGE)
        .enabled(!this.vm.isMutating)
        .onChange((isOn: boolean) => {
          if (isOn === (rule.status === 'active')) {
            return;
          }
          if (!this.guardWrite()) {
            this.vm.load(this.zoneId).catch(() => {
            });
            return;
          }
          this.vm.setActive(this.zoneId, rule.id, isOn).then((err: string) => {
            this.toast(err);
          });
        })
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(16)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 10, color: '#12000000', offsetY: 4 })
    .margin({ left: 16, right: 16, top: 5, bottom: 5 })
    .opacity(rule.status === 'active' ? 1 : 0.55)
    .gesture(LongPressGesture().onAction(() => {
      if (!this.guardWrite()) {
        return;
      }
      this.confirmDelete(rule);
    }))
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载 Page Rules…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load(this.zoneId).catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.rules.length === 0) {
          Column() {
            OCEmpty({
              symbol: $r('sys.symbol.doc_text'),
              title: '没有 Page Rules',
              subtitle: 'Page Rules 是传统功能，Cloudflare 建议迁移到新的规则产品',
            })
          }
          .width('100%')
          .height('100%')
        } else {
          List() {
            ForEach(this.vm.rules, (rule: PageRule) => {
              ListItem() {
                this.ruleRow(rule)
              }
            }, (rule: PageRule) => rule.id)

            ListItem() {
              Text('传统功能仅支持查看、启停与删除；开关启停，长按删除。')
                .fontSize(11)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
                .padding({ left: 20, right: 20, top: 8, bottom: 16 })
            }
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
    }
    .title(`${this.zoneName} · Page Rules`)
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      this.vm.load(param.zoneId).catch(() => {
      });
    })
  }
}
