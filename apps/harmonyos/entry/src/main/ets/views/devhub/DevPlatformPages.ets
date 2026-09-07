import { OCAddActionBar, OC_ACTION_BAR_CLEARANCE } from '../common/ActionBar';
import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 开发者平台各资源只读列表页（Queues / AI Gateway / Durable Objects / Hyperdrive）
// + Workers AI 模型目录与试运行（对齐 Android DevPlatformScreens）。
import {
  AIGateway,
  AIModel,
  CFQueue,
  DurableObjectInstance,
  DurableObjectNamespace,
  HyperdriveConfig,
  HyperdriveCaching,
  HyperdriveOrigin,
  QueueConsumer,
  QueueEndpoint,
} from '../../models/WorkerModels';
import { Routes, IdNameParam } from '../../models/Routes';
import { DevPlatformService, DurableObjectMemory } from '../../services/DevPlatformService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { formatBytes, formatTimeAgo } from '../../core/util/Format';
import {
  BRAND_ORANGE,
  BRAND_ORANGE_BG,
  DANGER_RED,
  InfoRow,
  OCEmpty,
  OCError,
  OCLoading,
  ResourceCard,
  ToggleRow,
} from '../common/Components';
import { GlassIsland, OCLayout, SectionTitle } from '../common/Daybreak';
import { image } from '@kit.ImageKit';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

