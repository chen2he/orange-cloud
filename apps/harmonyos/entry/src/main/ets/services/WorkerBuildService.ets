// Workers Builds —— Worker 的 CI 构建记录（workers-ci.read / .write）。
//
// 注意 status 与 outcome 是两个维度：status 只到 stopped 为止
// （queued / initializing / running / stopped），成功还是失败要看 build_outcome。
// 只看 status 会把「失败」显示成「已结束」。
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

export interface BuildTriggerMetadata {
  author?: string;
  branch?: string;
  commit_hash?: string;
  build_command?: string;
  build_trigger_source?: string;
}

export interface WorkerBuild {
  build_uuid: string;
  status?: string;             // queued / initializing / running / stopped
  build_outcome?: string;      // success / fail / skipped / cancelled / terminated
  created_on?: string;
  modified_on?: string;
  build_trigger_metadata?: BuildTriggerMetadata;
}

export interface BuildLogLine {
  line?: string;
  ts?: string;
}

interface BuildLogsPage {
  lines?: BuildLogLine[];
}

interface EmptyBody {
}

/// 把 status + outcome 合成一个用户能看懂的状态
export function buildStateLabel(b: WorkerBuild): string {
  if (b.status !== 'stopped') {
    if (b.status === 'queued') {
      return '排队中';
    }
    if (b.status === 'initializing' || b.status === 'running') {
      return '构建中';
    }
    return '未知';
  }
  if (b.build_outcome === 'success') {
    return '成功';
  }
  if (b.build_outcome === 'fail' || b.build_outcome === 'terminated') {
    return '失败';
  }
  if (b.build_outcome === 'cancelled') {
    return '已取消';
  }
  if (b.build_outcome === 'skipped') {
    return '已跳过';
  }
  return '未知';
}

export function buildStateColor(b: WorkerBuild): string {
  const label = buildStateLabel(b);
  if (label === '成功') {
    return '#2E7D32';
  }
  if (label === '失败') {
    return '#C62828';
  }
  if (label === '排队中' || label === '构建中') {
    return '#EF6C00';
  }
  return '#757575';
}

export function isBuildRunning(b: WorkerBuild): boolean {
  const label = buildStateLabel(b);
  return label === '排队中' || label === '构建中';
}

export class WorkerBuildService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  /// 未接 CI 的 Worker 会 404，调用方按「没有构建」处理
  builds(accountId: string, scriptId: string): Promise<WorkerBuild[]> {
    return this.client.getList<WorkerBuild>(`/accounts/${accountId}/builds/workers/${scriptId}/builds`, {
      'per_page': '20',
    } as Record<string, string>);
  }

  async logs(accountId: string, buildUuid: string): Promise<BuildLogLine[]> {
    const page = await this.client.getObject<BuildLogsPage>(`/accounts/${accountId}/builds/builds/${buildUuid}/logs`);
    return page.lines ?? [];
  }

  /// 取消进行中的构建（workers-ci.write）
  cancel(accountId: string, buildUuid: string): Promise<WorkerBuild> {
    const body: EmptyBody = {};
    return this.client.putObject<WorkerBuild>(`/accounts/${accountId}/builds/builds/${buildUuid}/cancel`, body);
  }
}
