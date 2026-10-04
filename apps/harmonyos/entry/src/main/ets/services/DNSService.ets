// DNS Service：/zones/{zone_id}/dns_records 增删改查
import { DNSRecord, DNSRecordPayload } from '../models/Models';
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

export class DNSService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  /// include_shadow_metadata：附带 meta.shadowed_by / shadowed_records_count（被 NS 委派遮蔽的记录）
  fetchRecords(zoneId: string): Promise<DNSRecord[]> {
    return this.client.getList<DNSRecord>(`/zones/${zoneId}/dns_records`, {
      'per_page': '100',
      'include_shadow_metadata': 'true',
    } as Record<string, string>);
  }

  createRecord(zoneId: string, payload: DNSRecordPayload): Promise<DNSRecord> {
    return this.client.postObject<DNSRecord>(`/zones/${zoneId}/dns_records`, payload);
  }

  updateRecord(zoneId: string, recordId: string, payload: DNSRecordPayload): Promise<DNSRecord> {
    return this.client.putObject<DNSRecord>(`/zones/${zoneId}/dns_records/${recordId}`, payload);
  }

  deleteRecord(zoneId: string, recordId: string): Promise<void> {
    return this.client.delete(`/zones/${zoneId}/dns_records/${recordId}`);
  }
}
