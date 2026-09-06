import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// Transform 规则：三个 phase 切换（URL 重写 / 请求头 / 响应头），动作恒为 rewrite。
// 对齐 Android ZoneTransformScreen。
import {
  HeaderTransform,
  RuleActionParameters,
  RulesetPhases,
  RulesetRule,
  RulesetRuleCreate,
  UriRewrite,
  UriRewriteValue,
} from '../../models/RulesetModels';
import { ZoneRouteParam } from '../../models/Routes';
import { RulesetVM } from '../../services/RulesetService';
import { BRAND_ORANGE, OCEmpty, OCLoading } from '../common/Components';
import { RuleRow } from './RuleComponents';
import { ExpressionBuilder } from './ExpressionBuilder';
import { lintExpression } from '../../models/RuleExpressionBuilder';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

interface PhaseSpec {
  raw: string;
  label: string;
  isUrl: boolean;
}

const PHASES: PhaseSpec[] = [
  { raw: RulesetPhases.TRANSFORM_URL, label: 'URL 重写', isUrl: true },
  { raw: RulesetPhases.TRANSFORM_REQ_HEADER, label: '请求头', isUrl: false },
  { raw: RulesetPhases.TRANSFORM_RESP_HEADER, label: '响应头', isUrl: false },
];

@ComponentV2
export struct TransformRulesPage {
  @Local vms: RulesetVM[] = [
    new RulesetVM(RulesetPhases.TRANSFORM_URL),
    new RulesetVM(RulesetPhases.TRANSFORM_REQ_HEADER),
    new RulesetVM(RulesetPhases.TRANSFORM_RESP_HEADER),
  ];
  @Local phaseIndex: number = 0;
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local editorVisible: boolean = false;
  @Local editingId: string = '';
  @Local fDescription: string = '';
  @Local fExpression: string = '';
  @Local fPath: string = '';
  @Local fQuery: string = '';
  @Local fHeaderName: string = '';
  @Local fHeaderOp: string = 'set';
  @Local fHeaderValue: string = '';

  private vm(): RulesetVM {
    return this.vms[this.phaseIndex];
  }

  private phase(): PhaseSpec {
    return PHASES[this.phaseIndex];
  }

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  private rules(): RulesetRule[] {
    return this.vm().ruleset?.rules ?? [];
  }

  private openEditor(rule: RulesetRule | null): void {
    this.vm().saveError = '';
    if (rule) {
      this.editingId = rule.id;
      this.fDescription = rule.description ?? '';
      this.fExpression = rule.expression ?? '';
      this.fPath = rule.action_parameters?.uri?.path?.value ?? '';
      this.fQuery = rule.action_parameters?.uri?.query?.value ?? '';
      const headers = rule.action_parameters?.headers;
      if (headers) {
        const keys = Object.keys(headers);
        if (keys.length > 0) {
          this.fHeaderName = keys[0];
          this.fHeaderOp = headers[keys[0]].operation ?? 'set';
          this.fHeaderValue = headers[keys[0]].value ?? '';
        }
      }
    } else {
      this.editingId = '';
      this.fDescription = '';
      this.fExpression = '';
      this.fPath = '';
      this.fQuery = '';
      this.fHeaderName = '';
      this.fHeaderOp = 'set';
      this.fHeaderValue = '';
    }
    this.editorVisible = true;
  }

