// Workers Service：脚本列表 / 部署 / 密钥 / 定时触发器 / 子域名 / 自定义域名 / 路由 / tail 会话。
// 对齐 Android WorkerRepository + WorkerTailRepository。
import {
  TailSession,
  WorkerBindingInfo,
  WorkerBindingInput,
  WorkerCustomDomain,
  WorkerDeployment,
  WorkerDeploymentsResult,
  WorkerRoute,
  WorkerSchedule,
  WorkerScript,
  WorkerScriptContent,
  WorkerSecret,
  WorkerSettingsInfo,
  WorkerSubdomain,
} from '../models/WorkerModels';
import { CFApiClient, MultipartPart, apiClient } from '../core/network/CFApiClient';

/// secrets-bulk 请求体：键 = 密钥名，值 = 密钥对象（写）或 null（删）
interface WorkerSecretsBulkPatch {
  secrets: Record<string, WorkerSecretInput | null>;
}

interface WorkerSecretInput {
  name: string;
  text: string;
  type: string;
}

interface WorkerScheduleInput {
  cron: string;
}

interface WorkerSchedulesResult {
  schedules: WorkerSchedule[];
}

interface WorkerSubdomainInput {
  enabled: boolean;
}

interface WorkerCustomDomainInput {
  hostname: string;
  service: string;
  zone_id: string;
}

interface WorkerRouteInput {
  pattern: string;
  script: string;
}

interface TailFilters {
  // 空过滤 = 全量
  filters: string[];
}

/// 更新代码时回传的绑定：inherit 只发 { type, name }，按名保留现有绑定
interface WorkerBindingInherit {
  type: string;
  name: string;
}

/// 更新代码的 metadata part（模块脚本发 main_module，service worker 发 body_part）
interface WorkerCodeUpdateMetadata {
  main_module?: string;
  body_part?: string;
  compatibility_date?: string;
  compatibility_flags?: string[];
  bindings: WorkerBindingInherit[];
}

function trimNewlines(text: string): string {
  let start = 0;
  let end = text.length;
  while (start < end && (text.charAt(start) === '\r' || text.charAt(start) === '\n')) {
    start += 1;
  }
  while (end > start && (text.charAt(end - 1) === '\r' || text.charAt(end - 1) === '\n')) {
    end -= 1;
  }
  return text.substring(start, end);
}

/// 取 Content-Disposition 里形如 key="x" 的值
function headerQuoted(headers: string, key: string): string | undefined {
  const marker = `${key}="`;
  const idx = headers.indexOf(marker);
  if (idx < 0) {
    return undefined;
  }
  const start = idx + marker.length;
  const end = headers.indexOf('"', start);
  if (end < 0) {
    return undefined;
  }
  return headers.substring(start, end);
}

function contentTypeOf(headers: string): string | undefined {
  const lines = headers.split('\n');
  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.toLowerCase().startsWith('content-type:')) {
      return trimmed.substring(13).trim();
    }
  }
  return undefined;
}

/// 解析 content 端点响应：模块脚本返回 multipart（正文首行即分隔符，客户端拿不到响应头，
/// 从正文首行还原 boundary）；service worker 返回裸 JS。仅单模块可安全往返编辑。
function parseWorkerContent(raw: string): WorkerScriptContent {
  if (!raw.startsWith('--')) {
    return {
      body: raw,
      moduleName: 'worker.js',
      contentType: 'application/javascript',
      isModule: false,
      editable: true,
      moduleCount: 1,
    } as WorkerScriptContent;
  }
  let firstLineEnd = raw.indexOf('\r\n');
  if (firstLineEnd < 0) {
    firstLineEnd = raw.indexOf('\n');
  }
  const delimiter = firstLineEnd > 0 ? raw.substring(0, firstLineEnd) : raw;
  const names: string[] = [];
  const types: string[] = [];
  const bodies: string[] = [];
  const chunks = raw.split(delimiter);
  for (const chunk of chunks) {
    const part = trimNewlines(chunk);
    if (part === '' || part === '--') {
      continue;
    }
    let sep = part.indexOf('\r\n\r\n');
    let sepLen = 4;
    if (sep < 0) {
      sep = part.indexOf('\n\n');
      sepLen = 2;
    }
    if (sep < 0) {
      continue;
    }
    const headers = part.substring(0, sep);
    const body = part.substring(sep + sepLen);
    names.push(headerQuoted(headers, 'name') ?? headerQuoted(headers, 'filename') ?? 'worker.js');
    types.push(contentTypeOf(headers) ?? 'application/javascript+module');
    bodies.push(body);
  }
  if (bodies.length === 0) {
    // 解析不出模块时按原文只读展示，避免误编辑丢内容
    return {
      body: raw,
      moduleName: 'worker.js',
      contentType: 'application/javascript',
      isModule: false,
      editable: false,
      moduleCount: 0,
    } as WorkerScriptContent;
  }
  return {
    body: bodies[0],
    moduleName: names[0],
    contentType: types[0],
    isModule: true,
    editable: bodies.length === 1,
    moduleCount: bodies.length,
  } as WorkerScriptContent;
}

