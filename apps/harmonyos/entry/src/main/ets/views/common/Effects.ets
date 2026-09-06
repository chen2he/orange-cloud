// HDS 沉浸视效（UI Design Kit）：按压交互阴影与点光源。
// 官方说明：这些效果**只在真机渲染**，模拟器不支持（点光源 / 流光 / 按压阴影 / 光感材质），
// 但接口本身在模拟器上调用安全，只是看不到效果，因此可以无条件挂载。
import { hdsEffect, hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { uiEffect } from '@kit.ArkGraphics2D';

/// 按压交互阴影：系统按压时自动计算背景色变化，给可点按的卡片用。
export const OC_PRESS_EFFECT: uiEffect.VisualEffect = new hdsEffect.HdsEffectBuilder()
  .pressShadow(hdsEffect.PressShadowType.BLEND_GRADIENT)
  .buildEffect();

/// 柔光点光源（描边受光）：克制使用——只给主 CTA 与付费墙这类关键元素，避免整屏发光。
export const OC_SOFT_LIGHT: uiEffect.VisualEffect = new hdsEffect.HdsEffectBuilder()
  .pointLight({
    sourceType: hdsEffect.PointLightSourceType.SOFT,
    illuminatedType: hdsEffect.PointLightIlluminatedType.DEFAULT_FEATHERING_BORDER,
  })
  .buildEffect();


/// 沉浸光感材质参数（标题栏 / 页签栏共用）。
/// hdsMaterial 自 6.1.0(23) 起提供，而工程 compatibleSdkVersion 是 6.0.0(20)，
/// 所以枚举只能在版本满足时才去取值——低版本返回 undefined，组件走默认背景。
export function systemMaterial(): SystemMaterialParams | undefined {
  if (deviceInfo.sdkApiVersion < 23) {
    return undefined;
  }
  return {
    materialType: hdsMaterial.MaterialType.ADAPTIVE,
    materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
  };
}


/// HDS 标题栏（MINI 模式）高度。标题栏浮在内容上层，页面内容需要让出这段高度。
export const OC_TITLE_BAR_INSET: number = 56;