  private submit(): void {
    const lint: string = lintExpression(this.fExpression.trim());
    if (lint !== '') {
      this.toast(lint);
      return;
    }
    const params: RuleActionParameters = {};
    if (this.phase().isUrl) {
      const uri: UriRewrite = {};
      if (this.fPath.trim() !== '') {
        const pathValue: UriRewriteValue = { value: this.fPath.trim() };
        uri.path = pathValue;
      }
      if (this.fQuery.trim() !== '') {
        const queryValue: UriRewriteValue = { value: this.fQuery.trim() };
        uri.query = queryValue;
      }
      params.uri = uri;
    } else {
      const header: HeaderTransform = { operation: this.fHeaderOp };
      if (this.fHeaderOp === 'set') {
        header.value = this.fHeaderValue;
      }
      const headers: Record<string, HeaderTransform> = {};
      headers[this.fHeaderName.trim()] = header;
      params.headers = headers;
    }
    const rule: RulesetRuleCreate = {
      action: 'rewrite',
      expression: this.fExpression.trim(),
      description: this.fDescription.trim(),
      enabled: true,
      action_parameters: params,
    };
    this.vm().save(this.zoneId, this.editingId, rule).then((ok: boolean) => {
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
          this.vm().remove(this.zoneId, rule.id).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  @Builder
  editorSheet() {
    Column({ space: 12 }) {
      Text(this.editingId === '' ? `新建${this.phase().label}规则` : `编辑${this.phase().label}规则`)
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

      if (this.phase().isUrl) {
        TextInput({ text: this.fPath, placeholder: '重写路径为（留空不改），如 /new-path' })
          .fontSize(14)
          .width('100%')
          .onChange((value: string) => {
            this.fPath = value;
          })
        TextInput({ text: this.fQuery, placeholder: '重写查询串为（留空不改），如 a=1' })
          .fontSize(14)
          .width('100%')
          .onChange((value: string) => {
            this.fQuery = value;
          })
      } else {
        TextInput({ text: this.fHeaderName, placeholder: '头名称，如 X-Custom' })
          .fontSize(14)
          .width('100%')
          .onChange((value: string) => {
            this.fHeaderName = value;
          })
        Row({ space: 12 }) {
          Text('操作')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          Select([{ value: '设置' } as SelectOption, { value: '移除' } as SelectOption])
            .selected(this.fHeaderOp === 'set' ? 0 : 1)
            .value(this.fHeaderOp === 'set' ? '设置' : '移除')
            .font({ size: 14 })
            .onSelect((index: number) => {
              this.fHeaderOp = index === 0 ? 'set' : 'remove';
            })
        }
        .width('100%')

        if (this.fHeaderOp === 'set') {
          TextInput({ text: this.fHeaderValue, placeholder: '头的值' })
            .fontSize(14)
            .width('100%')
            .onChange((value: string) => {
              this.fHeaderValue = value;
            })
        }
      }

      if (this.vm().saveError !== '') {
        Text(this.vm().saveError)
          .fontSize(13)
          .fontColor('#DC2626')
          .width('100%')
      }

      Button(this.vm().isSaving ? '正在保存…' : (this.editingId === '' ? '创建' : '保存'))
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm().isSaving && this.fExpression.trim() !== '' &&
          (this.phase().isUrl
            ? (this.fPath.trim() !== '' || this.fQuery.trim() !== '')
            : this.fHeaderName.trim() !== ''))
        .onClick(() => {
          this.submit();
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        Column() {
          Row({ space: 8 }) {
            ForEach(PHASES, (spec: PhaseSpec, index: number) => {
              Text(spec.label)
                .fontSize(13)
                .fontWeight(this.phaseIndex === index ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.phaseIndex === index ? $r('app.color.oc_brand_text') : $r('sys.color.font_secondary'))
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .backgroundColor(this.phaseIndex === index ? $r('app.color.oc_brand_bg') : $r('sys.color.comp_background_list_card'))
                .borderRadius(16)
                .onClick(() => {
                  this.phaseIndex = index;
                  if (!this.vm().ruleset) {
                    this.vm().load(this.zoneId).catch(() => {
                    });
                  }
                })
            }, (spec: PhaseSpec) => spec.raw)
            Blank()
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 4 })

          if (this.vm().isLoading) {
            OCLoading({ text: '正在加载规则…' })
          } else if (this.rules().length === 0) {
            OCEmpty({ symbol: $r('sys.symbol.arrow_left_arrow_right'), title: `暂无${this.phase().label}规则`, subtitle: '点右下角 + 创建' })
          } else {
            List() {
              ForEach(this.rules(), (rule: RulesetRule) => {
                ListItem() {
                  RuleRow({
                    rule: rule,
                    busy: this.vm().isSaving,
                    onEdit: () => {
                      this.openEditor(rule);
                    },
                    onToggle: (enabled: boolean) => {
                      this.vm().toggle(this.zoneId, rule.id, enabled).then((err: string) => {
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
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
        }
        .width('100%')
        .height('100%')

        Button('+')
          .width(52)
          .height(52)
          .fontSize(26)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.oc_brand_cta'))
          .borderRadius(26)
          .margin({ right: 20, bottom: 28 })
          .onClick(() => {
            this.openEditor(null);
          })
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({ content: { title: { mainTitle: `${this.zoneName} · Transform` } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.editorVisible, this.editorSheet(), ocSheet(() => {
      this.editorVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      for (const vm of this.vms) {
        vm.load(param.zoneId).catch(() => {
        });
      }
    })
  }
}
