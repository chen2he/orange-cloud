import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 审计日志：最近 30 天操作记录 + 游标分页续接（对齐 iOS AuditLogViewModel，只读）。
import { AuditLogEntry } from '../../models/AccountModels';
import { AccountModuleService, AuditLogPageResult } from '../../services/AccountModuleService';
import { accountStore } from '../../core/store/AccountStore';
import { formatTimeAgo } from '../../core/util/Format';
import { BRAND_ORANGE, OCEmpty, OCError, OCLoading } from '../common/Components';
import { GlassIsland } from '../common/Daybreak';
import { OCSkyBackground } from '../common/OCSky';

/// 查询窗口：最近 30 天（对齐 iOS windowDays）
const AUDIT_WINDOW_DAYS: number = 30;

@ObservedV2
class AuditVM {
  @Trace entries: AuditLogEntry[] = [];
  @Trace isLoading: boolean = false;
  @Trace isLoadingMore: boolean = false;
  @Trace cursor: string = '';
  @Trace error: string = '';
  // 时间窗在首次加载时固定，续页复用同一窗口（游标分页要求查询参数一致）
  private sinceIso: string = '';
  private beforeIso: string = '';
  private service: AccountModuleService = new AccountModuleService();

  async load(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    this.error = '';
    this.cursor = '';
    this.beforeIso = new Date().toISOString();
    this.sinceIso = new Date(Date.now() - AUDIT_WINDOW_DAYS * 24 * 3600 * 1000).toISOString();
    try {
      const page: AuditLogPageResult = await this.service.auditLogsPage(
        accountStore.selectedId, this.sinceIso, this.beforeIso, '');
      this.entries = page.entries;
      this.cursor = page.cursor;
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  // ---- 资源变更历史 ----
  @Trace historyOpen: boolean = false;
  @Trace historyEntries: AuditLogEntry[] = [];
  @Trace historyLoading: boolean = false;
  @Trace historyStatus: string = '';
  @Trace historyError: string = '';
  @Trace historyResource: string = '';

  // 查同一资源在同一 30 天窗口内的其它变更。entry 必须同时有 id 与时间戳，接口靠这两项定位资源。
  async openHistory(entry: AuditLogEntry): Promise<void> {
    const entryId: string = entry.id ?? '';
    const actionTime: string = entry.when ?? '';
    if (entryId === '' || actionTime === '') {
      return;
    }
    this.historyOpen = true;
    this.historyEntries = [];
    this.historyStatus = '';
    this.historyError = '';
    this.historyLoading = true;
    this.historyResource = entry.resource?.type ?? '';
    try {
      const page: AuditLogPageResult = await this.service.auditResourceHistory(
        accountStore.selectedId, entryId, actionTime, this.sinceIso, this.beforeIso);
      this.historyEntries = page.entries;
      this.historyStatus = page.historyStatus ?? '';
    } catch (e) {
      this.historyError = (e as Error).message ?? '加载失败';
    } finally {
      this.historyLoading = false;
    }
  }

  async loadMore(): Promise<void> {
    if (this.isLoading || this.isLoadingMore || this.cursor === '') {
      return;
    }
    this.isLoadingMore = true;
    try {
      const page: AuditLogPageResult = await this.service.auditLogsPage(
        accountStore.selectedId, this.sinceIso, this.beforeIso, this.cursor);
      this.entries = this.entries.concat(page.entries);
      this.cursor = page.cursor;
    } catch (e) {
    } finally {
      this.isLoadingMore = false;
    }
  }
}

function resultColor(result: string): string {
  return result === 'success' ? '#22C55E' : '#DC2626';
}

// 识别质量说明。approximate 时结果可能混入无关条目，必须写明而不是假装精确。
function historyNote(status: string): string {
  if (status === 'unavailable') {
    return '这条记录没有携带足够信息来定位资源，因此查不到它的变更历史。';
  }
  if (status === 'approximate') {
    return '这条记录没有资源地址，只能按其它字段近似匹配，列表里可能混入无关变更。';
  }
  return '同一资源在最近 30 天内的全部变更，最新在上。';
}

@ComponentV2
export struct AuditLogPage {
  @Local vm: AuditVM = new AuditVM();
  @Local refreshing: boolean = false;

  @Builder
  HistorySheet() {
    Column({ space: 10 }) {
      if (this.vm.historyResource !== '') {
        Text(this.vm.historyResource)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
      }
      Text(historyNote(this.vm.historyStatus))
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      if (this.vm.historyLoading) {
        LoadingProgress().width(28).height(28).margin({ top: 24 })
      } else if (this.vm.historyError !== '') {
        Text(this.vm.historyError)
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
      } else if (this.vm.historyEntries.length === 0) {
        Text('没有查到这个资源的其它变更。')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
      } else {
        List({ space: 8 }) {
          ForEach(this.vm.historyEntries, (entry: AuditLogEntry) => {
            ListItem() {
              GlassIsland({ pad: 12 }) {
                Row({ space: 10 }) {
                  Circle({ width: 8, height: 8 })
                    .fill(resultColor(entry.action?.result ?? ''))
                    .margin({ top: 5 })
                  Column({ space: 3 }) {
                    Text(entry.action?.type ?? '操作')
                      .fontSize(13)
                      .fontColor($r('sys.color.font_primary'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${entry.actor?.email ?? entry.actor?.type ?? ''} · ${formatTimeAgo(entry.when ?? '')}`)
                      .fontSize(11)
                      .fontColor($r('sys.color.font_secondary'))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
              }
            }
          }, (entry: AuditLogEntry, index: number) => `h-${entry.id ?? ''}-${index}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading && this.vm.entries.length === 0) {
          Column() {
            OCLoading({ text: '正在加载审计日志…' })
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
        } else if (this.vm.entries.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.doc_text'), title: '近 30 天无审计记录' })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            List() {
              ForEach(this.vm.entries, (entry: AuditLogEntry) => {
                ListItem() {
                  GlassIsland({ pad: 14 }) {
                    Row({ space: 10 }) {
                      Circle({ width: 8, height: 8 })
                        .fill(resultColor(entry.action?.result ?? ''))
                        .margin({ top: 6 })
                      Column({ space: 3 }) {
                        Text(`${entry.action?.type ?? '操作'} · ${entry.resource?.type ?? ''}`)
                          .fontSize(14)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('sys.color.font_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(`${entry.actor?.email ?? entry.actor?.type ?? ''} · ${formatTimeAgo(entry.when ?? '')}`)
                          .fontSize(11)
                          .fontColor($r('sys.color.font_secondary'))
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Top)
                  }
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
                .onClick(() => {
                  this.vm.openHistory(entry).catch(() => {
                  });
                })
              }, (entry: AuditLogEntry, index: number) => `${entry.id ?? ''}-${index}`)
              if (this.vm.cursor !== '') {
                ListItem() {
                  Text(this.vm.isLoadingMore ? '正在加载…' : '加载更多')
                    .fontSize(13)
                    .fontColor($r('app.color.oc_brand_text'))
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .padding(16)
                    .onClick(() => {
                      this.vm.loadMore().catch(() => {
                      });
                    })
                }
              } else {
                ListItem() {
                  Text('仅显示当前账号最近 30 天的操作记录')
                    .fontSize(11)
                    .fontColor($r('sys.color.font_tertiary'))
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .padding(16)
                }
              }
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
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
      .bindSheet($$this.vm.historyOpen, this.HistorySheet(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        title: { title: '变更历史' },
      })
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: '审计日志' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady(() => {
      this.vm.load().catch(() => {
      });
    })
  }
}
