// 太阳弧仪表（对齐 iOS/Android 用量太阳弧）：半圆弧轨道 + 沿弧运行的太阳，
// 弧的进度 = 比值（0~1）。主 App 用 Canvas 绘制；中心可放百分比文字（由调用方叠加）。
import { BRAND_ORANGE } from './Components';

@ComponentV2
export struct SunArcGauge {
  /// 0~1 比值（如缓存命中率）
  @Require @Param ratio: number;
  @Param gaugeSize: number = 120;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  @Local ready: boolean = false;

  @Monitor('ratio')
  onRatioChange(): void {
    if (this.ready) {
      this.draw();
    }
  }

  private draw(): void {
    const ctx = this.ctx;
    const w = ctx.width;
    const h = ctx.height;
    ctx.clearRect(0, 0, w, h);
    const cx = w / 2;
    const cy = h - 8;
    const radius = Math.min(w / 2 - 12, h - 16);
    const start = Math.PI; // 180°（左）
    const end = Math.PI * 2; // 360°（右），上半弧
    const r = Math.max(0, Math.min(1, this.ratio));

    // 轨道
    ctx.beginPath();
    ctx.arc(cx, cy, radius, start, end);
    ctx.strokeStyle = '#1FF48120';
    ctx.lineWidth = 8;
    ctx.lineCap = 'round';
    ctx.stroke();

    // 进度弧
    const cur = start + (end - start) * r;
    ctx.beginPath();
    ctx.arc(cx, cy, radius, start, cur);
    ctx.strokeStyle = BRAND_ORANGE;
    ctx.lineWidth = 8;
    ctx.lineCap = 'round';
    ctx.stroke();

    // 太阳（弧末端）
    const sx = cx + radius * Math.cos(cur);
    const sy = cy + radius * Math.sin(cur);
    ctx.beginPath();
    ctx.arc(sx, sy, 8, 0, Math.PI * 2);
    ctx.fillStyle = BRAND_ORANGE;
    ctx.fill();
    ctx.beginPath();
    ctx.arc(sx, sy, 13, 0, Math.PI * 2);
    ctx.fillStyle = '#33F48120';
    ctx.fill();
  }

  build() {
    Canvas(this.ctx)
      .width(this.gaugeSize)
      .height(this.gaugeSize / 2 + 16)
      .onReady(() => {
        this.ready = true;
        this.draw();
      })
  }
}
