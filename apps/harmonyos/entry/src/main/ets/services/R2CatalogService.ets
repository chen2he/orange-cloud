// R2 Data Catalog —— 把 R2 桶启用为 Apache Iceberg 目录。
// /accounts/{account_id}/r2-catalog[/{bucket_name}]（r2-catalog.read / .write）
//
// 2026-08-03 起计费（$9/百万次目录操作，每月含 100 万次免费），启用是有成本的动作。
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

export interface R2CatalogCompaction {
  state?: string;
  target_size_mb?: string;   // 接口返回的是字符串数字
}

export interface R2CatalogMaintenance {
  compaction?: R2CatalogCompaction;
}

export interface R2Catalog {
  id?: string;
  bucket?: string;
  name?: string;             // 完整目录名，形如 account123_analytics-bucket
  status?: string;
  credential_status?: string;
  maintenance_config?: R2CatalogMaintenance;
}

export interface R2CatalogNamespace {
  name?: string[];           // Iceberg 命名空间分段返回
}

interface NamespaceList {
  namespaces?: R2CatalogNamespace[];
}

/// 表清单外壳（GET .../namespaces/{ns}/tables）
export interface R2CatalogTable {
  name?: string;
  namespace?: string[];
}

interface TableList {
  identifiers?: R2CatalogTable[];
}

interface EmptyBody {
}

export class R2CatalogService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  catalog(accountId: string, bucket: string): Promise<R2Catalog> {
    return this.client.getObject<R2Catalog>(`/accounts/${accountId}/r2-catalog/${bucket}`);
  }

  /// 启用为 Iceberg 目录。**计费动作**，调用方需先确认。
  enable(accountId: string, bucket: string): Promise<R2Catalog> {
    const body: EmptyBody = {};
    return this.client.postObject<R2Catalog>(`/accounts/${accountId}/r2-catalog/${bucket}/enable`, body);
  }

  /// 停用目录。数据保留，只是不再作为 Iceberg 目录对外提供。
  disable(accountId: string, bucket: string): Promise<R2Catalog> {
    const body: EmptyBody = {};
    return this.client.postObject<R2Catalog>(`/accounts/${accountId}/r2-catalog/${bucket}/disable`, body);
  }

  async namespaces(accountId: string, bucket: string): Promise<R2CatalogNamespace[]> {
    const result =
      await this.client.getObject<NamespaceList>(`/accounts/${accountId}/r2-catalog/${bucket}/namespaces`,
        { 'page_size': '100' } as Record<string, string>);
    return result.namespaces ?? [];
  }

  /// 某命名空间下的表清单（嵌套命名空间按 Iceberg 惯例以 . 连接进路径）
  async tables(accountId: string, bucket: string, namespace: string): Promise<R2CatalogTable[]> {
    const result = await this.client.getObject<TableList>(
      `/accounts/${accountId}/r2-catalog/${bucket}/namespaces/${namespace}/tables`,
      { 'page_size': '100' } as Record<string, string>);
    return result.identifiers ?? [];
  }
}

/// SQL 里引用表用的前缀（嵌套命名空间以 . 连接）
export function namespaceSqlName(ns: R2CatalogNamespace): string {
  return (ns.name ?? []).join('.');
}

/// SQL 里的完整表引用：namespace.table
export function tableSqlName(table: R2CatalogTable): string {
  const parts = (table.namespace ?? []).concat([table.name ?? '']);
  return parts.filter((p: string) => p !== '').join('.');
}

/// 嵌套命名空间用 · 连接展示
export function namespaceLabel(ns: R2CatalogNamespace): string {
  return (ns.name ?? []).join(' · ');
}
