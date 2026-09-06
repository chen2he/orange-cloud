// DNS 记录列表 ViewModel（读 + 增删改）
import { DNSRecord, DNSRecordPayload } from '../models/Models';
import { DNSService } from '../services/DNSService';

@ObservedV2
export class DNSListViewModel {
  @Trace records: DNSRecord[] = [];
  @Trace isLoading: boolean = false;
  @Trace isSaving: boolean = false;
  @Trace error: string = '';
  /// 编辑表单内的提交错误（与列表加载错误分开展示）
  @Trace saveError: string = '';

  private dnsService: DNSService = new DNSService();
  private zoneId: string = '';

  async load(zoneId: string): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.zoneId = zoneId;
    this.isLoading = true;
    this.error = '';
    try {
      this.records = await this.dnsService.fetchRecords(zoneId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  /// 新建或更新（recordId 为空 = 新建）；成功返回 true 供 UI 关闭表单
  async save(recordId: string, payload: DNSRecordPayload): Promise<boolean> {
    if (this.isSaving || this.zoneId === '') {
      return false;
    }
    this.isSaving = true;
    this.saveError = '';
    try {
      if (recordId === '') {
        const created = await this.dnsService.createRecord(this.zoneId, payload);
        this.records = [created, ...this.records];
      } else {
        const updated = await this.dnsService.updateRecord(this.zoneId, recordId, payload);
        this.records = this.records.map((r: DNSRecord) => r.id === recordId ? updated : r);
      }
      return true;
    } catch (e) {
      this.saveError = (e as Error).message ?? '保存失败';
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  /// 删除；成功返回空串，失败回滚列表并返回错误信息（由 UI toast 提示）
  async remove(record: DNSRecord): Promise<string> {
    if (this.zoneId === '') {
      return '';
    }
    // 先乐观移除，失败回滚
    const before = this.records;
    this.records = before.filter((r: DNSRecord) => r.id !== record.id);
    try {
      await this.dnsService.deleteRecord(this.zoneId, record.id);
      return '';
    } catch (e) {
      this.records = before;
      return (e as Error).message ?? '删除失败';
    }
  }
}
