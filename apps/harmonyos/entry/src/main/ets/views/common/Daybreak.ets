// 页面层级（HarmonyOS「深度层级 / 平面层级」口径）——新页面一律照这四级铺，别自造中间色：
//   L0 页面底     sys.color.background_secondary      灰底 / 纯黑
//   L1 分组卡片   sys.color.comp_background_list_card 白 / #1A1A1A（无描边、无投影，靠明度差分层）
//   L2 卡内控件   sys.color.comp_background_tertiary  分段轨道 / 输入框 / 芯片底
//   L3 浮层       半模态与弹窗（ocSheet：灰底 + 内部 L1 卡片，与设置页同一套分组语言）
// 视觉权重同理只有三档：主操作 = oc_brand_cta 实心（每屏至多一个）；
//   选中态 / 筛选态 = oc_brand_bg 浅底 + oc_brand_text 文字；其余 = 系统中性色。
// 反面教材（已清理）：整屏渐变天色、卡片 0.5px 描边 + 投影、选中态用实心品牌色——
// 三者叠加会让一屏出现五六个同等权重的色块，层级就糊了。
// 「晨昏」设计基座（精确对照 iOS Views/Components/Daybreak.swift）：
// 玻璃岛浮在天色上 + 地平线弧上的太阳/月亮按时走位 + 布局常量全局统一。
import { mediaquery } from '@kit.ArkUI';
import { BRAND_ORANGE } from './Components';

/// 布局常量（对照 iOS OCLayout，不再各处手写魔法数）
export class OCLayout {
  static readonly islandRadius: number = 20; // 玻璃岛圆角
  static readonly chipRadius: number = 16; // 小岛/行内控件圆角
  static readonly pagePadding: number = 16; // 页面水平边距
  static readonly islandGap: number = 12; // 岛与岛间距
  static readonly islandPadding: number = 14; // 岛内边距
}

/// 玻璃岛容器：玻璃底透天色 + 顶亮底暗折射描边 + 软投影（对照 iOS glassIsland）。
/// 内容经 @BuilderParam 传入。
@Component
export struct GlassIsland {
  @Prop cornerRadius: number = OCLayout.islandRadius;
  @Prop pad: number = OCLayout.islandPadding;
  @BuilderParam content: () => void;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(this.pad)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(this.cornerRadius)
    // HarmonyOS 卡片是平的：靠卡片色与页面底色（background_secondary）的明度差分层，
    // 不加描边、不加投影。原先的 0.5px 描边 + 软投影是 iOS 玻璃岛的做法，与系统观感冲突。
  }
}

/// 玻璃岛错峰浮现（对照 iOS islandReveal）：一次性入场——透明度 0→1 + 上移 12→0，
/// 延迟 = idx × 45ms，单档 300ms，Friction 缓出。只做属性动画，不引入模糊/逐帧重绘，
/// 不影响滚动性能（玻璃材质保持纯色校准，见 GlassIsland 注释）。
/// 防重放：played 在首次 onAppear 置位后不再回滚；页面实例仍在导航栈中被二次展示
/// （NavDestination onShown，如从子页 pop 回来）时组件未重挂载、onAppear 不会再触发；
/// 万一被重复挂载（分支重建等）也只直落终态、不再播动画。
/// 减少动画（设置页开关；开启后错峰浮现一步到位）。
/// 全局可观察单例：设置页拨动后各页 RevealBox 立即按新口径走。
@ObservedV2
export class MotionPrefs {
  @Trace reduced: boolean = false;
}

export const motionPrefs: MotionPrefs = new MotionPrefs();

@ComponentV2
export struct RevealBox {
  /// 错峰档位：延迟 = idx × 45ms（长列表调用侧自行封顶）
  @Param idx: number = 0;
  @BuilderParam content: () => void;
  @Local revealed: boolean = false;
  private played: boolean = false;

  private play(): void {
    // 减少动画：直接到位，不做浮现过渡
    if (this.played || motionPrefs.reduced) {
      this.played = true;
      this.revealed = true;
      return;
    }
    this.played = true;
    try {
      this.getUIContext().animateTo({
        duration: 300,
        curve: Curve.Friction,
        delay: this.idx * 45,
      }, () => {
        this.revealed = true;
      });
    } catch (e) {
      // 上下文异常时直接显示，绝不让内容卡在透明态
      this.revealed = true;
    }
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .opacity(this.revealed ? 1 : 0)
    .translate({ y: this.revealed ? 0 : 12 })
    .onAppear(() => {
      this.play();
    })
  }
}

/// 分区标题（对照 iOS .font(.title3.bold)）
@Component
export struct SectionTitle {
  @Prop title: string;

