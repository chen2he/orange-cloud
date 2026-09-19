// Zone 列表 ViewModel：按选中账户拉取 Zone，支持搜索过滤与添加域名
import { Zone } from '../models/Models';
import { ZoneService } from '../services/ZoneService';

@ObservedV2
export class ZoneListViewModel {
  @Trace zones: Zone[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  @Trace keyword: string = '';
  @Trace isCreating: boolean = false;
  @Trace createError: string = '';

  private zoneService: ZoneService = new ZoneService();
  private loadedAccountId: string = '';

  filtered(): Zone[] {
    const kw = this.keyword.trim().toLowerCase();
    if (kw === '') {
      return this.zones;
    }
    return this.zones.filter((z: Zone) => z.name.toLowerCase().includes(kw));
  }

  async load(accountId: string, force: boolean = false): Promise<void> {
    if (this.isLoading || accountId === '') {
      return;
    }
    if (!force && this.loadedAccountId === accountId && this.zones.length > 0) {
      return;
    }
    this.isLoading = true;
    this.error = '';
    try {
      const zones = await this.zoneService.fetchZones(accountId);
      zones.sort((a: Zone, b: Zone) => a.name.localeCompare(b.name));
      this.zones = zones;
      this.loadedAccountId = accountId;
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  /// 新建成功后 Cloudflare 分配的名称服务器（引导用户去注册商改 NS）
  @Trace createdZoneName: string = '';
  @Trace createdNameServers: string[] = [];

  /// 添加域名；成功返回 true 并刷新列表，同时留下分配到的 NS 供结果页展示
  async create(accountId: string, name: string): Promise<boolean> {
    if (this.isCreating) {
      return false;
    }
    this.isCreating = true;
    this.createError = '';
    try {
      const created = await this.zoneService.createZone(accountId, name);
      this.createdZoneName = created.name !== '' ? created.name : name;
      this.createdNameServers = created.name_servers ?? [];
      await this.load(accountId, true);
      return true;
    } catch (e) {
      this.createError = (e as Error).message ?? '添加失败';
      return false;
    } finally {
      this.isCreating = false;
    }
  }
}
