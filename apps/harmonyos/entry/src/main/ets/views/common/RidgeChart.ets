// 山脊图（对齐 iOS/Android「数据长成地形」）：24h 数据点连成起伏山脊，
// 填充暖色渐变，脚下地平线，太阳落在当前时刻的山脊上。主 App 用 Canvas 绘制。
import { BRAND_ORANGE } from './Components';

/// 图表专用橙：比品牌亮橙深一档，保证线/点这类图形元素对浅底 3.05:1、对深色卡 5.7:1
const CHART_ORANGE = '#E8730F';

@ComponentV2
export struct RidgeChart {
  @Require @Param data: number[];
  /// 太阳所在样本下标（当前钟点），<0 不画
  @Param sunIndex: number = -1;
  @Param ridgeHeight: number = 150;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  @Local ready: boolean = false;

  @Monitor('data', 'sunIndex')
  onDataChange(): void {
    if (this.ready) {
      this.draw();
    }
  }

  private draw(): void {
    const ctx = this.ctx;
    const w = ctx.width;
    const h = ctx.height;
    ctx.clearRect(0, 0, w, h);
    const pts = this.data;
    if (pts.length === 0) {
      return;
    }
    let max = 0;
    for (const v of pts) {
      if (v > max) {
        max = v;
      }
    }
    if (max <= 0) {
      max = 1;
    }
    const baseline = h - 14; // 地平线之上留脚
    const top = 12;
    const usable = baseline - top;
    const n = pts.length;
    const stepX = n > 1 ? w / (n - 1) : w;

    // 山脊顶线坐标
    const xy: number[][] = [];
    for (let i = 0; i < n; i++) {
      const x = i * stepX;
      const y = baseline - (pts[i] / max) * usable;
      xy.push([x, y]);
    }

    // 填充山体（渐变）
    const grad = ctx.createLinearGradient(0, top, 0, baseline);
    grad.addColorStop(0, '#66E8730F');
    grad.addColorStop(1, '#0FE8730F');
    ctx.beginPath();
    ctx.moveTo(0, baseline);
    for (let i = 0; i < n; i++) {
      ctx.lineTo(xy[i][0], xy[i][1]);
    }
    ctx.lineTo(w, baseline);
    ctx.closePath();
    ctx.fillStyle = grad;
    ctx.fill();

    // 山脊线
    ctx.beginPath();
    ctx.moveTo(xy[0][0], xy[0][1]);
    for (let i = 1; i < n; i++) {
      ctx.lineTo(xy[i][0], xy[i][1]);
    }
    ctx.strokeStyle = CHART_ORANGE;
    ctx.lineWidth = 2;
    ctx.stroke();

    // 地平线
    ctx.beginPath();
    ctx.moveTo(0, baseline);
    ctx.lineTo(w, baseline);
    ctx.strokeStyle = '#33E8730F';
    ctx.lineWidth = 1;
    ctx.stroke();

    // 太阳（落在当前时刻的山脊上）
    if (this.sunIndex >= 0 && this.sunIndex < n) {
      const sx = xy[this.sunIndex][0];
      const sy = xy[this.sunIndex][1];
      ctx.beginPath();
      ctx.arc(sx, sy, 9, 0, Math.PI * 2);
      ctx.fillStyle = CHART_ORANGE;
      ctx.fill();
      // 光晕
      ctx.beginPath();
      ctx.arc(sx, sy, 15, 0, Math.PI * 2);
      ctx.fillStyle = '#33E8730F';
      ctx.fill();
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height(this.ridgeHeight)
      .onReady(() => {
        this.ready = true;
        this.draw();
      })
  }
}