// ---------- Queues ----------
@ObservedV2
class QueuesVM {
  @Trace items: CFQueue[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  @Trace isCreating: boolean = false;
  private service: DevPlatformService = new DevPlatformService();

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.items = await this.service.listQueues(accountStore.selectedId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async create(name: string): Promise<string> {
    this.isCreating = true;
    try {
      const created = await this.service.createQueue(accountStore.selectedId, name);
      this.items = this.items.concat([created]);
      return '';
    } catch (e) {
      return (e as Error).message ?? '创建失败';
    } finally {
      this.isCreating = false;
    }
  }

  async remove(queueId: string): Promise<string> {
    try {
      await this.service.deleteQueue(accountStore.selectedId, queueId);
      this.items = this.items.filter((q: CFQueue) => q.queue_id !== queueId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

/// 文本框整数解析（空 / 非法一律回落到默认值，避免把 NaN 发给服务端）
function intOr(text: string, fallback: number): number {
  const value = Number.parseInt(text.trim());
  return Number.isNaN(value) ? fallback : value;
}

/// Hyperdrive 源库类型选项
interface SchemeOption {
  scheme: string;
  label: string;
  defaultPort: number;
}

const DB_SCHEMES: SchemeOption[] = [
  { scheme: 'postgres', label: 'PostgreSQL', defaultPort: 5432 },
  { scheme: 'mysql', label: 'MySQL', defaultPort: 3306 },
];

@ComponentV2
export struct QueuesPage {
  @Local vm: QueuesVM = new QueuesVM();
  @Local refreshing: boolean = false;
  @Local showCreate: boolean = false;
  @Local fName: string = '';
  private pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  @Builder
  createSheet() {
    Column({ space: 12 }) {
      Text('新建队列')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.fName, placeholder: '队列名' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fName = value;
        })
      Button(this.vm.isCreating ? '正在创建…' : '创建')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isCreating && this.fName.trim() !== '')
        .onClick(() => {
          this.vm.create(this.fName.trim()).then((err: string) => {
            if (err === '') {
              this.showCreate = false;
              this.fName = '';
            } else {
              this.toast(err);
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading && this.vm.items.length === 0) {
          Column() {
            OCLoading({ text: '正在加载 Queues…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load().catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.items.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.rectangle_stack'), title: '暂无队列', subtitle: '点右下角 + 创建' })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            List() {
              ForEach(this.vm.items, (item: CFQueue) => {
                ListItem() {
                  ResourceCard({
                    symbol: $r('sys.symbol.rectangle_stack'),
                    title: item.queue_name ?? item.queue_id ?? '',
                    subtitle: `生产者 ${item.producers_total_count ?? 0} · 消费者 ${item.consumers_total_count ?? 0}`,
                    onTap: () => {
                      const param: IdNameParam = { id: item.queue_id ?? '', name: item.queue_name ?? item.queue_id ?? '' };
                      this.pathStack?.pushPathByName(Routes.QUEUE_DETAIL, param);
                    },
                    onLongPress: () => {
                      this.vm.remove(item.queue_id ?? '').then((err: string) => {
                        this.toast(err === '' ? '已删除' : err);
                      });
                    },
                  })
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
              }, (item: CFQueue) => item.queue_id ?? item.queue_name ?? '')
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Off)
            // 贴底操作栏叠在内容上，底部留出净空
            .padding({ bottom: OC_ACTION_BAR_CLEARANCE })
          }
          .width('100%')
          .height('100%')
          .onRefreshing(() => {
            this.refreshing = true;
            this.vm.load().then(() => {
              this.refreshing = false;
            }).catch(() => {
              this.refreshing = false;
            });
          })
        }

        // 主操作：贴底核心操作栏（替代右下角 FAB，拇指可达）
        OCAddActionBar({
          label: '新建',
          onTap: () => {
            this.showCreate = true;
          },
        })
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: 'Queues' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.showCreate, this.createSheet(), ocSheet(() => {
      this.showCreate = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.vm.load().catch(() => {
      });
    })
  }
}

// ---------- Queue 详情 ----------
@ObservedV2
class QueueDetailVM {
  @Trace queue: CFQueue | null = null;
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  @Trace isSaving: boolean = false;
  private service: DevPlatformService = new DevPlatformService();

  async load(queueId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.queue = await this.service.getQueue(accountStore.selectedId, queueId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  /// 写操作成功后重新拉详情（PUT 响应不一定带全 producers / consumers）
  private async reload(queueId: string): Promise<void> {
    try {
      this.queue = await this.service.getQueue(accountStore.selectedId, queueId);
    } catch (e) {
    }
  }

  async rename(queueId: string, name: string): Promise<string> {
    this.isSaving = true;
    try {
      await this.service.renameQueue(accountStore.selectedId, queueId, name);
      await this.reload(queueId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '重命名失败';
    } finally {
      this.isSaving = false;
    }
  }

  async saveSettings(queueId: string, deliveryDelay: number, retentionPeriod: number): Promise<string> {
    this.isSaving = true;
    try {
      await this.service.updateQueueSettings(accountStore.selectedId, queueId, deliveryDelay, retentionPeriod);
      await this.reload(queueId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '保存失败';
    } finally {
      this.isSaving = false;
    }
  }

  async setPaused(queueId: string, paused: boolean): Promise<string> {
    try {
      await this.service.setQueuePaused(accountStore.selectedId, queueId, paused);
      await this.reload(queueId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '操作失败';
    }
  }

  async purge(queueId: string): Promise<string> {
    try {
      await this.service.purgeQueue(accountStore.selectedId, queueId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '清空失败';
    }
  }

  /// 秒 → 可读时长
  static formatSeconds(seconds: number | undefined): string {
    if (seconds === undefined) {
      return '—';
    }
    if (seconds === 0) {
      return '无';
    }
    if (seconds % 86400 === 0) {
      return `${seconds / 86400} 天`;
    }
    if (seconds % 3600 === 0) {
      return `${seconds / 3600} 小时`;
    }
    if (seconds % 60 === 0) {
      return `${seconds / 60} 分钟`;
    }
    return `${seconds} 秒`;
  }
}

@ComponentV2
export struct QueueDetailPage {
  @Local vm: QueueDetailVM = new QueueDetailVM();
  @Local queueId: string = '';
  @Local queueName: string = '';
  @Local showRename: boolean = false;
  @Local fQueueName: string = '';
  @Local showSettings: boolean = false;
  @Local fDelay: string = '0';
  @Local fRetention: string = '345600';

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  /// 写操作 scope 门控：缺 queues.write 时拦截并提示
  private canWrite(): boolean {
    if (!authManager.hasScope(Scopes.QUEUES_WRITE)) {
      this.toast('当前授权未包含 Queues 写权限（queues.write）');
      return false;
    }
    return true;
  }

  private openRenameSheet(): void {
    if (!this.canWrite()) {
      return;
    }
    this.fQueueName = this.vm.queue?.queue_name ?? this.queueName;
    this.showRename = true;
  }

  private openSettingsSheet(): void {
    if (!this.canWrite()) {
      return;
    }
    this.fDelay = `${this.vm.queue?.settings?.delivery_delay ?? 0}`;
    this.fRetention = `${this.vm.queue?.settings?.message_retention_period ?? 345600}`;
    this.showSettings = true;
  }

  private confirmPurge(): void {
    if (!this.canWrite()) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '清空消息',
      message: `确定清空队列「${this.queueName}」的全部消息？此操作不可恢复。`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '清空',
        fontColor: '#DC2626',
        action: () => {
          this.vm.purge(this.queueId).then((err: string) => {
            this.toast(err === '' ? '已清空全部消息' : err);
          });
        },
      },
    });
  }

  // 分区标题 + 右侧橙色操作（SectionTitle 自带 width 100% 会把操作挤出屏幕，故行内自绘）
  @Builder
  actionTitle(title: string, action: string, onTap: () => void) {
    Row() {
      Text(title)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      Text(action)
        .fontSize(13)
        .fontColor($r('app.color.oc_brand_text'))
        .padding({ left: 8 })
        .onClick(onTap)
    }
    .width('100%')
  }

  /// Hero 卡（对照样板 ZoneDetailPage.heroCard）：队列图标 + 名称大字 + 投递状态点·生产/消费者计数
  @Builder
  heroCard() {
    Column({ space: 10 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.rectangle_stack'))
          .fontSize(26)
          .fontColor([$r('app.color.oc_brand_text')])
      }
      .width(52)
      .height(52)
      .backgroundColor($r('app.color.oc_brand_bg'))
      .borderRadius(14)

      Text(this.vm.queue?.queue_name ?? this.queueName)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 8 }) {
        Row({ space: 5 }) {
          Circle({ width: 7, height: 7 })
            .fill((this.vm.queue?.settings?.delivery_paused === true) ? '#EAB308' : '#22C55E')
          Text((this.vm.queue?.settings?.delivery_paused === true) ? '已暂停投递' : '投递中')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor((this.vm.queue?.settings?.delivery_paused === true) ? '#EAB308' : '#22C55E')
        }
        Text(`生产者 ${this.vm.queue?.producers?.length ?? 0} · 消费者 ${this.vm.queue?.consumers?.length ?? 0}`)
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
      }
    }
    .width('100%')
    .padding(OCLayout.islandPadding)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(OCLayout.islandRadius)
  }

  @Builder
  renameSheet() {
    Column({ space: 12 }) {
      Text('重命名队列')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.fQueueName, placeholder: '队列名' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fQueueName = value;
        })
      Button(this.vm.isSaving ? '正在保存…' : '保存')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isSaving && this.fQueueName.trim() !== '')
        .onClick(() => {
          const name = this.fQueueName.trim();
          this.vm.rename(this.queueId, name).then((err: string) => {
            if (err === '') {
              this.queueName = name;
              this.showRename = false;
              this.toast('已重命名');
            } else {
              this.toast(err);
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  @Builder
  settingsSheet() {
    Column({ space: 12 }) {
      Text('编辑投递设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      Text('投递延迟（秒，0 = 立即投递，最大 43200）')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ text: this.fDelay, placeholder: '0' })
        .type(InputType.Number)
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fDelay = value;
        })
      Text('消息保留期（秒，60–1209600，默认 4 天 = 345600）')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ text: this.fRetention, placeholder: '345600' })
        .type(InputType.Number)
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fRetention = value;
        })
      Button(this.vm.isSaving ? '正在保存…' : '保存')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isSaving && this.fDelay.trim() !== '' && this.fRetention.trim() !== '')
        .onClick(() => {
          const delay = Number.parseInt(this.fDelay.trim());
          const retention = Number.parseInt(this.fRetention.trim());
          this.vm.saveSettings(this.queueId, Number.isNaN(delay) ? 0 : delay,
            Number.isNaN(retention) ? 345600 : retention).then((err: string) => {
            if (err === '') {
              this.showSettings = false;
              this.toast('已保存');
            } else {
              this.toast(err);
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  private consumerLine(c: QueueConsumer): string {
    const parts: string[] = [];
    const s = c.settings;
    if (s) {
      if (s.batch_size !== undefined) {
        parts.push(`批 ${s.batch_size}`);
      }
      if (s.max_retries !== undefined) {
        parts.push(`重试 ${s.max_retries}`);
      }
      if (s.max_concurrency !== undefined) {
        parts.push(`并发 ${s.max_concurrency}`);
      }
    }
    return parts.join(' · ');
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载队列…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load(this.queueId).catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.queue !== null) {
          Scroll() {
            Column({ space: 16 }) {
              this.heroCard()

              // 队列（重命名；名称已上 Hero，岛内留标识信息）
              Column({ space: 8 }) {
                this.actionTitle('队列', '重命名', () => {
                  this.openRenameSheet();
                })
                GlassIsland({ pad: 0 }) {
                  Column() {
                    InfoRow({ label: '名称', value: this.vm.queue!.queue_name ?? this.queueName })
                    InfoRow({ label: '队列 ID', value: this.vm.queue!.queue_id ?? this.queueId })
                  }
                  .width('100%')
                }
              }
              .width('100%')

              // 投递状态（暂停 / 恢复）
              Column({ space: 8 }) {
                SectionTitle({ title: '投递' })
                GlassIsland({ pad: 0 }) {
                  ToggleRow({
                    title: '投递',
                    subtitle: (this.vm.queue!.settings?.delivery_paused === true)
                      ? '已暂停，消息将积压在队列中' : '投递中',
                    isOn: !(this.vm.queue!.settings?.delivery_paused === true),
                    onToggle: (on: boolean) => {
                      if (!this.canWrite()) {
                        return;
                      }
                      this.vm.setPaused(this.queueId, !on).then((err: string) => {
                        this.toast(err === '' ? (on ? '已恢复投递' : '已暂停投递') : err);
                      });
                    },
                  })
                }
              }
              .width('100%')

              // 设置
              Column({ space: 8 }) {
                this.actionTitle('设置', '编辑', () => {
                  this.openSettingsSheet();
                })
                GlassIsland({ pad: 0 }) {
                  Column() {
                    InfoRow({
                      label: '消息保留期',
                      value: QueueDetailVM.formatSeconds(this.vm.queue!.settings?.message_retention_period),
                    })
                    InfoRow({
                      label: '投递延迟',
                      value: QueueDetailVM.formatSeconds(this.vm.queue!.settings?.delivery_delay),
                    })
                    if ((this.vm.queue!.created_on ?? '') !== '') {
                      InfoRow({ label: '创建于', value: formatTimeAgo(this.vm.queue!.created_on ?? '') })
                    }
                  }
                  .width('100%')
                }
              }
              .width('100%')

              // 生产者
              Column({ space: 8 }) {
                SectionTitle({ title: `生产者（${this.vm.queue!.producers?.length ?? 0}）` })
                GlassIsland({ pad: 0 }) {
                  Column() {
                    if ((this.vm.queue!.producers?.length ?? 0) > 0) {
                      ForEach(this.vm.queue!.producers, (p: QueueEndpoint, index: number) => {
                        Text(p.script ?? p.type ?? '未知')
                          .fontSize(14)
                          .fontFamily('monospace')
                          .fontColor($r('sys.color.font_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                      }, (p: QueueEndpoint, index: number) => `${index}`)
                    } else {
                      Text('无生产者')
                        .fontSize(14)
                        .fontColor($r('sys.color.font_secondary'))
                        .width('100%')
                        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                    }
                  }
                  .width('100%')
                }
              }
              .width('100%')

              // 消费者
              Column({ space: 8 }) {
                SectionTitle({ title: `消费者（${this.vm.queue!.consumers?.length ?? 0}）` })
                GlassIsland({ pad: 0 }) {
                  Column() {
                    if ((this.vm.queue!.consumers?.length ?? 0) > 0) {
                      ForEach(this.vm.queue!.consumers, (c: QueueConsumer, index: number) => {
                        Column({ space: 3 }) {
                          Text(c.script ?? c.type ?? '未知')
                            .fontSize(14)
                            .fontFamily('monospace')
                            .fontColor($r('sys.color.font_primary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                          if (this.consumerLine(c) !== '') {
                            Text(this.consumerLine(c))
                              .fontSize(12)
                              .fontColor($r('sys.color.font_secondary'))
                              .width('100%')
                          }
                          if ((c.dead_letter_queue ?? '') !== '') {
                            Text(`死信队列：${c.dead_letter_queue}`)
                              .fontSize(11)
                              .fontColor($r('sys.color.font_tertiary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .width('100%')
                          }
                        }
                        .alignItems(HorizontalAlign.Start)
                        .width('100%')
                        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                      }, (c: QueueConsumer, index: number) => `${index}`)
                    } else {
                      Text('无消费者')
                        .fontSize(14)
                        .fontColor($r('sys.color.font_secondary'))
                        .width('100%')
                        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                    }
                  }
                  .width('100%')
                }
              }
              .width('100%')

              // 危险区（对照样板底部红色危险操作）
              Button('清空消息')
                .width('100%')
                .height(46)
                .fontSize(15)
                .fontColor('#DC2626')
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(OCLayout.chipRadius)
                .margin({ top: 8, bottom: 24 })
                .onClick(() => {
                  this.confirmPurge();
                })
            }
            .width('100%')
            .padding(OCLayout.pagePadding)
          }
          .scrollBar(BarState.Off)
          .width('100%')
          .height('100%')
          .align(Alignment.Top)
        }
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: this.queueName !== '' ? this.queueName : 'Queue' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.showRename, this.renameSheet(), ocSheet(() => {
      this.showRename = false;
    }))
    .bindSheet(this.showSettings, this.settingsSheet(), ocSheet(() => {
      this.showSettings = false;
    }))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as IdNameParam;
      this.queueId = param.id;
      this.queueName = param.name;
      this.vm.load(this.queueId).catch(() => {
      });
    })
  }
}

// ---------- AI Gateway ----------
@ObservedV2
class GatewaysVM {
  @Trace items: AIGateway[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  @Trace isCreating: boolean = false;
  private service: DevPlatformService = new DevPlatformService();

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.items = await this.service.listGateways(accountStore.selectedId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async create(name: string, cacheTtl: number, collectLogs: boolean,
    rateLimit: number, rateInterval: number): Promise<string> {
    this.isCreating = true;
    try {
      const created = await this.service.createGateway(accountStore.selectedId, name,
        cacheTtl, collectLogs, rateLimit, rateInterval);
      this.items = this.items.concat([created]);
      return '';
    } catch (e) {
      return (e as Error).message ?? '创建失败';
    } finally {
      this.isCreating = false;
    }
  }

  async remove(gatewayId: string): Promise<string> {
    try {
      await this.service.deleteGateway(accountStore.selectedId, gatewayId);
      this.items = this.items.filter((g: AIGateway) => g.id !== gatewayId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct AIGatewayPage {
  /// 新建网关的可选项（默认值与 iOS 一致：收日志、不缓存、不限速、60s 窗口）
  @Local fCollectLogs: boolean = true;
  @Local fCacheTtl: string = '0';
  @Local fRateLimit: string = '0';
  @Local fRateInterval: string = '60';
  @Local vm: GatewaysVM = new GatewaysVM();
  @Local refreshing: boolean = false;
  @Local showCreate: boolean = false;
  @Local fName: string = '';
  private pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  @Builder
  createSheet() {
    Column({ space: 12 }) {
      Text('新建 AI Gateway')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.fName, placeholder: '网关 ID（小写字母/数字/连字符）' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fName = value;
        })
      Text('创建后不可更改。')
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')

      // 日志与缓存（对照 iOS 新建网关的「日志与缓存」段）
      Row({ space: 12 }) {
        Text('收集日志')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.fCollectLogs })
          .selectedColor($r('app.color.oc_brand'))
          .onChange((isOn: boolean) => {
            this.fCollectLogs = isOn;
          })
      }
      .width('100%')
      TextInput({ text: this.fCacheTtl, placeholder: '缓存 TTL（秒，0 = 不缓存）' })
        .type(InputType.Number)
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fCacheTtl = value;
        })

      // 限速（对照 iOS 的「限速」段；上限 0 = 不限速）
      Row({ space: 8 }) {
        TextInput({ text: this.fRateLimit, placeholder: '限速上限（0=不限）' })
          .type(InputType.Number)
          .fontSize(14)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.fRateLimit = value;
          })
        TextInput({ text: this.fRateInterval, placeholder: '窗口（秒）' })
          .type(InputType.Number)
          .fontSize(14)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.fRateInterval = value;
          })
      }
      .width('100%')

      Button(this.vm.isCreating ? '正在创建…' : '创建')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isCreating && this.fName.trim() !== '')
        .onClick(() => {
          this.vm.create(this.fName.trim(), intOr(this.fCacheTtl, 0), this.fCollectLogs,
            intOr(this.fRateLimit, 0), intOr(this.fRateInterval, 60)).then((err: string) => {
            if (err === '') {
              this.showCreate = false;
              this.fName = '';
            } else {
              this.toast(err);
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading && this.vm.items.length === 0) {
          Column() {
            OCLoading({ text: '正在加载网关…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load().catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.items.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.wand_and_stars'), title: '暂无 AI Gateway', subtitle: '点右下角 + 创建' })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            List() {
              ForEach(this.vm.items, (item: AIGateway) => {
                ListItem() {
                  ResourceCard({
                    symbol: $r('sys.symbol.wand_and_stars'),
                    title: item.name ?? item.id,
                    subtitle: item.created_on ? `创建于 ${formatTimeAgo(item.created_on ?? '')}` : '',
                    onTap: () => {
                      const param: IdNameParam = { id: item.id, name: item.name ?? item.id };
                      this.pathStack?.pushPathByName(Routes.AI_GATEWAY_DETAIL, param);
                    },
                    onLongPress: () => {
                      this.vm.remove(item.id).then((err: string) => {
                        this.toast(err === '' ? '已删除' : err);
                      });
                    },
                  })
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
              }, (item: AIGateway) => item.id)
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Off)
          }
          .width('100%')
          .height('100%')
          .onRefreshing(() => {
            this.refreshing = true;
            this.vm.load().then(() => {
              this.refreshing = false;
            }).catch(() => {
              this.refreshing = false;
            });
          })
        }

        // 主操作：贴底核心操作栏（替代右下角 FAB，拇指可达）
        OCAddActionBar({
          label: '新建',
          onTap: () => {
            this.showCreate = true;
          },
        })
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: 'AI Gateway' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.showCreate, this.createSheet(), ocSheet(() => {
      this.showCreate = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.vm.load().catch(() => {
      });
    })
  }
}

// ---------- AI Gateway 详情 ----------
@ObservedV2
class AIGatewayDetailVM {
  @Trace gateway: AIGateway | null = null;
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  private service: DevPlatformService = new DevPlatformService();

  async load(gatewayId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.gateway = await this.service.getGateway(accountStore.selectedId, gatewayId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }
}

@ComponentV2
export struct AIGatewayDetailPage {
  @Local vm: AIGatewayDetailVM = new AIGatewayDetailVM();
  @Local gatewayId: string = '';
  @Local gatewayName: string = '';

  /// Hero 卡（对照样板 ZoneDetailPage.heroCard）：网关图标 + 名称大字 + 缓存/日志关键元信息
  @Builder
  heroCard() {
    Column({ space: 10 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.wand_and_stars'))
          .fontSize(26)
          .fontColor([$r('app.color.oc_brand_text')])
      }
      .width(52)
      .height(52)
      .backgroundColor($r('app.color.oc_brand_bg'))
      .borderRadius(14)

      Text(this.vm.gateway?.name ?? this.gatewayName)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 8 }) {
        Row({ space: 5 }) {
          Circle({ width: 7, height: 7 })
            .fill(this.vm.gateway?.collect_logs === true ? '#22C55E' : $r('sys.color.font_tertiary'))
          Text(this.vm.gateway?.collect_logs === true ? '日志采集中' : '日志已关闭')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.vm.gateway?.collect_logs === true ? '#22C55E' : $r('sys.color.font_secondary'))
        }
        Text((this.vm.gateway?.cache_ttl ?? 0) > 0 ? `缓存 ${this.vm.gateway?.cache_ttl} 秒` : '不缓存')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
      }
    }
    .width('100%')
    .padding(OCLayout.islandPadding)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(OCLayout.islandRadius)
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载网关…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load(this.gatewayId).catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.gateway !== null) {
          Scroll() {
            Column({ space: 16 }) {
              this.heroCard()

              // 标识
              Column({ space: 8 }) {
                SectionTitle({ title: '标识' })
                GlassIsland({ pad: 0 }) {
                  InfoRow({ label: '网关 ID', value: this.vm.gateway!.id })
                }
              }
              .width('100%')

              // 设置
              Column({ space: 8 }) {
                SectionTitle({ title: '设置' })
                GlassIsland({ pad: 0 }) {
                  Column() {
                    InfoRow({
                      label: '缓存 TTL',
                      value: (this.vm.gateway!.cache_ttl ?? 0) > 0 ? `${this.vm.gateway!.cache_ttl} 秒` : '不缓存',
                    })
                    InfoRow({ label: '日志采集', value: this.vm.gateway!.collect_logs === true ? '已开启' : '已关闭' })
                    InfoRow({
                      label: '限流上限',
                      value: (this.vm.gateway!.rate_limiting_limit ?? 0) > 0
                        ? `${this.vm.gateway!.rate_limiting_limit}` : '不限',
                    })
                    if ((this.vm.gateway!.rate_limiting_limit ?? 0) > 0 &&
                      this.vm.gateway!.rate_limiting_interval !== undefined) {
                      InfoRow({ label: '限流窗口', value: `${this.vm.gateway!.rate_limiting_interval} 秒` })
                    }
                  }
                  .width('100%')
                }
              }
              .width('100%')

              // 时间
              if ((this.vm.gateway!.created_on ?? '') !== '' || (this.vm.gateway!.modified_on ?? '') !== '') {
                Column({ space: 8 }) {
                  SectionTitle({ title: '时间' })
                  GlassIsland({ pad: 0 }) {
                    Column() {
                      if ((this.vm.gateway!.created_on ?? '') !== '') {
                        InfoRow({ label: '创建于', value: formatTimeAgo(this.vm.gateway!.created_on ?? '') })
                      }
                      if ((this.vm.gateway!.modified_on ?? '') !== '') {
                        InfoRow({ label: '修改于', value: formatTimeAgo(this.vm.gateway!.modified_on ?? '') })
                      }
                    }
                    .width('100%')
                  }
                }
                .width('100%')
              }
            }
            .width('100%')
            .padding(OCLayout.pagePadding)
          }
          .scrollBar(BarState.Off)
          .width('100%')
          .height('100%')
          .align(Alignment.Top)
        }
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: this.gatewayName !== '' ? this.gatewayName : 'AI Gateway' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as IdNameParam;
      this.gatewayId = param.id;
      this.gatewayName = param.name;
      this.vm.load(this.gatewayId).catch(() => {
      });
    })
  }
}

// ---------- Durable Objects ----------
@ObservedV2
class DOVM {
  @Trace items: DurableObjectNamespace[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  private service: DevPlatformService = new DevPlatformService();

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.items = await this.service.listDurableObjectNamespaces(accountStore.selectedId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }
}

@ComponentV2
export struct DurableObjectsPage {
  @Local vm: DOVM = new DOVM();
  @Local pathStack: NavPathStack | null = null;

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载命名空间…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load().catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.items.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.square_stack_3d'), title: '暂无 Durable Object' })
          }
          .width('100%')
          .height('100%')
        } else {
          List() {
            ForEach(this.vm.items, (item: DurableObjectNamespace) => {
              ListItem() {
                ResourceCard({
                  symbol: $r('sys.symbol.square_stack_3d'),
                  title: item.name ?? item.id,
                  subtitle: `${item.class ?? ''} · ${item.script ?? ''}`,
                  onTap: () => {
                    const param: IdNameParam = { id: item.id, name: item.name ?? item.id };
                    this.pathStack?.pushPathByName(Routes.DO_DETAIL, param);
                  },
                })
              }
              .margin({ left: 16, right: 16, top: 5, bottom: 5 })
            }, (item: DurableObjectNamespace) => item.id)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
        }
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: 'Durable Objects' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.vm.load().catch(() => {
      });
    })
  }
}

// ---------- Hyperdrive ----------

/// 命名空间下的对象实例（只读，游标分页）
@ObservedV2
class DOInstancesVM {
  @Trace items: DurableObjectInstance[] = [];
  @Trace isLoading: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  /// 下一页游标，空 = 已到末页
  @Trace cursor: string = '';
  /// 24h 内存分位数；undefined = 无数据（免费账号 authz 或该窗口无流量）
  @Trace memory: DurableObjectMemory | undefined = undefined;
  @Trace memoryLoaded: boolean = false;
  private service: DevPlatformService = new DevPlatformService();

  async load(namespaceId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      const page = await this.service.listDurableObjects(accountStore.selectedId, namespaceId);
      this.items = page.items;
      this.cursor = page.cursor;
      this.loaded = true;
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
    // 内存单独取、失败不影响列表
    this.memory = await this.service.durableObjectMemory(accountStore.selectedId, namespaceId);
    this.memoryLoaded = true;
  }

  async loadMore(namespaceId: string): Promise<void> {
    if (this.isLoading || this.cursor === '') {
      return;
    }
    this.isLoading = true;
    try {
      const page = await this.service.listDurableObjects(accountStore.selectedId, namespaceId, this.cursor);
      this.items = this.items.concat(page.items);
      this.cursor = page.cursor;
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }
}

/// 对象实例列表（对照 iOS DurableObjectInstancesSheet）：只读展示对象 ID 与是否已写入存储。
@ComponentV2
export struct DurableObjectDetailPage {
  @Local vm: DOInstancesVM = new DOInstancesVM();
  @Local namespaceId: string = '';
  @Local namespaceName: string = '';

  /// 24h 内存分位数。口径必须写清楚是 isolate 而非单个对象，否则会被读成「这个对象占了多少」。
  @Builder
  memoryCard() {
    GlassIsland({ pad: 14 }) {
      Column({ space: 6 }) {
        Text('内存用量（24 小时）')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
        if (!this.vm.memoryLoaded) {
          LoadingProgress().width(20).height(20)
        } else if (this.vm.memory === undefined) {
          Text('这个命名空间在过去 24 小时没有内存数据，或当前账号无权读取账户级分析。')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        } else {
          this.memoryRow('P50', this.vm.memory.p50)
          this.memoryRow('P90', this.vm.memory.p90)
          this.memoryRow('P99', this.vm.memory.p99)
          this.memoryRow('P99.9', this.vm.memory.p999)
          Text('这是 V8 isolate 的内存，不是单个对象的。一个 isolate 可能同时承载同类的多个对象与外围 Worker 代码，每个 isolate 上限 128 MB。')
            .fontSize(11)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  memoryRow(label: string, value: number) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
      Blank()
      Text(formatBytes(value))
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor($r('sys.color.font_primary'))
    }
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading && !this.vm.loaded) {
          Column() {
            OCLoading({ text: '正在加载对象…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.items.length === 0) {
          Column({ space: 12 }) {
            OCEmpty({
              symbol: $r('sys.symbol.square_stack_3d'),
              title: '没有对象',
              subtitle: this.vm.error !== '' ? this.vm.error : '该命名空间下还没有对象实例。对象在首次被访问时自动创建。',
            })
            this.memoryCard()
          }
          .width('100%')
          .height('100%')
          .padding(OCLayout.pagePadding)
        } else {
          Scroll() {
            Column({ space: 8 }) {
              Text(`${this.vm.items.length} 个对象`)
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
                .width('100%')
                .padding({ left: 4 })
              this.memoryCard()
              Column() {
                ForEach(this.vm.items, (item: DurableObjectInstance, index: number) => {
                  Row({ space: 8 }) {
                    Text(item.id)
                      .fontSize(13)
                      .fontFamily('monospace')
                      .fontColor($r('sys.color.font_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    if (item.hasStoredData === true) {
                      Text('有数据')
                        .fontSize(10)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.oc_brand_text'))
                        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                        .backgroundColor($r('app.color.oc_brand_bg'))
                        .borderRadius(8)
                    }
                  }
                  .width('100%')
                  .padding({ left: 14, right: 14, top: 11, bottom: 11 })
                  if (index < this.vm.items.length - 1) {
                    Divider()
                      .strokeWidth(0.5)
                      .color($r('sys.color.comp_divider'))
                      .margin({ left: 14 })
                  }
                }, (item: DurableObjectInstance) => item.id)
              }
              .width('100%')
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(OCLayout.chipRadius)
              .clip(true)

              if (this.vm.cursor !== '') {
                Button(this.vm.isLoading ? '正在加载…' : '加载更多')
                  .width('100%')
                  .height(42)
                  .fontSize(14)
                  .fontColor($r('app.color.oc_brand_text'))
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(OCLayout.chipRadius)
                  .enabled(!this.vm.isLoading)
                  .onClick(() => {
                    this.vm.loadMore(this.namespaceId).catch(() => {
                    });
                  })
              }

              Text('对象实例只读：展示对象 ID 与是否已写入存储。')
                .fontSize(11)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
                .padding({ left: 4, top: 4 })
            }
            .width('100%')
            .padding(OCLayout.pagePadding)
          }
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .width('100%')
          .height('100%')
        }
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: this.namespaceName !== '' ? this.namespaceName : 'Durable Object' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as IdNameParam;
      this.namespaceId = param.id;
      this.namespaceName = param.name;
      this.vm.load(param.id).catch(() => {
      });
    })
  }
}

@ObservedV2
class HyperdriveVM {
  @Trace items: HyperdriveConfig[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  @Trace isCreating: boolean = false;
  private service: DevPlatformService = new DevPlatformService();

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.items = await this.service.listHyperdrive(accountStore.selectedId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async create(name: string, host: string, port: string, database: string, user: string,
    password: string, scheme: string): Promise<string> {
    this.isCreating = true;
    try {
      const portNum = Number.parseInt(port);
      const fallbackPort = scheme === 'mysql' ? 3306 : 5432;
      const created = await this.service.createHyperdrive(accountStore.selectedId, name, host,
        Number.isNaN(portNum) ? fallbackPort : portNum, database, user, password, scheme);
      this.items = this.items.concat([created]);
      return '';
    } catch (e) {
      return (e as Error).message ?? '创建失败';
    } finally {
      this.isCreating = false;
    }
  }

  async remove(configId: string): Promise<string> {
    try {
      await this.service.deleteHyperdrive(accountStore.selectedId, configId);
      this.items = this.items.filter((h: HyperdriveConfig) => h.id !== configId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct HyperdrivePage {
  /// 源库类型（postgres / mysql），切换时同步端口默认值
  @Local fScheme: string = 'postgres';
  @Local vm: HyperdriveVM = new HyperdriveVM();
  @Local refreshing: boolean = false;
  @Local showCreate: boolean = false;
  @Local fName: string = '';
  @Local fHost: string = '';
  @Local fPort: string = '5432';
  @Local fDatabase: string = '';
  @Local fUser: string = '';
  @Local fPassword: string = '';
  private pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  @Builder
  createSheet() {
    Column({ space: 10 }) {
      Text('新建 Hyperdrive')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      // 数据库类型（对照 iOS 的 Picker；切类型时端口跟着换默认值）
      Row({ space: 8 }) {
        Text('数据库类型')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        ForEach(DB_SCHEMES, (option: SchemeOption) => {
          Text(option.label)
            .fontSize(13)
            .fontWeight(this.fScheme === option.scheme ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.fScheme === option.scheme ? $r('app.color.oc_brand_text') : $r('sys.color.font_secondary'))
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .backgroundColor(this.fScheme === option.scheme ? $r('app.color.oc_brand_bg') : $r('sys.color.comp_background_list_card'))
            .borderRadius(16)
            .onClick(() => {
              this.fScheme = option.scheme;
              this.fPort = `${option.defaultPort}`;
            })
        }, (option: SchemeOption) => option.scheme)
      }
      .width('100%')
      TextInput({ text: this.fName, placeholder: '配置名' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fName = value;
        })
      TextInput({ text: this.fHost, placeholder: '源库主机' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fHost = value;
        })
      Row({ space: 8 }) {
        TextInput({ text: this.fPort, placeholder: '端口' })
          .type(InputType.Number)
          .fontSize(14)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.fPort = value;
          })
        TextInput({ text: this.fDatabase, placeholder: '数据库名' })
          .fontSize(14)
          .layoutWeight(2)
          .onChange((value: string) => {
            this.fDatabase = value;
          })
      }
      .width('100%')
      TextInput({ text: this.fUser, placeholder: '用户名' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fUser = value;
        })
      TextInput({ text: this.fPassword, placeholder: '密码' })
        .type(InputType.Password)
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fPassword = value;
        })
      Button(this.vm.isCreating ? '正在创建…' : '创建')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isCreating && this.fName.trim() !== '' && this.fHost.trim() !== '' &&
          this.fDatabase.trim() !== '' && this.fUser.trim() !== '')
        .onClick(() => {
          this.vm.create(this.fName.trim(), this.fHost.trim(), this.fPort.trim(), this.fDatabase.trim(),
            this.fUser.trim(), this.fPassword, this.fScheme).then((err: string) => {
            if (err === '') {
              this.showCreate = false;
              this.fName = '';
              this.fHost = '';
              this.fDatabase = '';
              this.fUser = '';
              this.fPassword = '';
            } else {
              this.toast(err);
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading && this.vm.items.length === 0) {
          Column() {
            OCLoading({ text: '正在加载 Hyperdrive…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load().catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.items.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.externaldrive'), title: '暂无 Hyperdrive 配置', subtitle: '点右下角 + 创建' })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            List() {
              ForEach(this.vm.items, (item: HyperdriveConfig) => {
                ListItem() {
                  ResourceCard({
                    symbol: $r('sys.symbol.archivebox'),
                    title: item.name ?? item.id,
                    subtitle: item.origin?.host ?? '',
                    onTap: () => {
                      this.pathStack?.pushPathByName(Routes.HYPERDRIVE_DETAIL, item);
                    },
                    onLongPress: () => {
                      this.vm.remove(item.id).then((err: string) => {
                        this.toast(err === '' ? '已删除' : err);
                      });
                    },
                  })
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
              }, (item: HyperdriveConfig) => item.id)
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Off)
          }
          .width('100%')
          .height('100%')
          .onRefreshing(() => {
            this.refreshing = true;
            this.vm.load().then(() => {
              this.refreshing = false;
            }).catch(() => {
              this.refreshing = false;
            });
          })
        }

        // 主操作：贴底核心操作栏（替代右下角 FAB，拇指可达）
        OCAddActionBar({
          label: '新建',
          onTap: () => {
            this.showCreate = true;
          },
        })
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: 'Hyperdrive' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.showCreate, this.createSheet(), ocSheet(() => {
      this.showCreate = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.vm.load().catch(() => {
      });
    })
  }
}

// ---------- Hyperdrive 详情 ----------
@ObservedV2
class HyperdriveDetailVM {
  @Trace config: HyperdriveConfig | null = null;
  @Trace isSaving: boolean = false;
  private service: DevPlatformService = new DevPlatformService();

  /// 编辑缓存 + 连接上限，PATCH 返回更新后的配置
  async saveCaching(disabled: boolean, maxAge: number, swr: number, connLimit: number): Promise<string> {
    this.isSaving = true;
    try {
      const updated = await this.service.updateHyperdrive(accountStore.selectedId, this.config?.id ?? '',
        disabled, maxAge, swr, connLimit);
      this.config = updated;
      return '';
    } catch (e) {
      return (e as Error).message ?? '保存失败';
    } finally {
      this.isSaving = false;
    }
  }

  /// 重命名（PATCH 只发 name）
  async rename(name: string): Promise<string> {
    this.isSaving = true;
    try {
      const updated = await this.service.renameHyperdrive(accountStore.selectedId, this.config?.id ?? '', name);
      this.config = updated;
      return '';
    } catch (e) {
      return (e as Error).message ?? '重命名失败';
    } finally {
      this.isSaving = false;
    }
  }

  /// 编辑源库连接（PATCH origin 需整组字段含密码；scheme 沿用现值）
  async saveOrigin(host: string, port: number, database: string, user: string,
    password: string): Promise<string> {
    this.isSaving = true;
    try {
      const scheme = this.config?.origin?.scheme ?? 'postgres';
      const updated = await this.service.updateHyperdriveOrigin(accountStore.selectedId,
        this.config?.id ?? '', scheme, host, port, database, user, password);
      this.config = updated;
      return '';
    } catch (e) {
      return (e as Error).message ?? '保存失败';
    } finally {
      this.isSaving = false;
    }
  }
}

@ComponentV2
export struct HyperdriveDetailPage {
  @Local vm: HyperdriveDetailVM = new HyperdriveDetailVM();
  @Local showCaching: boolean = false;
  @Local eDisabled: boolean = false;
  @Local eMaxAge: string = '60';
  @Local eSwr: string = '15';
  @Local eConnLimit: string = '';
  @Local showRename: boolean = false;
  @Local fName: string = '';
  @Local showOrigin: boolean = false;
  @Local fHost: string = '';
  @Local fPort: string = '5432';
  @Local fDatabase: string = '';
  @Local fUser: string = '';
  @Local fPassword: string = '';

  private get config(): HyperdriveConfig | null {
    return this.vm.config;
  }

  private cachingEnabled(): boolean {
    return !(this.vm.config?.caching?.disabled ?? false);
  }

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  /// 写操作 scope 门控：缺 query-cache.write 时拦截并提示
  private canWrite(): boolean {
    if (!authManager.hasScope(Scopes.HYPERDRIVE_WRITE)) {
      this.toast('当前授权未包含 Hyperdrive 写权限（query-cache.write）');
      return false;
    }
    return true;
  }

  private openCachingSheet(): void {
    if (!this.canWrite()) {
      return;
    }
    const caching: HyperdriveCaching | undefined = this.vm.config?.caching;
    this.eDisabled = caching?.disabled ?? false;
    this.eMaxAge = `${caching?.max_age ?? 60}`;
    this.eSwr = `${caching?.stale_while_revalidate ?? 15}`;
    this.eConnLimit = this.vm.config?.origin_connection_limit !== undefined
      ? `${this.vm.config!.origin_connection_limit}` : '';
    this.showCaching = true;
  }

  private openRenameSheet(): void {
    if (!this.canWrite()) {
      return;
    }
    this.fName = this.vm.config?.name ?? '';
    this.showRename = true;
  }

  private openOriginSheet(): void {
    if (!this.canWrite()) {
      return;
    }
    const origin: HyperdriveOrigin | undefined = this.vm.config?.origin;
    this.fHost = origin?.host ?? '';
    this.fPort = `${origin?.port ?? 5432}`;
    this.fDatabase = origin?.database ?? '';
    this.fUser = origin?.user ?? '';
    this.fPassword = '';
    this.showOrigin = true;
  }

  // 分区标题 + 右侧橙色操作（SectionTitle 自带 width 100% 会把操作挤出屏幕，故行内自绘）
  @Builder
  actionTitle(title: string, action: string, onTap: () => void) {
    Row() {
      Text(title)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      Text(action)
        .fontSize(13)
        .fontColor($r('app.color.oc_brand_text'))
        .padding({ left: 8 })
        .onClick(onTap)
    }
    .width('100%')
  }

  /// Hero 卡（对照样板 ZoneDetailPage.heroCard）：Hyperdrive 图标 + 配置名大字 + 缓存状态点·源库主机
  @Builder
  heroCard() {
    Column({ space: 10 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.archivebox'))
          .fontSize(26)
          .fontColor([$r('app.color.oc_brand_text')])
      }
      .width(52)
      .height(52)
      .backgroundColor($r('app.color.oc_brand_bg'))
      .borderRadius(14)

      Text(this.config?.name ?? 'Hyperdrive')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 8 }) {
        Row({ space: 5 }) {
          Circle({ width: 7, height: 7 })
            .fill(this.cachingEnabled() ? '#22C55E' : $r('sys.color.font_tertiary'))
          Text(this.cachingEnabled() ? '查询缓存已启用' : '查询缓存已禁用')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.cachingEnabled() ? '#22C55E' : $r('sys.color.font_secondary'))
        }
        if ((this.config?.origin?.host ?? '') !== '') {
          Text(this.config?.origin?.host ?? '')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
    }
    .width('100%')
    .padding(OCLayout.islandPadding)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(OCLayout.islandRadius)
  }

  @Builder
  renameSheet() {
    Column({ space: 12 }) {
      Text('重命名配置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.fName, placeholder: '配置名' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fName = value;
        })
      Button(this.vm.isSaving ? '正在保存…' : '保存')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isSaving && this.fName.trim() !== '')
        .onClick(() => {
          this.vm.rename(this.fName.trim()).then((err: string) => {
            if (err === '') {
              this.showRename = false;
              this.toast('已重命名');
            } else {
              this.toast(err);
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  @Builder
  originSheet() {
    Column({ space: 10 }) {
      Text('编辑源库连接')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      Text('修改连接需重新输入密码（Cloudflare 不回传旧密码）')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ text: this.fHost, placeholder: '源库主机' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fHost = value;
        })
      Row({ space: 8 }) {
        TextInput({ text: this.fPort, placeholder: '端口' })
          .type(InputType.Number)
          .fontSize(14)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.fPort = value;
          })
        TextInput({ text: this.fDatabase, placeholder: '数据库名' })
          .fontSize(14)
          .layoutWeight(2)
          .onChange((value: string) => {
            this.fDatabase = value;
          })
      }
      .width('100%')
      TextInput({ text: this.fUser, placeholder: '用户名' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fUser = value;
        })
      TextInput({ text: this.fPassword, placeholder: '密码（必填）' })
        .type(InputType.Password)
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fPassword = value;
        })
      Button(this.vm.isSaving ? '正在保存…' : '保存')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isSaving && this.fHost.trim() !== '' && this.fDatabase.trim() !== '' &&
          this.fUser.trim() !== '' && this.fPassword !== '')
        .onClick(() => {
          const portNum = Number.parseInt(this.fPort.trim());
          this.vm.saveOrigin(this.fHost.trim(), Number.isNaN(portNum) ? 5432 : portNum,
            this.fDatabase.trim(), this.fUser.trim(), this.fPassword).then((err: string) => {
            if (err === '') {
              this.showOrigin = false;
              this.toast('已保存');
            } else {
              this.toast(err);
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  @Builder
  cachingSheet() {
    Column({ space: 12 }) {
      Text('编辑缓存')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text('启用查询缓存')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Text('关闭后所有查询直连源库，不缓存结果')
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: !this.eDisabled })
          .selectedColor($r('app.color.oc_brand'))
          .onChange((isOn: boolean) => {
            this.eDisabled = !isOn;
          })
      }
      .width('100%')
      if (!this.eDisabled) {
        TextInput({ text: this.eMaxAge, placeholder: '最大缓存时长（秒）' })
          .type(InputType.Number)
          .fontSize(14)
          .width('100%')
          .onChange((value: string) => {
            this.eMaxAge = value;
          })
        TextInput({ text: this.eSwr, placeholder: '陈旧重验证（秒）' })
          .type(InputType.Number)
          .fontSize(14)
          .width('100%')
          .onChange((value: string) => {
            this.eSwr = value;
          })
      }
      TextInput({ text: this.eConnLimit, placeholder: '连接上限（留空为默认）' })
        .type(InputType.Number)
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.eConnLimit = value;
        })
      Button(this.vm.isSaving ? '正在保存…' : '保存')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isSaving)
        .onClick(() => {
          const maxAge = Number.parseInt(this.eMaxAge);
          const swr = Number.parseInt(this.eSwr);
          const conn = Number.parseInt(this.eConnLimit);
          this.vm.saveCaching(this.eDisabled, Number.isNaN(maxAge) ? 60 : maxAge,
            Number.isNaN(swr) ? 15 : swr, Number.isNaN(conn) ? 0 : conn).then((err: string) => {
            if (err === '') {
              this.showCaching = false;
              this.toast('已保存');
            } else {
              this.toast(err);
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.config !== null) {
          Scroll() {
            Column({ space: 16 }) {
              this.heroCard()

              // 配置（重命名；名称已上 Hero，岛内留标识信息）
              Column({ space: 8 }) {
                this.actionTitle('配置', '重命名', () => {
                  this.openRenameSheet();
                })
                GlassIsland({ pad: 0 }) {
                  Column() {
                    InfoRow({ label: '名称', value: this.config!.name ?? '' })
                    InfoRow({ label: '配置 ID', value: this.config!.id })
                  }
                  .width('100%')
                }
              }
              .width('100%')

              // 源数据库
              Column({ space: 8 }) {
                this.actionTitle('源数据库', '编辑连接', () => {
                  this.openOriginSheet();
                })
                GlassIsland({ pad: 0 }) {
                  Column() {
                    if (this.config!.origin !== undefined) {
                      if ((this.config!.origin!.scheme ?? '') !== '') {
                        InfoRow({ label: '类型', value: (this.config!.origin!.scheme ?? '').toUpperCase() })
                      }
                      if ((this.config!.origin!.host ?? '') !== '') {
                        InfoRow({ label: '主机', value: this.config!.origin!.host ?? '' })
                      }
                      if (this.config!.origin!.port !== undefined) {
                        InfoRow({ label: '端口', value: `${this.config!.origin!.port}` })
                      }
                      if ((this.config!.origin!.database ?? '') !== '') {
                        InfoRow({ label: '数据库', value: this.config!.origin!.database ?? '' })
                      }
                      if ((this.config!.origin!.user ?? '') !== '') {
                        InfoRow({ label: '用户名', value: this.config!.origin!.user ?? '' })
                      }
                    } else {
                      Text('无连接信息')
                        .fontSize(14)
                        .fontColor($r('sys.color.font_secondary'))
                        .width('100%')
                        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                    }
                  }
                  .width('100%')
                }
              }
              .width('100%')

              // 缓存
              Column({ space: 8 }) {
                this.actionTitle('缓存', '编辑缓存', () => {
                  this.openCachingSheet();
                })
                GlassIsland({ pad: 0 }) {
                  Column() {
                    InfoRow({ label: '查询缓存', value: this.cachingEnabled() ? '已启用' : '已禁用' })
                    if (this.cachingEnabled()) {
                      InfoRow({ label: '最大缓存时长', value: `${this.config!.caching?.max_age ?? 60} 秒` })
                      InfoRow({ label: '陈旧重验证', value: `${this.config!.caching?.stale_while_revalidate ?? 15} 秒` })
                    }
                    if (this.config!.origin_connection_limit !== undefined) {
                      InfoRow({ label: '连接上限', value: `${this.config!.origin_connection_limit}` })
                    }
                  }
                  .width('100%')
                }
              }
              .width('100%')
            }
            .width('100%')
            .padding(OCLayout.pagePadding)
          }
          .scrollBar(BarState.Off)
          .width('100%')
          .height('100%')
          .align(Alignment.Top)
        }
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: this.config?.name ?? 'Hyperdrive' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.showCaching, this.cachingSheet(), ocSheet(() => {
      this.showCaching = false;
    }))
    .bindSheet(this.showRename, this.renameSheet(), ocSheet(() => {
      this.showRename = false;
    }))
    .bindSheet(this.showOrigin, this.originSheet(), ocSheet(() => {
      this.showOrigin = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.vm.config = context.pathInfo.param as HyperdriveConfig;
    })
  }
}

// ---------- Workers AI（模型目录 + 试运行） ----------
/// 模型按任务分组（对照 iOS WorkersAIViewModel.grouped）
interface AIModelGroup {
  task: string;
  models: AIModel[];
}

/// 模型短名：去掉 @cf/vendor/ 前缀，只留最后一段
function modelShortName(model: AIModel): string {
  const full = model.name ?? model.id ?? '';
  const parts = full.split('/');
  return parts.length > 0 ? parts[parts.length - 1] : full;
}

@ObservedV2
class AIVM {
  @Trace models: AIModel[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  @Trace running: boolean = false;
  /// 文本生成输出
  @Trace output: string = '';
  /// 文生图输出（PixelMap，null = 尚无结果）
  @Trace image: PixelMap | null = null;
  /// 试运行失败原因（与输出区分开，红字展示）
  @Trace runError: string = '';
  private service: DevPlatformService = new DevPlatformService();

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.models = await this.service.listAIModels(accountStore.selectedId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  /// 按任务名分组并排序；keyword 非空时按短名 / 全名 / 描述过滤（对照 iOS filteredGroups）
  groups(keyword: string): AIModelGroup[] {
    const lowered = keyword.trim().toLowerCase();
    const byTask = new Map<string, AIModel[]>();
    for (const model of this.models) {
      if (lowered !== '') {
        const haystack = `${modelShortName(model)} ${model.name ?? ''} ${model.description ?? ''}`.toLowerCase();
        if (!haystack.includes(lowered)) {
          continue;
        }
      }
      const task = model.task?.name ?? '其它';
      const bucket = byTask.get(task);
      if (bucket === undefined) {
        byTask.set(task, [model]);
      } else {
        bucket.push(model);
      }
    }
    const out: AIModelGroup[] = [];
    byTask.forEach((models: AIModel[], task: string) => {
      out.push({ task: task, models: models });
    });
    out.sort((a: AIModelGroup, b: AIModelGroup) => a.task.localeCompare(b.task));
    return out;
  }

  /// 清掉上一次试运行的结果（换模型 / 重开详情时）
  resetRun(): void {
    this.output = '';
    this.image = null;
    this.runError = '';
  }

  async runText(model: string, prompt: string): Promise<void> {
    this.running = true;
    this.resetRun();
    try {
      this.output = await this.service.runTextGeneration(accountStore.selectedId, model, prompt);
    } catch (e) {
      this.runError = (e as Error).message ?? '运行失败';
    } finally {
      this.running = false;
    }
  }

  async runImage(model: string, prompt: string): Promise<void> {
    this.running = true;
    this.resetRun();
    try {
      const buffer = await this.service.runTextToImage(accountStore.selectedId, model, prompt);
      const source = image.createImageSource(buffer);
      this.image = await source.createPixelMap();
    } catch (e) {
      this.runError = (e as Error).message ?? '生成失败';
    } finally {
      this.running = false;
    }
  }
}

/// Workers AI 模型目录（对照 iOS WorkersAIView）：按任务分组 + 搜索 + 模型详情试运行。
/// 试运行支持文本生成与文生图两类；其余任务只读展示。
@ComponentV2
export struct WorkersAIPage {
  @Local vm: AIVM = new AIVM();
  @Local keyword: string = '';
  @Local detailVisible: boolean = false;
  @Local selected: AIModel | null = null;
  @Local prompt: string = '';

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  /// 该模型能否在 App 内试运行，以及走文本还是图片
  private isTextModel(model: AIModel): boolean {
    return (model.task?.name ?? '').includes('Text Generation');
  }

  private isImageModel(model: AIModel): boolean {
    return (model.task?.name ?? '').includes('Text-to-Image');
  }

  private openDetail(model: AIModel): void {
    this.selected = model;
    this.vm.resetRun();
    this.prompt = this.isImageModel(model) ? '' : '用一句话介绍 Cloudflare。';
    this.detailVisible = true;
  }

  private runSelected(): void {
    const model = this.selected;
    if (model === null) {
      return;
    }
    if (!authManager.hasScope(Scopes.AI_WRITE)) {
      this.toast('当前授权未包含 Workers AI 写权限（ai.write），无法试运行');
      return;
    }
    const name = model.name ?? model.id ?? '';
    const text = this.prompt.trim();
    if (name === '' || text === '') {
      return;
    }
    if (this.isImageModel(model)) {
      this.vm.runImage(name, text).catch(() => {
      });
    } else {
      this.vm.runText(name, text).catch(() => {
      });
    }
  }

  @Builder
  modelRow(model: AIModel) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(modelShortName(model))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if ((model.description ?? '') !== '') {
          Text(model.description)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Text(model.name ?? model.id ?? '')
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('sys.media.ohos_ic_public_arrow_right'))
        .width(14)
        .height(14)
        .fillColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .onClick(() => {
      this.openDetail(model);
    })
  }

  /// 模型详情 + 试运行 Playground
  @Builder
  detailSheet() {
    Column({ space: 12 }) {
      Text(this.selected !== null ? modelShortName(this.selected!) : '')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      if (this.selected !== null) {
        if ((this.selected!.task?.name ?? '') !== '') {
          InfoRow({ label: '任务', value: this.selected!.task!.name! })
        }
        Text(this.selected!.name ?? this.selected!.id ?? '')
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
        if ((this.selected!.description ?? '') !== '') {
          Text(this.selected!.description)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        }

        if (this.isTextModel(this.selected!) || this.isImageModel(this.selected!)) {
          Divider()
            .strokeWidth(0.5)
            .color($r('sys.color.comp_divider'))
          Text(this.isImageModel(this.selected!) ? '文生图试运行' : '文本生成试运行')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
          TextArea({
            text: this.prompt,
            placeholder: this.isImageModel(this.selected!) ? '描述你想生成的画面' : '输入提示词',
          })
            .fontSize(13)
            .height(90)
            .width('100%')
            .onChange((value: string) => {
              this.prompt = value;
            })
          Button(this.vm.running ? '运行中…' : (this.isImageModel(this.selected!) ? '生成' : '运行'))
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.oc_brand_cta'))
            .enabled(!this.vm.running && this.prompt.trim() !== '')
            .onClick(() => {
              this.runSelected();
            })

          if (this.vm.runError !== '') {
            Text(this.vm.runError)
              .fontSize(12)
              .fontColor(DANGER_RED)
              .width('100%')
          }
          if (this.vm.output !== '') {
            Text(this.vm.output)
              .fontSize(13)
              .fontColor($r('sys.color.font_primary'))
              .width('100%')
              .padding(14)
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(12)
          }
          if (this.vm.image !== null) {
            Image(this.vm.image)
              .width('100%')
              .objectFit(ImageFit.Contain)
              .borderRadius(12)
              .backgroundColor($r('sys.color.comp_background_list_card'))
          }
        } else {
          Text('该模型类型暂不支持在 App 内试运行，可在 Cloudflare 控制台或用 API 调用。')
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
        }
      }
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载模型…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load().catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.models.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.wand_and_stars'), title: '没有可用模型', subtitle: '未能取到 Workers AI 模型目录。' })
          }
          .width('100%')
          .height('100%')
        } else {
          Column({ space: 10 }) {
            Search({ value: this.keyword, placeholder: '搜索模型' })
              .width('100%')
              .height(40)
              .onChange((value: string) => {
                this.keyword = value;
              })

            if (this.vm.groups(this.keyword).length === 0) {
              Column() {
                OCEmpty({ symbol: $r('sys.symbol.wand_and_stars'), title: '没有匹配的模型', subtitle: `未找到「${this.keyword}」` })
              }
              .width('100%')
              .layoutWeight(1)
            } else {
              Scroll() {
                Column({ space: 16 }) {
                  ForEach(this.vm.groups(this.keyword), (group: AIModelGroup) => {
                    Column({ space: 8 }) {
                      Text(`${group.task}（${group.models.length}）`)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('sys.color.font_secondary'))
                        .width('100%')
                        .padding({ left: 4 })
                      Column() {
                        ForEach(group.models, (model: AIModel, index: number) => {
                          this.modelRow(model)
                          if (index < group.models.length - 1) {
                            Divider()
                              .strokeWidth(0.5)
                              .color($r('sys.color.comp_divider'))
                              .margin({ left: 14 })
                          }
                        }, (model: AIModel) => model.name ?? model.id ?? '')
                      }
                      .width('100%')
                      .backgroundColor($r('sys.color.comp_background_list_card'))
                      .borderRadius(OCLayout.chipRadius)
                      .clip(true)
                    }
                    .width('100%')
                  }, (group: AIModelGroup) => group.task)

                  Text(`共 ${this.vm.models.length} 个模型`)
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                    .width('100%')
                    .padding({ left: 4, bottom: 8 })
                }
                .width('100%')
              }
              .align(Alignment.Top)
              .scrollBar(BarState.Off)
              .layoutWeight(1)
            }
          }
          .width('100%')
          .height('100%')
          .padding(OCLayout.pagePadding)
        }
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: 'Workers AI' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.detailVisible, this.detailSheet(), ocSheet(() => {
      this.detailVisible = false;
    }))
    .onReady(() => {
      this.vm.load().catch(() => {
      });
    })
  }
}
