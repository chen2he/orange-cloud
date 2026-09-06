// 指标趋势图（对照 iOS WorkerDetailView.seriesChart）：请求走橙色面积 + 描边线，
// 错误走红色细线（全为 0 时不画）。Canvas 绘制，与 RidgeChart 同一套渲染方式。
// 与 RidgeChart 的区别：这里是「两条真实曲线 + 右侧刻度」的读数图，不是晨昏山脊装饰图。
import { BRAND_ORANGE } from './Components';

/// 一个样本点：请求数 + 错误数
export interface MetricsPoint {
  requests: number;
  errors: number;
}

/// 紧凑记数（12.3K / 4.5M），与右轴刻度共用
function compact(value: number): string {
  if (value >= 1000000) {
    return `${(value / 1000000).toFixed(1)}M`;
  }
  if (value >= 1000) {
    return `${(value / 1000).toFixed(1)}K`;
  }
  return `${Math.round(value)}`;
}

/// Canvas 只接受字符串色值；用图表专用橙（对浅底 3.05:1、对深色卡 5.7:1）
const CHART_ORANGE = '#E8730F';

@ComponentV2
export struct MetricsChart {
  @Require @Param points: MetricsPoint[];
  /// 不能叫 height——与组件内置属性同名会编译失败（同 RidgeChart 的 ridgeHeight）
  @Param chartHeight: number = 130;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  @Local ready: boolean = false;

  @Monitor('points')
  onPointsChange(): void {
    if (this.ready) {
      this.draw();
    }
  }

  /// 纵轴上界：取请求峰值，向上取整到 1/2/5×10^n 便于读刻度
  private niceMax(raw: number): number {
    if (raw <= 0) {
      return 1;
    }
    const magnitude = Math.pow(10, Math.floor(Math.log10(raw)));
    const normalized = raw / magnitude;
    let step = 10;
    if (normalized <= 1) {
      step = 1;
    } else if (normalized <= 2) {
      step = 2;
    } else if (normalized <= 5) {
      step = 5;
    }
    return step * magnitude;
  }

  private draw(): void {
    const ctx = this.ctx;
    const w = ctx.width;
    const h = ctx.height;
    ctx.clearRect(0, 0, w, h);
    const pts = this.points;
    if (pts.length === 0) {
      return;
    }
    // 右侧留出刻度文字宽度
    const padRight = 34;
    const padTop = 8;
    const padBottom = 6;
    const plotW = w - padRight;
    const plotH = h - padTop - padBottom;
    if (plotW <= 0 || plotH <= 0) {
      return;
    }

    let peak = 0;
    let errorPeak = 0;
    for (const p of pts) {
      if (p.requests > peak) {
        peak = p.requests;
      }
      if (p.errors > errorPeak) {
        errorPeak = p.errors;
      }
    }
    const max = this.niceMax(peak);
    const stepX = pts.length > 1 ? plotW / (pts.length - 1) : 0;
    const yOf = (value: number): number => padTop + plotH - (value / max) * plotH;
    const xOf = (index: number): number => pts.length > 1 ? index * stepX : plotW / 2;

    // 三条虚线横向刻度（0 / 半 / 满）
    ctx.strokeStyle = '#33888888';
    ctx.lineWidth = 0.5;
    ctx.setLineDash([3, 3]);
    ctx.font = '10px sans-serif';
    ctx.fillStyle = '#88888888';
    for (let i = 0; i <= 2; i++) {
      const value = max * i / 2;
      const y = yOf(value);
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(plotW, y);
      ctx.stroke();
      ctx.fillText(compact(value), plotW + 5, y + 3);
    }
    ctx.setLineDash([]);

    // 请求：面积渐变 + 顶描边
    const gradient = ctx.createLinearGradient(0, padTop, 0, padTop + plotH);
    gradient.addColorStop(0, '#40F48120');
    gradient.addColorStop(1, '#05F48120');
    ctx.beginPath();
    ctx.moveTo(xOf(0), padTop + plotH);
    for (let i = 0; i < pts.length; i++) {
      ctx.lineTo(xOf(i), yOf(pts[i].requests));
    }
    ctx.lineTo(xOf(pts.length - 1), padTop + plotH);
    ctx.closePath();
    ctx.fillStyle = gradient;
    ctx.fill();

    ctx.beginPath();
    for (let i = 0; i < pts.length; i++) {
      const x = xOf(i);
      const y = yOf(pts[i].requests);
      if (i === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.strokeStyle = CHART_ORANGE;
    ctx.lineWidth = 2;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.stroke();

    // 错误：全 0 就不画，避免一条贴底的红线误导
    if (errorPeak > 0) {
      ctx.beginPath();
      for (let i = 0; i < pts.length; i++) {
        const x = xOf(i);
        const y = yOf(pts[i].errors);
        if (i === 0) {
          ctx.moveTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
      }
      ctx.strokeStyle = '#DC2626';
      ctx.lineWidth = 1.5;
      ctx.stroke();
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height(this.chartHeight)
      .onReady(() => {
        this.ready = true;
        this.draw();
      })
  }
}
