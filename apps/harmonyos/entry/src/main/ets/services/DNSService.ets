// DNS Service：/zones/{zone_id}/dns_records 增删改查
import { DNSRecord, DNSRecordPayload } from '../models/Models';
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

export class DNSService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  fetchRecords(zoneId: string): Promise<DNSRecord[]> {
    return this.client.getList<DNSRecord>(`/zones/${zoneId}/dns_records`, {
      'per_page': '100',
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
