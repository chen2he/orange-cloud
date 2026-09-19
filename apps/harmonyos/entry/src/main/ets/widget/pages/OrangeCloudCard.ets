// 晨昏「天窗」服务卡片：域名总数大字直落天色，页脚账号 + 已激活。
// 数据由 OrangeCloudFormAbility 从共享快照绑定；点按拉起主 App。
// 卡片运行时受限，只用 Text/Column/Row/Stack + linearGradient；相位色内联（不 import 主模块逻辑）。

// 相位天色渐变（自上而下），与 core/design/SkyPhase.ets 同表
function skyColors(phase: number): Array<[string, number]> {
  switch (phase) {
    case 0: // Dawn
      return [['#FFE8D1', 0.0], ['#F5F2ED', 1.0]];
    case 2: // Dusk
      return [['#FFDEBF', 0.0], ['#F0EDF2', 1.0]];
    case 3: // Ember
      return [['#1F1208', 0.0], ['#0F0E13', 0.6], ['#0A0A0F', 1.0]];
    case 4: // Night
      return [['#120D0A', 0.0], ['#0A0A0E', 1.0]];
    default: // Day
      return [['#FCF2E3', 0.0], ['#F2F2F2', 1.0]];
  }
}

function isDarkPhase(phase: number): boolean {
  return phase === 3 || phase === 4;
}

function onSky(phase: number): string {
  return isDarkPhase(phase) ? '#F3ECE4' : '#24190F';
}

function onSkyDim(phase: number): string {
  return isDarkPhase(phase) ? '#B3F3ECE4' : '#9924190F';
}

const storage = new LocalStorage();

@Entry(storage)
@Component
struct OrangeCloudCard {
  @LocalStorageProp('label') label: string = '未登录';
  @LocalStorageProp('requests') requests: string = '—';
  @LocalStorageProp('zones') zones: string = '—';
  @LocalStorageProp('active') active: string = '—';
  @LocalStorageProp('phase') phase: number = 1;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 天色背景
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: skyColors(this.phase),
        })

      // 地平线上的橙色天体（右下角露头）
      Circle({ width: 88, height: 88 })
        .fill('#F48120')
        .opacity(isDarkPhase(this.phase) ? 0.9 : 0.8)
        .position({ x: '62%', y: '58%' })

      Column() {
        Text('今日请求')
          .fontSize(12)
          .fontColor(onSkyDim(this.phase))

        Blank()

        Text(this.requests)
          .fontSize(40)
          .fontWeight(FontWeight.Bold)
          .fontColor(onSky(this.phase))
          .maxLines(1)

        Text(`${this.zones} 域名 · ${this.label}`)
          .fontSize(11)
          .fontColor(onSkyDim(this.phase))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .height('100%')
      .padding(14)
      .onClick(() => {
        postCardAction(this, {
          action: 'router',
          abilityName: 'EntryAbility',
          params: {} as Record<string, Object>,
        });
      })
    }
    .width('100%')
    .height('100%')
  }
}