export class WorkerService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  listScripts(accountId: string): Promise<WorkerScript[]> {
    return this.client.getList<WorkerScript>(`/accounts/${accountId}/workers/scripts`);
  }

  /// 取单个脚本的元信息。Workers 没有「单脚本 metadata」端点
  /// （GET scripts/{name} 返回的是脚本正文），故从列表里按 id 找。
  async findScript(accountId: string, name: string): Promise<WorkerScript | null> {
    const scripts = await this.listScripts(accountId);
    const match = scripts.find((s: WorkerScript) => s.id === name);
    return match ?? null;
  }

  /// 上传/部署脚本（multipart：metadata main_module + JS 模块）
  async deploy(accountId: string, name: string, code: string, compatibilityDate: string): Promise<void> {
    interface DeployMetadata {
      main_module: string;
      compatibility_date: string;
    }
    const metadata: DeployMetadata = { main_module: 'worker.js', compatibility_date: compatibilityDate };
    const parts: MultipartPart[] = [
      { name: 'worker.js', filename: 'worker.js', contentType: 'application/javascript+module', data: code },
      { name: 'metadata', contentType: 'application/json', data: JSON.stringify(metadata) },
    ];
    await this.client.putMultipartObject<object>(`/accounts/${accountId}/workers/scripts/${name}`, parts);
  }

  async deleteScript(accountId: string, name: string): Promise<void> {
    await this.client.delete(`/accounts/${accountId}/workers/scripts/${name}`);
  }

  /// 部署历史（result.deployments，首项为当前活跃部署）
  async listDeployments(accountId: string, scriptName: string): Promise<WorkerDeployment[]> {
    const result = await this.client.getObject<WorkerDeploymentsResult>(
      `/accounts/${accountId}/workers/scripts/${scriptName}/deployments`);
    return result.deployments ?? [];
  }

  /// 删除某次部署（当前活跃部署 Cloudflare 会拒绝删除）
  deleteDeployment(accountId: string, scriptName: string, deploymentId: string): Promise<void> {
    return this.client.delete(
      `/accounts/${accountId}/workers/scripts/${scriptName}/deployments/${deploymentId}`);
  }

  /// 脚本源码：必须走 content/v2——v1 的 content 端点对 OAuth 认证返回 405 cf=10405
  /// （对齐 iOS WorkerService.content，issue #55 真机实测）。
  async content(accountId: string, scriptName: string): Promise<WorkerScriptContent> {
    const raw = await this.client.getRaw(`/accounts/${accountId}/workers/scripts/${scriptName}/content/v2`);
    return parseWorkerContent(raw);
  }

  /// 脚本设置（绑定 + 兼容性日期/标志），更新代码前拉取以便按名 inherit 保留绑定
  scriptSettings(accountId: string, scriptName: string): Promise<WorkerSettingsInfo> {
    return this.client.getObject<WorkerSettingsInfo>(
      `/accounts/${accountId}/workers/scripts/${scriptName}/settings`);
  }

  /// 安全更新代码：仅替换正文；现有绑定整组按名 inherit（密钥值读不到也能保住），
  /// 兼容性日期/标志沿用旧值；带 bindings_inherit=strict，缺绑定直接报错而非静默丢弃。
  async updateCode(accountId: string, scriptName: string, current: WorkerScriptContent, newCode: string,
    scriptSettings: WorkerSettingsInfo): Promise<void> {
    const bindings: WorkerBindingInherit[] = (scriptSettings.bindings ?? [])
      .filter((b: WorkerBindingInfo) => (b.name ?? '') !== '')
      .map((b: WorkerBindingInfo): WorkerBindingInherit => ({ type: 'inherit', name: b.name ?? '' }));
    const metadata: WorkerCodeUpdateMetadata = {
      main_module: current.isModule ? current.moduleName : undefined,
      body_part: current.isModule ? undefined : current.moduleName,
      compatibility_date: scriptSettings.compatibility_date,
      compatibility_flags: scriptSettings.compatibility_flags,
      bindings: bindings,
    };
    const parts: MultipartPart[] = [
      { name: current.moduleName, filename: current.moduleName, contentType: current.contentType, data: newCode },
      { name: 'metadata', contentType: 'application/json', data: JSON.stringify(metadata) },
    ];
    await this.client.putMultipartObject<object>(
      `/accounts/${accountId}/workers/scripts/${scriptName}?bindings_inherit=strict`, parts);
  }

  /// 改绑定：整组回写（变更项为实体、其余 inherit），端点是 **multipart PATCH**，
  /// JSON 放在名为 settings 的 part 里——不是普通 JSON PATCH（对齐 iOS patchSettings）。
  async patchSettings(accountId: string, scriptName: string, bindings: WorkerBindingInput[],
    current: WorkerSettingsInfo): Promise<void> {
    interface SettingsPatch {
      bindings: WorkerBindingInput[];
      compatibility_date?: string;
      compatibility_flags?: string[];
    }
    const patch: SettingsPatch = {
      bindings: bindings,
      compatibility_date: current.compatibility_date,
      compatibility_flags: current.compatibility_flags,
    };
    const parts: MultipartPart[] = [
      { name: 'settings', contentType: 'application/json', data: JSON.stringify(patch) },
    ];
    await this.client.patchMultipart(
      `/accounts/${accountId}/workers/scripts/${scriptName}/settings`, parts);
  }

  listSecrets(accountId: string, scriptName: string): Promise<WorkerSecret[]> {
    return this.client.getList<WorkerSecret>(`/accounts/${accountId}/workers/scripts/${scriptName}/secrets`);
  }

  async putSecret(accountId: string, scriptName: string, name: string, text: string): Promise<void> {
    const body: WorkerSecretInput = { name: name, text: text, type: 'secret_text' };
    await this.client.putObject<object>(`/accounts/${accountId}/workers/scripts/${scriptName}/secrets`, body);
  }

  deleteSecret(accountId: string, scriptName: string, name: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/workers/scripts/${scriptName}/secrets/${name}`);
  }

  /// 批量写密钥（secrets-bulk，2026-06 新端点）：单次 PATCH 原子生效，单次上限 100 项。
  /// JSON Merge Patch 语义——对象 = 新建/覆盖，null = 删除，未提及的密钥不受影响。
  async bulkPatchSecrets(accountId: string, scriptName: string,
    names: string[], values: string[], deletes: string[] = []): Promise<void> {
    const secrets: Record<string, WorkerSecretInput | null> = {};
    for (let i = 0; i < names.length; i++) {
      secrets[names[i]] = { name: names[i], text: values[i], type: 'secret_text' };
    }
    for (const name of deletes) {
      secrets[name] = null;
    }
    const body: WorkerSecretsBulkPatch = { secrets: secrets };
    await this.client.patchObject<object>(
      `/accounts/${accountId}/workers/scripts/${scriptName}/secrets-bulk`, body);
  }

  async schedules(accountId: string, scriptName: string): Promise<WorkerSchedule[]> {
    const result = await this.client.getObject<WorkerSchedulesResult>(
      `/accounts/${accountId}/workers/scripts/${scriptName}/schedules`);
    return result.schedules ?? [];
  }

  async putSchedules(accountId: string, scriptName: string, crons: string[]): Promise<void> {
    const body: WorkerScheduleInput[] = crons.map((c: string): WorkerScheduleInput => ({ cron: c }));
    await this.client.putObject<object>(`/accounts/${accountId}/workers/scripts/${scriptName}/schedules`, body);
  }

  async subdomain(accountId: string, scriptName: string): Promise<boolean> {
    try {
      const result = await this.client.getObject<WorkerSubdomain>(
        `/accounts/${accountId}/workers/scripts/${scriptName}/subdomain`);
      return result.enabled === true;
    } catch (e) {
      return false;
    }
  }

  async setSubdomain(accountId: string, scriptName: string, enabled: boolean): Promise<void> {
    const body: WorkerSubdomainInput = { enabled: enabled };
    await this.client.postObject<object>(`/accounts/${accountId}/workers/scripts/${scriptName}/subdomain`, body);
  }

  customDomains(accountId: string, scriptName: string): Promise<WorkerCustomDomain[]> {
    return this.client.getList<WorkerCustomDomain>(`/accounts/${accountId}/workers/domains`, {
      'service': scriptName,
    } as Record<string, string>);
  }

  async attachDomain(accountId: string, scriptName: string, hostname: string, zoneId: string): Promise<void> {
    const body: WorkerCustomDomainInput = { hostname: hostname, service: scriptName, zone_id: zoneId };
    await this.client.putObject<object>(`/accounts/${accountId}/workers/domains`, body);
  }

  deleteDomain(accountId: string, domainId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/workers/domains/${domainId}`);
  }

  routes(zoneId: string): Promise<WorkerRoute[]> {
    return this.client.getList<WorkerRoute>(`/zones/${zoneId}/workers/routes`);
  }

  async createRoute(zoneId: string, pattern: string, scriptName: string): Promise<void> {
    const body: WorkerRouteInput = { pattern: pattern, script: scriptName };
    await this.client.postObject<object>(`/zones/${zoneId}/workers/routes`, body);
  }

  deleteRoute(zoneId: string, routeId: string): Promise<void> {
    return this.client.delete(`/zones/${zoneId}/workers/routes/${routeId}`);
  }

  /// 创建 tail 会话（返回预签名 wss:// URL）
  createTail(accountId: string, scriptName: string): Promise<TailSession> {
    const body: TailFilters = { filters: [] };
    return this.client.postObject<TailSession>(`/accounts/${accountId}/workers/scripts/${scriptName}/tails`, body);
  }

  deleteTail(accountId: string, scriptName: string, tailId: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/workers/scripts/${scriptName}/tails/${tailId}`);
  }
}