  build() {
    Row() {
      Text(this.title)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
      Blank()
    }
    .width('100%')
  }
}

/// 2×2 指标岛（对照 iOS StatIsland：label caption 次色 + 大数 title rounded bold + sub caption2 三级色）
@Component
export struct StatIsland {
  @Prop label: string;
  @Prop value: string;
  @Prop sub: string = '';

  build() {
    Column({ space: 2 }) {
      Text(this.label)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
      Text(this.value)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.sub !== '') {
        Text(this.sub)
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(OCLayout.islandPadding)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(OCLayout.chipRadius)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
  }
}

/// 地平线弧：细弧线 + 太阳(昼)/月亮(夜)按当前时刻在弧上走位（对照 iOS HorizonArc）。
@ComponentV2
export struct HorizonArc {
  @Local isDark: boolean = false;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;
  private listener?: mediaquery.MediaQueryListener;

  aboutToAppear(): void {
    try {
      this.listener = mediaquery.matchMediaSync('(dark-mode: true)');
      this.isDark = this.listener.matches;
      this.listener.on('change', (res: mediaquery.MediaQueryResult) => {
        this.isDark = res.matches;
        if (this.ready) {
          this.draw();
        }
      });
    } catch (e) {
    }
  }

  aboutToDisappear(): void {
    try {
      this.listener?.off('change');
    } catch (e) {
    }
  }

  /// 当前时刻在所属半日的进度（昼 6→18，夜 18→次日6）
  private progress(): number {
    const now = new Date();
    const minutes = now.getHours() * 60 + now.getMinutes();
    const day = (minutes - 6 * 60) / (12 * 60);
    if (day >= 0 && day < 1) {
      return Math.min(Math.max(day, 0.02), 0.98);
    }
    const night = minutes >= 18 * 60 ? minutes - 18 * 60 : minutes + 6 * 60;
    return Math.min(Math.max(night / (12 * 60), 0.02), 0.98);
  }

  private draw(): void {
    const ctx = this.ctx;
    const w = ctx.width;
    const h = ctx.height;
    ctx.clearRect(0, 0, w, h);
    const sx = 0;
    const sy = h - 2;
    const ex = w;
    const ey = h - 2;
    const cx = w / 2;
    const cy = -h * 0.55;
    const t = this.progress();
    const mt = 1 - t;
    // 弧线（虚线）
    ctx.beginPath();
    ctx.moveTo(sx, sy);
    ctx.quadraticCurveTo(cx, cy, ex, ey);
    ctx.setLineDash([3, 4]);
    ctx.lineWidth = 1;
    ctx.strokeStyle = this.isDark ? '#29FFFFFF' : '#59F48120';
    ctx.stroke();
    ctx.setLineDash([]);
    // 天体位置（二次贝塞尔）
    const dotX = mt * mt * sx + 2 * mt * t * cx + t * t * ex;
    const dotY = mt * mt * sy + 2 * mt * t * cy + t * t * ey;
    const body = this.isDark ? '#EDEDFA' : BRAND_ORANGE;
    ctx.beginPath();
    ctx.arc(dotX, dotY, 4, 0, Math.PI * 2);
    ctx.fillStyle = body;
    ctx.fill();
    // 光晕
    ctx.beginPath();
    ctx.arc(dotX, dotY, 8, 0, Math.PI * 2);
    ctx.fillStyle = this.isDark ? '#4DFFFFFF' : '#4DF48120';
    ctx.fill();
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height(44)
      .onReady(() => {
        this.ready = true;
        this.draw();
      })
  }
}

function timeGreeting(): string {
  const h = new Date().getHours();
  if (h < 5) {
    return '夜深了';
  }
  if (h < 11) {
    return '早上好';
  }
  if (h < 13) {
    return '中午好';
  }
  if (h < 18) {
    return '下午好';
  }
  return '晚上好';
}

function dateLine(): string {
  const now = new Date();
  const weekdays = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  return `${now.getMonth() + 1} 月 ${now.getDate()} 日 ${weekdays[now.getDay()]}`;
}

/// 晨昏问候头（对照 iOS daybreakHeader：日期 + 时段问候·账号 + 健康句 + 地平线弧）
@ComponentV2
export struct DaybreakHeader {
  @Param accountName: string = '';
  @Param healthLine: string = '';

  build() {
    Column({ space: 5 }) {
      Text(dateLine())
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
      Text(this.accountName !== '' ? `${timeGreeting()}，${this.accountName}` : timeGreeting())
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.healthLine !== '') {
        Text(this.healthLine)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      HorizonArc()
        .margin({ top: 2 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 4 })
  }
}
