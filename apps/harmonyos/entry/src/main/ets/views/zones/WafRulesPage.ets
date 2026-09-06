// WAF 自定义规则（Rulesets http_request_firewall_custom）：列表 / 启停 / 新建 / 编辑 / 删除。
// 对齐 Android WafRulesScreen（AI 表达式生成为安卓云端能力，此处提供表达式直编）。
import { RulesetPhases, RulesetRule, RulesetRuleCreate } from '../../models/RulesetModels';
import { ZoneRouteParam } from '../../models/Routes';
import { RulesetVM } from '../../services/RulesetService';
import { BRAND_ORANGE, OCEmpty, OCError, OCLoading } from '../common/Components';
import { RuleRow, actionLabel } from './RuleComponents';
import { ExpressionBuilder } from './ExpressionBuilder';
import { lintExpression } from '../../models/RuleExpressionBuilder';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

const WAF_ACTIONS: string[] = ['block', 'managed_challenge', 'js_challenge', 'challenge', 'log'];

@ComponentV2
export struct WafRulesPage {
  @Local vm: RulesetVM = new RulesetVM(RulesetPhases.WAF_CUSTOM);
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local editorVisible: boolean = false;
  @Local editingId: string = '';
  @Local fDescription: string = '';
  @Local fExpression: string = '';
  @Local fAction: string = 'block';
  @Local fEnabled: boolean = true;

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  private rules(): RulesetRule[] {
    return this.vm.ruleset?.rules ?? [];
  }

  private openEditor(rule: RulesetRule | null): void {
    this.vm.saveError = '';
    if (rule) {
      this.editingId = rule.id;
      this.fDescription = rule.description ?? '';
      this.fExpression = rule.expression ?? '';
      this.fAction = rule.action ?? 'block';
      this.fEnabled = rule.enabled === true;
    } else {
      this.editingId = '';
      this.fDescription = '';
      this.fExpression = '';
      this.fAction = 'block';
      this.fEnabled = true;
    }
    this.editorVisible = true;
  }

  private submit(): void {
    const lint: string = lintExpression(this.fExpression.trim());
    if (lint !== '') {
      this.toast(lint);
      return;
    }
    const rule: RulesetRuleCreate = {
      action: this.fAction,
      expression: this.fExpression.trim(),
      description: this.fDescription.trim(),
      enabled: this.fEnabled,
    };
    this.vm.save(this.zoneId, this.editingId, rule).then((ok: boolean) => {
      if (ok) {
        this.editorVisible = false;
      }
    });
  }

  private confirmDelete(rule: RulesetRule): void {
    this.getUIContext().showAlertDialog({
      title: '删除规则',
      message: `确定删除「${rule.description ?? rule.id}」？`,
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
  editorSheet() {
    Column({ space: 12 }) {
      Text(this.editingId === '' ? '新建 WAF 规则' : '编辑 WAF 规则')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })

      TextInput({ text: this.fDescription, placeholder: '规则描述' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fDescription = value;
        })

      ExpressionBuilder({
        expression: this.fExpression,
        onChange: (e: string) => {
          this.fExpression = e;
        },
      })

      Row({ space: 12 }) {
        Text('动作')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Select(WAF_ACTIONS.map((a: string): SelectOption => ({ value: actionLabel(a) })))
          .selected(WAF_ACTIONS.indexOf(this.fAction))
          .value(actionLabel(this.fAction))
          .font({ size: 14 })
          .onSelect((index: number) => {
            this.fAction = WAF_ACTIONS[index];
          })
      }
      .width('100%')

      Row({ space: 12 }) {
        Text('启用')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.fEnabled })
          .selectedColor($r('app.color.oc_brand'))
          .onChange((isOn: boolean) => {
            this.fEnabled = isOn;
          })
      }
      .width('100%')

      if (this.vm.saveError !== '') {
        Text(this.vm.saveError)
          .fontSize(13)
          .fontColor('#DC2626')
          .width('100%')
      }

      Button(this.vm.isSaving ? '正在保存…' : (this.editingId === '' ? '创建' : '保存'))
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isSaving && this.fExpression.trim() !== '')
        .onClick(() => {
          this.submit();
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载 WAF 规则…' })
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
        } else if (this.rules().length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.checkmark_shield'), title: '暂无自定义规则', subtitle: '点右下角 + 创建第一条规则' })
          }
          .width('100%')
          .height('100%')
        } else {
          List() {
            ForEach(this.rules(), (rule: RulesetRule) => {
              ListItem() {
                RuleRow({
                  rule: rule,
                  busy: this.vm.isSaving,
                  onEdit: () => {
                    this.openEditor(rule);
                  },
                  onToggle: (enabled: boolean) => {
                    this.vm.toggle(this.zoneId, rule.id, enabled).then((err: string) => {
                      this.toast(err);
                    });
                  },
                  onDelete: () => {
                    this.confirmDelete(rule);
                  },
                })
              }
            }, (rule: RulesetRule) => rule.id)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
        }

        Button('+')
          .width(52)
          .height(52)
          .fontSize(26)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.oc_brand_cta'))
          .borderRadius(26)
          .shadow({ radius: 12, color: '#40000000', offsetY: 4 })
          .margin({ right: 20, bottom: 28 })
          .onClick(() => {
            this.openEditor(null);
          })
      }
      .width('100%')
      .height('100%')
    }
    .title(`${this.zoneName} · WAF`)
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.editorVisible, this.editorSheet(), ocSheet(() => {
      this.editorVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      this.vm.load(param.zoneId).catch(() => {
      });
    })
  }
}
