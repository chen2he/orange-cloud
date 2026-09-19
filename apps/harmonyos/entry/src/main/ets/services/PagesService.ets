// Cloudflare Pages：项目 / 部署 / 自定义域名（端点对齐 iOS PagesService.swift，读 page.read，写 page.write）。
// 基础模型在 models/WorkerModels；详情态扩展字段（stages / build_config / env_vars 等）集中定义在本文件。
import { CFListEnvelope, CFObjectEnvelope } from '../models/Models';
import { PagesAssetUpload, PagesDeployment, PagesDomain, PagesProject } from '../models/WorkerModels';
import { ApiError, CFApiClient, MultipartPart, apiClient } from '../core/network/CFApiClient';

interface PagesCreateRequest {
  name: string;
  production_branch: string;
}

interface PagesDomainAddRequest {
  name: string;
}

// ---- 部署详情扩展 ----

/// 构建阶段（queued / initialize / clone_repo / build / deploy）
export interface PagesStage {
  name?: string;
  status?: string; // success 或 idle 或 active 或 failure 或 canceled
  started_on?: string;
  ended_on?: string;
}

export interface PagesTriggerMetadata {
  branch?: string;
  commit_hash?: string;
  commit_message?: string;
}

export interface PagesDeploymentTrigger {
  type?: string;
  metadata?: PagesTriggerMetadata;
}

/// 部署详情（列表模型 + 阶段时间线 + 触发信息）
export interface PagesDeploymentDetail extends PagesDeployment {
  modified_on?: string;
  is_skipped?: boolean;
  stages?: PagesStage[];
  deployment_trigger?: PagesDeploymentTrigger;
}

// ---- 项目详情扩展 ----

/// 构建配置（PATCH 时仅带要改的字段，顶层合并）
export interface PagesBuildConfigPayload {
  build_command?: string;
  destination_dir?: string;
  root_dir?: string;
}

/// 环境变量。注意：GET 项目时 secret_text 类型的 value 为 null（已脱敏），故 App 内只读展示。
export interface PagesEnvVar {
  type?: string; // plain_text 或 secret_text
  value?: string;
}

export interface PagesEnvConfig {
  env_vars?: Record<string, PagesEnvVar>;
}

export interface PagesDeploymentConfigs {
  production?: PagesEnvConfig;
  preview?: PagesEnvConfig;
}

export interface PagesProjectDetail extends PagesProject {
  build_config?: PagesBuildConfigPayload;
  deployment_configs?: PagesDeploymentConfigs;
}

/// PATCH 项目请求体：仅传要改的字段（环境变量脱敏风险，App 内不写）
export interface PagesProjectUpdate {
  build_config?: PagesBuildConfigPayload;
  production_branch?: string;
}

