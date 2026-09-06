// Rulesets 规则行（WAF / Cache / RateLimit / Transform 共用）：
// 描述 + 动作标 + 表达式 + 启停开关，点行编辑、长按删除。
import { RulesetRule } from '../../models/RulesetModels';
import { BRAND_ORANGE } from '../common/Components';

export function actionLabel(action: string): string {
  if (action === 'block') {
    return '拦截';
  }
  if (action === 'managed_challenge') {
    return '托管质询';
  }
  if (action === 'js_challenge') {
    return 'JS 质询';
  }
  if (action === 'challenge') {
    return '质询';
  }
  if (action === 'log') {
    return '仅记录';
  }
  if (action === 'skip') {
    return '跳过';
  }
  if (action === 'set_cache_settings') {
    return '缓存设置';
  }
  if (action === 'rewrite') {
    return '重写';
  }
  return action;
}

@ComponentV2
export struct RuleRow {
  @Require @Param rule: RulesetRule;
  @Param busy: boolean = false;
  @Param onEdit: () => void = () => {
  };
  @Param onToggle: (enabled: boolean) => void = () => {
  };
  @Param onDelete: () => void = () => {
  };

  build() {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(actionLabel(this.rule.action ?? ''))
            .fontSize(10)
            .fontColor(BRAND_ORANGE)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#1AF48120')
            .borderRadius(4)
          Text(this.rule.description ?? '（无描述）')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')

        Text(this.rule.expression ?? '')
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .fontFamily('monospace')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.rule.enabled === true })
        .selectedColor(BRAND_ORANGE)
        .enabled(!this.busy)
        .onChange((isOn: boolean) => {
          if (isOn !== (this.rule.enabled === true)) {
            this.onToggle(isOn);
          }
        })
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(16)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 10, color: '#12000000', offsetY: 4 })
    .margin({ left: 16, right: 16, top: 5, bottom: 5 })
    .onClick(() => {
      this.onEdit();
    })
    .gesture(LongPressGesture().onAction(() => {
      this.onDelete();
    }))
  }
}
