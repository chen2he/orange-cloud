// 性能设置：网络开关（brotli/http2/http3/0-RTT/Early Hints/WebSockets/IPv6）
// + 缓存级别 + Always Online + 查询串排序（对齐 Android ZonePerformanceScreen）。
import { ZoneRouteParam } from '../../models/Routes';
import { ZoneSettingsService } from '../../services/ZoneSettingsService';
import { OCLoading, SectionHeader, ToggleRow } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';

interface PerfToggle {
  id: string;
  title: string;
  subtitle: string;
}

const NETWORK_TOGGLES: PerfToggle[] = [
  { id: 'brotli', title: 'Brotli 压缩', subtitle: '更高压缩率的响应压缩' },
  { id: 'http2', title: 'HTTP/2', subtitle: '多路复用连接' },
  { id: 'http3', title: 'HTTP/3 (QUIC)', subtitle: '基于 UDP 的新一代传输' },
  { id: '0rtt', title: '0-RTT 连接恢复', subtitle: '回访连接免握手' },
  { id: 'early_hints', title: 'Early Hints', subtitle: '103 提前提示资源加载' },
  { id: 'websockets', title: 'WebSockets', subtitle: '允许 WS 长连接过境' },
  { id: 'ipv6', title: 'IPv6 兼容', subtitle: '双栈接入' },
];

const EXTRA_TOGGLES: PerfToggle[] = [
  { id: 'always_online', title: 'Always Online', subtitle: '源站宕机时用缓存副本兜底' },
  { id: 'sort_query_string_for_cache', title: '查询串排序缓存', subtitle: '忽略参数顺序提升命中率' },
];

const CACHE_LEVELS: string[] = ['basic', 'simplified', 'aggressive'];

function cacheLevelLabel(raw: string): string {
  if (raw === 'basic') {
    return '基础（无查询串）';
  }
  if (raw === 'simplified') {
    return '简化（忽略查询串）';
  }
  return '积极（含查询串）';
}

@ObservedV2
class PerfVM {
  /// setting id → 当前值（读不到的项不在 map 中）
  @Trace values: Map<string, string> = new Map();
  @Trace isLoading: boolean = false;
  @Trace savingId: string = '';

  private service: ZoneSettingsService = new ZoneSettingsService();

  isOn(id: string): boolean {
    return this.values.get(id) === 'on';
  }

  has(id: string): boolean {
    return this.values.has(id);
  }

  cacheLevel(): string {
    return this.values.get('cache_level') ?? 'aggressive';
  }

  async load(zoneId: string): Promise<void> {
    this.isLoading = true;
    const ids: string[] = NETWORK_TOGGLES.map((t: PerfToggle) => t.id)
      .concat(EXTRA_TOGGLES.map((t: PerfToggle) => t.id))
      .concat(['cache_level']);
    const next: Map<string, string> = new Map();
    for (const id of ids) {
      try {
        next.set(id, await this.service.getSetting(zoneId, id));
      } catch (e) {
        // 套餐不支持或无权限的设置项直接不展示
      }
    }
    this.values = next;
    this.isLoading = false;
  }

  async set(zoneId: string, id: string, value: string): Promise<string> {
    this.savingId = id;
    try {
      const applied = await this.service.setSetting(zoneId, id, value);
      const next: Map<string, string> = new Map(this.values);
      next.set(id, applied);
      this.values = next;
      return '';
    } catch (e) {
      return (e as Error).message ?? '设置失败';
    } finally {
      this.savingId = '';
    }
  }
}

@ComponentV2
export struct ZonePerformancePage {
  @Local vm: PerfVM = new PerfVM();
  @Local zoneId: string = '';
  @Local zoneName: string = '';

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  @Builder
  toggleGroup(title: string, toggles: PerfToggle[]) {
    Column() {
      SectionHeader({ title: title })
      Column() {
        ForEach(toggles.filter((t: PerfToggle) => this.vm.has(t.id)), (toggle: PerfToggle) => {
          ToggleRow({
            title: toggle.title,
            subtitle: toggle.subtitle,
            isOn: this.vm.isOn(toggle.id),
            isEnabled: this.vm.savingId === '',
            onToggle: (on: boolean) => {
              this.vm.set(this.zoneId, toggle.id, on ? 'on' : 'off').then((err: string) => {
                this.toast(err);
              });
            },
          })
        }, (toggle: PerfToggle) => toggle.id)
      }
      .backgroundColor($r('sys.color.comp_background_list_card'))
      .borderRadius(14)
      .border({ width: 0.5, color: $r('sys.color.comp_divider') })
      .clip(true)
      .margin({ left: 16, right: 16 })
    }
    .width('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载性能设置…' })
          }
          .width('100%')
          .height('100%')
        } else {
          Scroll() {
            Column({ space: 4 }) {
              this.toggleGroup('网络', NETWORK_TOGGLES)

              if (this.vm.has('cache_level')) {
                Column() {
                  SectionHeader({ title: '缓存级别' })
                  Row({ space: 12 }) {
                    Text('缓存级别')
                      .fontSize(15)
                      .fontColor($r('sys.color.font_primary'))
                    Blank()
                    Select(CACHE_LEVELS.map((level: string): SelectOption => ({ value: cacheLevelLabel(level) })))
                      .selected(CACHE_LEVELS.indexOf(this.vm.cacheLevel()))
                      .value(cacheLevelLabel(this.vm.cacheLevel()))
                      .font({ size: 14 })
                      .onSelect((index: number) => {
                        this.vm.set(this.zoneId, 'cache_level', CACHE_LEVELS[index]).then((err: string) => {
                          this.toast(err);
                        });
                      })
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(14)
                  .margin({ left: 16, right: 16 })
                }
                .width('100%')
              }

              this.toggleGroup('缓存行为', EXTRA_TOGGLES)
            }
            .width('100%')
            .padding({ bottom: 24 })
          }
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .width('100%')
          .height('100%')
        }
      }
      .width('100%')
      .height('100%')
    }
    .title(`${this.zoneName} · 性能`)
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      this.vm.load(param.zoneId).catch(() => {
      });
    })
  }
}
