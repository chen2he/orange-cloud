// 「书写规则」可视化表达式构建器组件：字段 + 运算符 + 值 行，AND/OR 连接，
// 可切到「表达式」原始模式。四个 Rulesets 阶段编辑器共用。
// 逻辑逐行移植自 iOS WAFExpressionBuilder（见 models/RuleExpressionBuilder.ets）。
import {
  compileExpression,
  RULE_FIELDS,
  RuleCondition,
  RuleField,
  RuleOperator,
  ruleOperators,
} from '../../models/RuleExpressionBuilder';
import { BRAND_ORANGE, BRAND_ORANGE_BG } from '../common/Components';

function fieldTypeOf(key: string): RuleField {
  for (let i = 0; i < RULE_FIELDS.length; i++) {
    if (RULE_FIELDS[i].key === key) {
      return RULE_FIELDS[i];
    }
  }
  return RULE_FIELDS[0];
}

@ComponentV2
export struct ExpressionBuilder {
  @Param @Require expression: string = '';
  @Event onChange: (expr: string) => void = () => {
  };

  @Local guided: boolean = true;
  @Local rows: RuleCondition[] = [{ fieldKey: 'http.host', opToken: 'eq', value: '' }];
  @Local logic: string = 'and';

  private compiled(): string {
    return compileExpression(this.logic, this.rows);
  }

  private emit(): void {
    this.onChange(this.compiled());
  }

  // rows 数组内容变更后整体重赋值以触发 @Local 刷新
  private replaceRows(next: RuleCondition[]): void {
    this.rows = next;
    this.emit();
  }

  private addRow(): void {
    const next: RuleCondition[] = this.rows.slice();
    next.push({ fieldKey: 'http.host', opToken: 'eq', value: '' });
    this.replaceRows(next);
  }

  private deleteRow(index: number): void {
    const next: RuleCondition[] = this.rows.slice();
    next.splice(index, 1);
    this.replaceRows(next);
  }

  private setField(index: number, key: string): void {
    const next: RuleCondition[] = this.rows.slice();
    const field: RuleField = fieldTypeOf(key);
    const ops: RuleOperator[] = ruleOperators(field.type);
    const cur: RuleCondition = next[index];
    // 字段变更后把运算符复位到该类型的第一个合法值（若当前 token 仍合法则保留）
    let opToken: string = ops.length > 0 ? ops[0].token : 'eq';
    for (let i = 0; i < ops.length; i++) {
      if (ops[i].token === cur.opToken) {
        opToken = cur.opToken;
        break;
      }
    }
    next[index] = { fieldKey: key, opToken: opToken, value: cur.value };
    this.replaceRows(next);
  }

  private setOp(index: number, token: string): void {
    const next: RuleCondition[] = this.rows.slice();
    const cur: RuleCondition = next[index];
    next[index] = { fieldKey: cur.fieldKey, opToken: token, value: cur.value };
    this.replaceRows(next);
  }

  private setValue(index: number, value: string): void {
    const next: RuleCondition[] = this.rows.slice();
    const cur: RuleCondition = next[index];
    next[index] = { fieldKey: cur.fieldKey, opToken: cur.opToken, value: value };
    this.replaceRows(next);
  }

  private switchTo(toGuided: boolean): void {
    if (toGuided === this.guided) {
      return;
    }
    if (!toGuided) {
      // guided → raw：回填编译结果，让原始框显示已拼好的表达式
      this.onChange(this.compiled());
    }
    this.guided = toGuided;
  }

  /// 选中态在 Builder 内部由 this.guided 现算——@Builder 的值参数是静态的，
  /// 把 active 当参数传进来点了不会重绘（同 PermissionSelectionSheet 已修的 bug）。
  @Builder
  segButton(title: string, toGuided: boolean) {
    Text(title)
      .fontSize(13)
      .fontWeight(this.guided === toGuided ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.guided === toGuided ? Color.White : $r('sys.color.font_secondary'))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(30)
      .borderRadius(7)
      .backgroundColor(this.guided === toGuided ? BRAND_ORANGE : Color.Transparent)
      .onClick(() => {
        this.switchTo(toGuided);
      })
  }

