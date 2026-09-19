// 中尺寸「山脊」服务卡（2×4/4×4）：24h 请求序列拼成地形柱条，太阳落在当前时刻，
// 顶部大字 24h 请求合计。卡片端不支持 Canvas，用 Row of Rect 柱条近似山脊。
// 数据由 OrangeCloudFormAbility 从共享快照绑定；点按拉起主 App。
// 注意：ArkTS 卡片页共享编译作用域，顶层符号需与 OrangeCloudCard 不重名（此处全部 r 前缀）。

function rSkyColors(phase: number): Array<[string, number]> {
  switch (phase) {
    case 0:
      return [['#FFE8D1', 0.0], ['#F5F2ED', 1.0]];
    case 2:
      return [['#FFDEBF', 0.0], ['#F0EDF2', 1.0]];
    case 3:
      return [['#1F1208', 0.0], ['#0F0E13', 0.6], ['#0A0A0F', 1.0]];
    case 4:
      return [['#120D0A', 0.0], ['#0A0A0E', 1.0]];
    default:
      return [['#FCF2E3', 0.0], ['#F2F2F2', 1.0]];
  }
}

function rIsDark(phase: number): boolean {
  return phase === 3 || phase === 4;
}

function rOnSky(phase: number): string {
  return rIsDark(phase) ? '#F3ECE4' : '#24190F';
}

function rOnSkyDim(phase: number): string {
  return rIsDark(phase) ? '#B3F3ECE4' : '#9924190F';
}

interface RidgeBar {
  ratio: number;
  isSun: boolean;
}

/// 逗号序列 → 归一化柱条（末端为当前时刻，标记太阳）
function rParseBars(series: string): RidgeBar[] {
  if (series === '') {
    return [];
  }
  const parts = series.split(',');
  const nums: number[] = [];
  for (const p of parts) {
    const n = Number.parseFloat(p);
    nums.push(Number.isNaN(n) ? 0 : n);
  }
  let max = 0;
  for (const n of nums) {
    if (n > max) {
      max = n;
    }
  }
  if (max <= 0) {
    max = 1;
  }
  const bars: RidgeBar[] = [];
  for (let i = 0; i < nums.length; i++) {
    bars.push({ ratio: Math.max(0.04, nums[i] / max), isSun: i === nums.length - 1 });
  }
  return bars;
}

const ridgeStorage = new LocalStorage();

@Entry(ridgeStorage)
@Component
struct OrangeCloudRidgeCard {
  @LocalStorageProp('label') label: string = '未登录';
  @LocalStorageProp('requests') requests: string = '—';
  @LocalStorageProp('zones') zones: string = '—';
  @LocalStorageProp('series') series: string = '';
  @LocalStorageProp('phase') phase: number = 1;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({ angle: 180, colors: rSkyColors(this.phase) })

      Column() {
        Row() {
          Column() {
            Text('今日请求')
              .fontSize(11)
              .fontColor(rOnSkyDim(this.phase))
            Text(this.requests)
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(rOnSky(this.phase))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text(`${this.zones} 域名`)
            .fontSize(11)
            .fontColor(rOnSkyDim(this.phase))
        }
        .width('100%')

        Blank()

        // 山脊：柱条地形，太阳（当前时刻）高亮
        Row({ space: 2 }) {
          ForEach(rParseBars(this.series), (bar: RidgeBar, index: number) => {
            Column() {
              Blank()
              if (bar.isSun) {
                Circle({ width: 8, height: 8 })
                  .fill('#F48120')
                  .margin({ bottom: 2 })
              }
              Column()
                .width('100%')
                .height(`${bar.ratio * 100}%`)
                .backgroundColor(bar.isSun ? '#F48120' : (rIsDark(this.phase) ? '#66F48120' : '#4DF48120'))
                .borderRadius({ topLeft: 2, topRight: 2 })
            }
            .layoutWeight(1)
            .height('100%')
          }, (bar: RidgeBar, index: number) => `${index}`)
        }
        .width('100%')
        .height(64)
        .alignItems(VerticalAlign.Bottom)

        Text(this.label)
          .fontSize(11)
          .fontColor(rOnSkyDim(this.phase))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6 })
      }
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
