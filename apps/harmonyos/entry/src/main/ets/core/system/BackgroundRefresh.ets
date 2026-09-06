// 后台刷新（对齐 iOS BGAppRefreshTask / Android WorkManager 保活）：
//   1. Token 保活——为每个持久化身份跑跨进程闸门刷新（TokenRefresher），会话永不因久不打开而过期。
//   2. 卡片刷新——用（已刷新的）token 重新拉 zone + 汇总 24h 请求，重写快照并推给每张已放置卡片。
// 关键：本函数会在**独立进程**（WorkScheduler 扩展）执行，不能依赖前台 AuthManager 单例的内存态——
// 一切从 TokenStore / AppPrefs 读取。为让共享 apiClient 可用，先 attach context 再 bootstrap authManager。
import { common } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { authManager, AuthSessionMeta } from '../auth/AuthManager';
import { TokenRefresher } from '../auth/TokenRefresher';
import { TokenStore } from '../auth/TokenStore';
import { AppPrefs } from './AppPrefs';
import { GlobalContext } from './GlobalContext';
import { WidgetSnapshot, WidgetSnapshotData } from './WidgetSnapshot';
import { WidgetForms } from './WidgetForms';
import { SkyPhaseColors } from '../design/SkyPhase';
import { formatCount } from '../util/Format';
import { Account, Zone } from '../../models/Models';
import { AccountService } from '../../services/AccountService';
import { ZoneService } from '../../services/ZoneService';
import { AnalyticsService } from '../../services/AnalyticsService';
import { TrafficDataPoint } from '../../models/AnalyticsModels';

const DOMAIN = 0x0001;
const TAG = 'BackgroundRefresh';
const KEY_SESSIONS = 'auth_sessions';
const KEY_CURRENT = 'auth_current_session';

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

/// 读持久化的身份列表（后台进程不经 authManager 内存态）
async function loadSessions(): Promise<AuthSessionMeta[]> {
  try {
    const raw = await AppPrefs.getString(KEY_SESSIONS, '[]');
    const metas = JSON.parse(raw) as AuthSessionMeta[];
    return Array.isArray(metas) ? metas : [];
  } catch (e) {
    return [];
  }
}

/// 复制 DashboardView 的跨 zone 24h 请求汇总（并发、容错单 zone 失败、按钟点合并出山脊序列）
async function aggregateToday(analytics: AnalyticsService, zones: Zone[]): Promise<WidgetSnapshotData | null> {
  const jobs: Promise<TrafficDataPoint[]>[] = zones.map((z: Zone) =>
    analytics.zoneTraffic(z.id, '24h').catch(() => [] as TrafficDataPoint[]));
  const all = await Promise.all(jobs);
  const byHour: Map<string, number> = new Map();
  let total = 0;
  for (const points of all) {
    for (const p of points) {
      byHour.set(p.label, (byHour.get(p.label) ?? 0) + p.requests);
      total += p.requests;
    }
  }
  const labels = Array.from(byHour.keys()).sort();
  const series: number[] = [];
  for (const l of labels) {
    series.push(byHour.get(l) ?? 0);
  }
  const activeCount = zones.filter((z: Zone) => z.status === 'active').length;
  const phaseNum: number = SkyPhaseColors.current(false, new Date().getHours()) as number;
  const data: WidgetSnapshotData = {
    label: '',
    requests: zones.length === 0 ? '0' : formatCount(total),
    zones: `${zones.length}`,
    active: `${activeCount}`,
    series: series.join(','),
    phase: phaseNum,
    updatedAt: new Date().toISOString(),
  };
  return data;
}

/// 向所有已放置卡片推最新快照
async function pushToForms(context: common.Context, data: WidgetSnapshotData): Promise<void> {
  const ids = await WidgetForms.list(context);
  for (const formId of ids) {
    try {
      await formProvider.updateForm(formId, bindingFrom(data));
    } catch (e) {
      // 该 formId 可能已被移除，忽略
    }
  }
}

/// 后台刷新主入口（前台可复用、后台 WorkScheduler / onUpdateForm 调用）
export async function runBackgroundRefresh(context: common.Context): Promise<void> {
  // 让共享模块（AppPrefs / RefreshGate / apiClient 经 authManager）用本进程 context
  AppPrefs.attach(context);
  GlobalContext.setBase(context);

  // 1) Token 保活：逐身份跑跨进程闸门刷新（先刷新，token 落盘后 authManager.bootstrap 才读到新值）
  const sessions = await loadSessions();
  if (sessions.length === 0) {
    return;
  }
  for (const meta of sessions) {
    try {
      await TokenRefresher.refreshSessionIfNeeded(context, meta.id);
    } catch (e) {
      // 不阻塞其它身份
      hilog.warn(DOMAIN, TAG, 'refresh session %{public}s failed: %{public}s', meta.id, (e as Error).message ?? '');
    }
  }

  // 2) 让 authManager 从持久层（现已刷新）恢复内存态，供 apiClient 注入 token
  await authManager.bootstrap();
  const savedCurrent = await AppPrefs.getString(KEY_CURRENT, '');
  const alive = authManager.sessions;
  if (alive.length === 0) {
    // 全部身份判死：写空快照兜底并推卡
    return;
  }
  const currentId = alive.some((s: AuthSessionMeta) => s.id === savedCurrent) ? savedCurrent : alive[0].id;
  await authManager.switchSession(currentId);

  // 3) 拉取选中账号的 zone + 汇总 24h，重写快照 + 推卡
  try {
    const accountService = new AccountService();
    const accounts: Account[] = await accountService.fetchAccounts();
    if (accounts.length === 0) {
      return;
    }
    const savedAccount = await AppPrefs.getString(`selected_account_${currentId}`, '');
    const chosen = accounts.find((a: Account) => a.id === savedAccount) ?? accounts[0];

    const zoneService = new ZoneService();
    const zones: Zone[] = await zoneService.fetchZones(chosen.id);

    const analytics = new AnalyticsService();
    const data = await aggregateToday(analytics, zones);
    if (data) {
      data.label = chosen.name !== '' ? chosen.name : authManager.currentLabel();
      await WidgetSnapshot.write(context, data);
      await pushToForms(context, data);
    }
  } catch (e) {
    // 网络/授权失败不影响 token 保活成果；卡片下次 onUpdateForm 再读快照
    hilog.warn(DOMAIN, TAG, 'widget refresh failed: %{public}s', (e as Error).message ?? '');
  }
}
