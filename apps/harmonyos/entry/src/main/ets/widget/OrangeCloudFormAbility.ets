// 服务卡片 FormExtensionAbility：卡片新增/刷新时读共享快照，喂给 ArkTS 卡片页。
// 卡片本身不做 OAuth（跑在独立进程），渲染主 App / 后台刷新写好的账号总览快照。
// onUpdateForm 会先做一次「节流的」后台刷新（token 保活 + 拉数据），再读快照，
// 让 30 分钟系统刷新周期也能带来新鲜数据，而非只回放旧快照。
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { WidgetSnapshot, WidgetSnapshotData } from '../core/system/WidgetSnapshot';
import { WidgetForms } from '../core/system/WidgetForms';
import { runBackgroundRefresh } from '../core/system/BackgroundRefresh';

/// onUpdateForm 后台刷新节流：两次刷新间隔至少 25 分钟（避免过度拉取 / 触发限流）
const REFRESH_THROTTLE_MS = 25 * 60 * 1000;
const THROTTLE_STORE = 'oc_widget_forms';
const THROTTLE_KEY = 'lastBgRefreshMs';

interface FormPayload {
  label: string;
  requests: string;
  zones: string;
  active: string;
  series: string;
  phase: number;
}

function bindingFrom(data: WidgetSnapshotData): formBindingData.FormBindingData {
  const payload: FormPayload = {
    label: data.label,
    requests: data.requests,
    zones: data.zones,
    active: data.active,
    series: data.series,
    phase: data.phase,
  };
  return formBindingData.createFormBindingData(payload);
}

export default class OrangeCloudFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const params = want.parameters as Record<string, Object> | undefined;
    const formId = params ? params[formInfo.FormParam.IDENTITY_KEY] as string : undefined;
    if (formId) {
      WidgetForms.add(this.context, formId).catch(() => {
      });
      WidgetSnapshot.read(this.context).then((data: WidgetSnapshotData) => {
        formProvider.updateForm(formId, bindingFrom(data)).catch(() => {
        });
      }).catch(() => {
      });
    }
    // 同步返回占位绑定，异步 updateForm 补真数据
    const placeholder: FormPayload = { label: '加载中…', requests: '—', zones: '—', active: '—', series: '', phase: 1 };
    return formBindingData.createFormBindingData(placeholder);
  }

  onUpdateForm(formId: string): void {
    this.maybeRefresh()
      .then(() => WidgetSnapshot.read(this.context))
      .then((data: WidgetSnapshotData) => {
        return formProvider.updateForm(formId, bindingFrom(data));
      })
      .catch(() => {
      });
  }

  /// 节流的后台刷新：距上次刷新超过阈值才真正拉取（否则直接回放快照）
  private async maybeRefresh(): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, THROTTLE_STORE);
      const last = await store.get(THROTTLE_KEY, 0) as number;
      const now = Date.now();
      if (now - last < REFRESH_THROTTLE_MS) {
        return;
      }
      // 先占位写入时间戳，避免并发重复拉取
      await store.put(THROTTLE_KEY, now);
      await store.flush();
      await runBackgroundRefresh(this.context);
    } catch (e) {
      // 刷新失败不阻塞快照回放
    }
  }

  onRemoveForm(formId: string): void {
    WidgetForms.remove(this.context, formId).catch(() => {
    });
  }

  onCastToNormalForm(formId: string): void {
  }
}
