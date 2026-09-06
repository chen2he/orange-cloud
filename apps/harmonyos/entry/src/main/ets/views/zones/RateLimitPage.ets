// 速率限制（Rulesets http_ratelimit）：列表 / 启停 / 新建 / 编辑 / 删除。
// 计数特征固定 ip.src + cf.colo.id（免费套餐可用组合，对齐 Android ZoneRateLimitScreen）。
import { RateLimitConfig, RulesetPhases, RulesetRule, RulesetRuleCreate } from '../../models/RulesetModels';
import { ZoneRouteParam } from '../../models/Routes';
import { RulesetVM } from '../../services/RulesetService';
import { BRAND_ORANGE, OCEmpty, OCError, OCLoading } from '../common/Components';
import { RuleRow } from './RuleComponents';
import { ExpressionBuilder } from './ExpressionBuilder';
import { lintExpression } from '../../models/RuleExpressionBuilder';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

const PERIOD_OPTIONS: number[] = [10, 60, 120, 300, 600];

function periodLabel(seconds: number): string {
  if (seconds < 60) {
    return `${seconds} 秒`;
  }
  return `${seconds / 60} 分钟`;
}

@ComponentV2
export struct RateLimitPage {
  @Local vm: RulesetVM = new RulesetVM(RulesetPhases.RATE_LIMIT);
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local editorVisible: boolean = false;
  @Local editingId: string = '';
  @Local fDescription: string = '';
  @Local fExpression: string = '';
  @Local fPeriod: number = 60;
  @Local fRequests: string = '100';
  @Local fTimeout: number = 60;

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
      this.fPeriod = rule.ratelimit?.period ?? 60;
      this.fRequests = `${rule.ratelimit?.requests_per_period ?? 100}`;
      this.fTimeout = rule.ratelimit?.mitigation_timeout ?? 60;
    } else {
      this.editingId = '';
      this.fDescription = '';
      this.fExpression = 'true';
      this.fPeriod = 60;
      this.fRequests = '100';
      this.fTimeout = 60;
    }
    this.editorVisible = true;
  }

  private submit(): void {
    const lint: string = lintExpression(this.fExpression.trim());
    if (lint !== '') {
      this.toast(lint);
      return;
    }
    const requests = Number.parseInt(this.fRequests.trim());
    const config: RateLimitConfig = {
      characteristics: ['cf.colo.id', 'ip.src'],
      period: this.fPeriod,
      requests_per_period: Number.isNaN(requests) ? 100 : requests,
      mitigation_timeout: this.fTimeout,
    };
    const rule: RulesetRuleCreate = {
      action: 'block',
      expression: this.fExpression.trim(),
      description: this.fDescription.trim(),
      enabled: true,
      ratelimit: config,
    };
    this.vm.save(this.zoneId, this.editingId, rule).then((ok: boolean) => {
      if (ok) {
        this.editorVisible = false;
      }
    });
  }

  private confirmDelete(rule: RulesetRule): void {
    this.getUIContext().showAlertDialog({
      title: '删除速率限制规则',
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
  numberSelect(label: string, current: number, onPick: (value: number) => void) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
      Blank()
      Select(PERIOD_OPTIONS.map((v: number): SelectOption => ({ value: periodLabel(v) })))
        .selected(PERIOD_OPTIONS.indexOf(current))
        .value(periodLabel(current))
        .font({ size: 14 })
        .onSelect((index: number) => {
          onPick(PERIOD_OPTIONS[index]);
        })
    }
    .width('100%')
  }

  @Builder
  editorSheet() {
    Column({ space: 12 }) {
      Text(this.editingId === '' ? '新建速率限制' : '编辑速率限制')
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

      TextInput({ text: this.fRequests, placeholder: '周期内允许请求数' })
        .type(InputType.Number)
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fRequests = value;
        })

      this.numberSelect('统计周期', this.fPeriod, (value: number) => {
        this.fPeriod = value;
      })
      this.numberSelect('拦截时长', this.fTimeout, (value: number) => {
        this.fTimeout = value;
      })

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
        .enabled(!this.vm.isSaving && this.fExpression.trim() !== '' && this.fRequests.trim() !== '')
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
            OCLoading({ text: '正在加载速率限制…' })
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
            OCEmpty({ symbol: $r('sys.symbol.timer'), title: '暂无速率限制规则', subtitle: '点右下角 + 创建第一条规则' })
          }
          .width('100%')
          .height('100%')
        } else {
          List() {
            ForEach(this.rules(), (rule: RulesetRule) => {
              ListItem() {
                Column({ space: 2 }) {
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
                  if (rule.ratelimit) {
                    Text(`${rule.ratelimit.requests_per_period ?? '-'} 次 / ${periodLabel(rule.ratelimit.period ?? 60)}，拦 ${periodLabel(rule.ratelimit.mitigation_timeout ?? 60)}`)
                      .fontSize(11)
                      .fontColor($r('sys.color.font_tertiary'))
                      .width('100%')
                      .padding({ left: 14, bottom: 8 })
                  }
                }
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
    .title(`${this.zoneName} · 速率限制`)
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
