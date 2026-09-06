import { HdsListItemCard, IconSize, PrefixIcon, SuffixArrow, SuffixSwitch, SuffixText, SuffixTextAndArrow } from '@kit.UIDesignKit';
// 公共 UI 组件：加载 / 错误 / 空态 / 分区头 / 信息行 / 开关行 / 导航行 / 标签。
// 品牌橙 #F48120 只给点缀（对齐晨昏设计语言：数字回归主文本色）。

/// 图形/装饰用橙（字符串型：Canvas、字符串形参、字符串拼接都要用它）。
/// 比原亮橙 #F48120 深一档，保证线条/图标这类图形元素对浅底 3.05:1、对深色卡 5.7:1。
/// 文字请用 $r('app.color.oc_brand_text')，白字底请用 $r('app.color.oc_brand_cta')。
export const BRAND_ORANGE: string = '#E8730F';
export const BRAND_ORANGE_BG: string = '#1AE8730F';
export const DANGER_RED = '#DC2626';

@ComponentV2
export struct OCLoading {
  @Param text: string = '正在加载…';

  build() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color(BRAND_ORANGE)
      Text(this.text)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}

@ComponentV2
export struct OCError {
  @Param message: string = '加载失败';
  @Param onRetry: () => void = () => {
  };

  build() {
    Column({ space: 14 }) {
      Text('出错了')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
      Text(this.message)
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
      Button('重试')
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .onClick(() => {
          this.onRetry();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}

@ComponentV2
export struct OCEmpty {
  @Param icon: string = '';
  @Param symbol: Resource | null = null;
  @Param title: string = '暂无数据';
  @Param subtitle: string = '';

  build() {
    Column({ space: 8 }) {
      if (this.symbol !== null) {
        SymbolGlyph(this.symbol)
          .fontSize(46)
          .fontColor([$r('sys.color.font_tertiary')])
          .margin({ bottom: 4 })
      } else {
        Text(this.icon !== '' ? this.icon : '🗒️')
          .fontSize(40)
      }
      Text(this.title)
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
      if (this.subtitle !== '') {
        Text(this.subtitle)
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .textAlign(TextAlign.Center)
          .padding({ left: 32, right: 32 })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}

@ComponentV2
export struct SectionHeader {
  @Param title: string = '';

  build() {
    Text(this.title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 6 })
  }
}

@ComponentV2
export struct InfoRow {
  @Param label: string = '';
  @Param value: string = '';

  build() {
    HdsListItemCard({
      textItem: { primaryText: { text: this.label } },
      suffixItem: new SuffixText({ text: this.value }),
      // 卡片背板交给外层分组容器（GlassIsland），这里只取系统列表项的排版与触感
      cardBackgroundColor: Color.Transparent,
    })
  }
}

@ComponentV2
export struct ToggleRow {
  @Param title: string = '';
  @Param subtitle: string = '';
  @Param isOn: boolean = false;
  @Param isEnabled: boolean = true;
  @Param onToggle: (isOn: boolean) => void = () => {
  };

  build() {
    HdsListItemCard({
      textItem: {
        primaryText: { text: this.title },
        secondaryText: this.subtitle !== '' ? { text: this.subtitle } : undefined,
      },
      suffixItem: new SuffixSwitch({
        isCheck: this.isOn,
        enable: this.isEnabled,
        selectColor: $r('app.color.oc_brand'),
        onChange: (isOn: boolean) => {
          if (isOn !== this.isOn) {
            this.onToggle(isOn);
          }
        },
      }),
      cardBackgroundColor: Color.Transparent,
    })
  }
}

@ComponentV2
export struct NavRow {
  @Param icon: string = '';
  @Param symbol: Resource | null = null;
  @Param title: string = '';
  @Param subtitle: string = '';
  /// Pro 闸门行：chevron 前挂一枚「Pro」徽章（点按仍进，由 requirePro 决定是推付费墙还是目的页）
  @Param locked: boolean = false;
  @Param onNav: () => void = () => {
  };

  build() {
    HdsListItemCard({
      prefixItem: this.symbol !== null
        ? new PrefixIcon({ iconValue: { symbol: this.symbol }, iconSize: IconSize.SYSTEM_ICON })
        : undefined,
      textItem: {
        primaryText: { text: this.title },
        secondaryText: this.subtitle !== '' ? { text: this.subtitle } : undefined,
      },
      // Pro 闸门行用「Pro ›」文字+箭头槽位：HDS 列表项没有徽章槽，把 ProBadge 挂在卡片
      // 外面会被卡片裁掉（实测右侧只露出半个「Pr」），所以走系统的 SuffixTextAndArrow。
      suffixItem: this.locked
        ? new SuffixTextAndArrow({ text: 'Pro' }, {})
        : new SuffixArrow({}),
      onClick: () => {
        this.onNav();
      },
      cardBackgroundColor: Color.Transparent,
    })
  }
}

/// Pro 徽章：闸门入口的统一标识（品牌橙描边胶囊，不抢主文本）
@ComponentV2
export struct ProBadge {
  build() {
    Text('Pro')
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.oc_brand_text'))
      .padding({ left: 7, right: 7, top: 2, bottom: 2 })
      .backgroundColor($r('app.color.oc_brand_bg'))
      .borderRadius(8)
  }
}

/// 资源玻璃卡片行（对照 iOS glassRow）：图标(暖底方块) + 标题/副标题 + 可选尾标 + chevron，
/// 点按 onTap、长按 onLongPress（删除等）。用于 R2/D1/KV/Workers/Pages 等资源列表页。
@ComponentV2
export struct ResourceCard {
  @Param icon: string = '';
  @Param symbol: Resource | null = null;
  @Param title: string = '';
  @Param subtitle: string = '';
  @Param trailing: string = '';
  @Param onTap: () => void = () => {
  };
  @Param onLongPress: () => void = () => {
  };

  build() {
    Row({ space: 12 }) {
      if (this.symbol !== null) {
        Stack() {
          SymbolGlyph(this.symbol)
            .fontSize(21)
            .fontColor([$r('app.color.oc_brand_text')])
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.oc_brand_bg'))
        .borderRadius(11)
      } else if (this.icon !== '') {
        Text(this.icon)
          .fontSize(20)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.oc_brand_bg'))
          .borderRadius(11)
      }
      Column({ space: 3 }) {
        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.trailing !== '') {
        Text(this.trailing)
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
      }
      Image($r('sys.media.ohos_ic_public_arrow_right'))
        .width(14)
        .height(14)
        .fillColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(16)
    .onClick(() => {
      this.onTap();
    })
    .gesture(LongPressGesture().onAction(() => {
      this.onLongPress();
    }))
  }
}

@ComponentV2
export struct OCTag {
  @Param text: string = '';
  @Param color: string = BRAND_ORANGE;

  build() {
    Text(this.text)
      .fontSize(10)
      .fontColor(this.color)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor(`#1A${this.color.replace('#', '')}`)
      .borderRadius(4)
  }
}