  @Builder
  conditionRow(cond: RuleCondition, index: number) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Select(RULE_FIELDS.map((f: RuleField): SelectOption => ({ value: f.label })))
          .selected(RULE_FIELDS.findIndex((f: RuleField): boolean => f.key === cond.fieldKey))
          .value(fieldTypeOf(cond.fieldKey).label)
          .font({ size: 13 })
          .layoutWeight(1)
          .onSelect((i: number) => {
            this.setField(index, RULE_FIELDS[i].key);
          })

        Select(ruleOperators(fieldTypeOf(cond.fieldKey).type)
          .map((o: RuleOperator): SelectOption => ({ value: o.label })))
          .selected(ruleOperators(fieldTypeOf(cond.fieldKey).type)
            .findIndex((o: RuleOperator): boolean => o.token === cond.opToken))
          .value(this.opLabel(cond))
          .font({ size: 13 })
          .onSelect((i: number) => {
            this.setOp(index, ruleOperators(fieldTypeOf(cond.fieldKey).type)[i].token);
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        TextInput({ text: cond.value, placeholder: '值' })
          .fontSize(13)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.setValue(index, value);
          })

        Text('删除')
          .fontSize(12)
          .fontColor('#DC2626')
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .enabled(this.rows.length > 1)
          .opacity(this.rows.length > 1 ? 1 : 0.35)
          .onClick(() => {
            if (this.rows.length > 1) {
              this.deleteRow(index);
            }
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(10)
    .borderRadius(12)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
  }

  private opLabel(cond: RuleCondition): string {
    const ops: RuleOperator[] = ruleOperators(fieldTypeOf(cond.fieldKey).type);
    for (let i = 0; i < ops.length; i++) {
      if (ops[i].token === cond.opToken) {
        return ops[i].label;
      }
    }
    return ops.length > 0 ? ops[0].label : cond.opToken;
  }

  build() {
    Column({ space: 10 }) {
      // 模式切换段控
      Row() {
        this.segButton('书写规则', true)
        this.segButton('表达式', false)
      }
      .width('100%')
      .padding(3)
      .borderRadius(9)
      .backgroundColor($r('app.color.oc_brand_bg'))

      if (this.guided) {
        ForEach(this.rows, (cond: RuleCondition, index: number) => {
          this.conditionRow(cond, index)
        }, (cond: RuleCondition, index: number) => `${index}-${cond.fieldKey}`)

        Row({ space: 12 }) {
          Text('＋加条件')
            .fontSize(13)
            .fontColor($r('app.color.oc_brand_text'))
            .onClick(() => {
              this.addRow();
            })
          Blank()
          Select([{ value: '满足全部' } as SelectOption, { value: '满足任一' } as SelectOption])
            .selected(this.logic === 'or' ? 1 : 0)
            .value(this.logic === 'or' ? '满足任一' : '满足全部')
            .font({ size: 13 })
            .enabled(this.rows.length >= 2)
            .opacity(this.rows.length >= 2 ? 1 : 0.4)
            .onSelect((i: number) => {
              this.logic = i === 1 ? 'or' : 'and';
              this.emit();
            })
        }
        .width('100%')

        // 实时预览
        Text(this.compiled() === '' ? '（尚未填写条件）' : this.compiled())
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding(10)
          .borderRadius(10)
          .backgroundColor($r('sys.color.comp_background_list_card'))
      } else {
        TextArea({ text: this.expression, placeholder: '表达式，如 (ip.src eq 1.2.3.4) or (http.host eq "a.com")' })
          .fontSize(12)
          .height(110)
          .width('100%')
          .onChange((value: string) => {
            this.onChange(value);
          })
      }
    }
    .width('100%')
  }
}
