// App 版本号（versionName）——「新功能」弹窗与评分邀请的版本门控都以它为准。
// 取自 bundleManager 的自查询（同步、无权限要求），首次读到后缓存；
// 读失败回退 '1.0.0'（宁可少弹一次，也不能因取不到版本号崩在启动路径上）。
import { bundleManager } from '@kit.AbilityKit';

let cached: string = '';

export function appVersionName(): string {
  if (cached !== '') {
    return cached;
  }
  try {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    cached = info.versionName !== '' ? info.versionName : '1.0.0';
  } catch (e) {
    cached = '1.0.0';
  }
  return cached;
}
