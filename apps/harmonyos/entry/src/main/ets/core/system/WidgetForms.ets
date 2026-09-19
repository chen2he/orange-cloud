// 已放置服务卡片的 formId 台账（供后台刷新枚举后逐个 formProvider.updateForm）。
// FormExtensionAbility 侧在 onAddForm 登记、onRemoveForm 注销；
// 后台 WorkScheduler 进程读取台账，向每张卡推最新快照。
// 存于独立 preferences store（同 bundle 各进程共享沙箱）。
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME = 'oc_widget_forms';
const KEY_IDS = 'formIds';

function parseIds(raw: string): string[] {
  try {
    const arr = JSON.parse(raw) as string[];
    return Array.isArray(arr) ? arr : [];
  } catch (e) {
    return [];
  }
}

export class WidgetForms {
  static async list(context: common.Context): Promise<string[]> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const raw = await store.get(KEY_IDS, '[]') as string;
      return parseIds(raw);
    } catch (e) {
      return [];
    }
  }

  static async add(context: common.Context, formId: string): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const raw = await store.get(KEY_IDS, '[]') as string;
      const ids = parseIds(raw);
      if (!ids.includes(formId)) {
        ids.push(formId);
        await store.put(KEY_IDS, JSON.stringify(ids));
        await store.flush();
      }
    } catch (e) {
    }
  }

  static async remove(context: common.Context, formId: string): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const raw = await store.get(KEY_IDS, '[]') as string;
      const ids = parseIds(raw).filter((id: string) => id !== formId);
      await store.put(KEY_IDS, JSON.stringify(ids));
      await store.flush();
    } catch (e) {
    }
  }
}