export class PagesService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  listProjects(accountId: string): Promise<PagesProject[]> {
    return this.client.getList<PagesProject>(`/accounts/${accountId}/pages/projects`);
  }

  getProject(accountId: string, projectName: string): Promise<PagesProjectDetail> {
    return this.client.getObject<PagesProjectDetail>(`/accounts/${accountId}/pages/projects/${projectName}`);
  }

  createProject(accountId: string, name: string, productionBranch: string): Promise<PagesProject> {
    const body: PagesCreateRequest = { name: name, production_branch: productionBranch };
    return this.client.postObject<PagesProject>(`/accounts/${accountId}/pages/projects`, body);
  }

  /// PATCH 项目（构建配置 / 生产分支）。仅传要改的字段，顶层合并。
  updateProject(accountId: string, projectName: string, update: PagesProjectUpdate): Promise<PagesProjectDetail> {
    return this.client.patchObject<PagesProjectDetail>(`/accounts/${accountId}/pages/projects/${projectName}`, update);
  }

  deleteProject(accountId: string, projectName: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/pages/projects/${projectName}`);
  }

  /// 部署列表（CF Pages 列表端点只认 page 参数，默认每页 25；对齐 iOS 逐页取、最多 10 页收尾）
  async listDeployments(accountId: string, projectName: string): Promise<PagesDeployment[]> {
    const all: PagesDeployment[] = [];
    let page = 1;
    while (true) {
      const envelope = await this.client.getListEnvelope<PagesDeployment>(
        `/accounts/${accountId}/pages/projects/${projectName}/deployments`, {
        'page': `${page}`,
      } as Record<string, string>);
      const items = envelope.result ?? [];
      for (const item of items) {
        all.push(item);
      }
      const totalPages = envelope.result_info?.total_pages ?? 1;
      if (page >= totalPages || items.length === 0 || page >= 10) {
        break;
      }
      page += 1;
    }
    return all;
  }

  getDeployment(accountId: string, projectName: string, deploymentId: string): Promise<PagesDeploymentDetail> {
    return this.client.getObject<PagesDeploymentDetail>(
      `/accounts/${accountId}/pages/projects/${projectName}/deployments/${deploymentId}`);
  }

  /// 重试部署（用相同的源重新构建并部署）
  retryDeployment(accountId: string, projectName: string, deploymentId: string): Promise<PagesDeploymentDetail> {
    return this.client.postObject<PagesDeploymentDetail>(
      `/accounts/${accountId}/pages/projects/${projectName}/deployments/${deploymentId}/retry`,
      {} as Record<string, string>);
  }

  /// 回滚到某次部署，使其重新成为生产环境当前版本（仅生产环境部署可用）
  rollbackDeployment(accountId: string, projectName: string, deploymentId: string): Promise<PagesDeploymentDetail> {
    return this.client.postObject<PagesDeploymentDetail>(
      `/accounts/${accountId}/pages/projects/${projectName}/deployments/${deploymentId}/rollback`,
      {} as Record<string, string>);
  }

  /// 删除部署（不可撤销；不能删除当前生效的部署）
  deleteDeployment(accountId: string, projectName: string, deploymentId: string): Promise<void> {
    return this.client.delete(
      `/accounts/${accountId}/pages/projects/${projectName}/deployments/${deploymentId}`);
  }

  /// 换取资源上传用的短期 JWT（后续三个 /pages/assets/* 端点都用它，不用账号 token）
  async uploadToken(accountId: string, projectName: string): Promise<string> {
    interface UploadToken {
      jwt: string;
    }
    const result = await this.client.getObject<UploadToken>(
      `/accounts/${accountId}/pages/projects/${projectName}/upload-token`);
    return result.jwt;
  }

  /// 问服务端缺哪些资源哈希——只有缺的才需要真正上传，重复部署几乎不传东西
  async checkMissingAssets(jwt: string, hashes: string[]): Promise<string[]> {
    interface HashesBody {
      hashes: string[];
    }
    const body: HashesBody = { hashes: hashes };
    const text = await this.client.bearerPostJson('/pages/assets/check-missing', jwt, body);
    const envelope = JSON.parse(text) as CFListEnvelope<string>;
    if (!envelope.success) {
      throw new ApiError('查询缺失资源失败');
    }
    return envelope.result ?? [];
  }

  /// 上传一批资源（value 为 base64）
  async uploadAssets(jwt: string, payloads: PagesAssetUpload[]): Promise<void> {
    const text = await this.client.bearerPostJson('/pages/assets/upload', jwt, payloads);
    const envelope = JSON.parse(text) as CFObjectEnvelope<object>;
    if (!envelope.success) {
      throw new ApiError('上传资源失败');
    }
  }

  /// 关联（保活）本次部署涉及的全部哈希——漏掉这步，未变更的旧资源可能被回收
  async upsertHashes(jwt: string, hashes: string[]): Promise<void> {
    interface HashesBody {
      hashes: string[];
    }
    const body: HashesBody = { hashes: hashes };
    const text = await this.client.bearerPostJson('/pages/assets/upsert-hashes', jwt, body);
    const envelope = JSON.parse(text) as CFObjectEnvelope<object>;
    if (!envelope.success) {
      throw new ApiError('关联资源失败');
    }
  }

  /// 带 manifest 建部署（manifest 是「/路径 → 资源哈希」的 JSON，走 multipart 字段）
  createDeployment(accountId: string, projectName: string,
    manifest: Record<string, string>): Promise<PagesDeployment> {
    const parts: MultipartPart[] = [
      { name: 'manifest', data: JSON.stringify(manifest) },
    ];
    return this.client.postMultipartObject<PagesDeployment>(
      `/accounts/${accountId}/pages/projects/${projectName}/deployments`, parts);
  }

  listDomains(accountId: string, projectName: string): Promise<PagesDomain[]> {
    return this.client.getList<PagesDomain>(`/accounts/${accountId}/pages/projects/${projectName}/domains`);
  }

  addDomain(accountId: string, projectName: string, name: string): Promise<PagesDomain> {
    const body: PagesDomainAddRequest = { name: name };
    return this.client.postObject<PagesDomain>(`/accounts/${accountId}/pages/projects/${projectName}/domains`, body);
  }

  /// 重新触发域名校验（PATCH 空体），用于 pending / 校验失败后重试
  async retryDomain(accountId: string, projectName: string, domainName: string): Promise<void> {
    // ArkTS 不接受裸对象字面量，空体也要有具名类型
    interface EmptyBody {
    }
    const body: EmptyBody = {};
    await this.client.patchObject<object>(
      `/accounts/${accountId}/pages/projects/${projectName}/domains/${domainName}`, body);
  }

  deleteDomain(accountId: string, projectName: string, domainName: string): Promise<void> {
    return this.client.delete(`/accounts/${accountId}/pages/projects/${projectName}/domains/${domainName}`);
  }
}
