// 桌面服务卡片快照（对应 iOS App Group / Android widget DataStore）。
// 主 App（Dashboard 算完账号总览后）写入独立 preferences store；
// FormExtensionAbility 用自身 context 读同名 store（同一 bundle 沙箱共享）。
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME = 'oc_widget';

export interface WidgetSnapshotData {
  label: string;
  /// 全账号 24h 请求合计（已缩写，如 1.2M），对齐安卓「天窗」hero
  requests: string;
  zones: string;
  active: string;
  /// 24h 按钟点请求序列，逗号分隔（供「山脊」卡拼地形）
  series: string;
  /// 天色相位序号（0=Dawn 1=Day 2=Dusk 3=Ember 4=Night）
  phase: number;
  updatedAt: string;
}

/// 兜底空快照（未登录 / 未刷新）
export function emptySnapshot(): WidgetSnapshotData {
  return { label: '未登录', requests: '—', zones: '—', active: '—', series: '', phase: 1, updatedAt: '' };
}

export class WidgetSnapshot {
  /// 主 App 侧写入（用 GlobalContext 的 UIAbility context）
  static async write(context: common.Context, data: WidgetSnapshotData): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.put('label', data.label);
      await store.put('requests', data.requests);
      await store.put('zones', data.zones);
      await store.put('active', data.active);
      await store.put('series', data.series);
      await store.put('phase', data.phase);
      await store.put('updatedAt', data.updatedAt);
      await store.flush();
    } catch (e) {
      // 写卡片快照失败不影响主流程
    }
  }

  /// Form 侧读取（用 FormExtensionAbility context）
  static async read(context: common.Context): Promise<WidgetSnapshotData> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const fallback = emptySnapshot();
      return {
        label: await store.get('label', fallback.label) as string,
        requests: await store.get('requests', fallback.requests) as string,
        zones: await store.get('zones', fallback.zones) as string,
        active: await store.get('active', fallback.active) as string,
        series: await store.get('series', fallback.series) as string,
        phase: await store.get('phase', fallback.phase) as number,
        updatedAt: await store.get('updatedAt', fallback.updatedAt) as string,
      };
    } catch (e) {
      return emptySnapshot();
    }
  }
}
