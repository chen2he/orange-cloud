import { HdsNavDestination } from '@kit.UIDesignKit';
// Workers 脚本列表：点入详情，右下角新建（对齐 Android WorkerListScreen）。
import { WorkerScript } from '../../models/WorkerModels';
import { Routes, NameParam } from '../../models/Routes';
import { WorkerService } from '../../services/WorkerService';
import { accountStore } from '../../core/store/AccountStore';
import { formatTimeAgo } from '../../core/util/Format';
import { BRAND_ORANGE, OCEmpty, OCError, OCLoading, ResourceCard } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';
import { loadSortKey, saveSortKey, sortByDateDesc, sortLabel, SORT_KEYS } from '../common/ResourceSort';

@ObservedV2
class WorkerListVM {
  @Trace scripts: WorkerScript[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';

  private service: WorkerService = new WorkerService();

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      // 自足加载账号：冷启动直奔开发者→Workers 时，概览可能还没填好 selectedId，
      // 之前 eager 传 accountStore.selectedId 会捕获到空串 → /accounts//workers/scripts 报错。
      await accountStore.loadIfNeeded();
      this.scripts = await this.service.listScripts(accountStore.selectedId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }
}

@ComponentV2
export struct WorkerListPage {
  @Local vm: WorkerListVM = new WorkerListVM();
  @Local refreshing: boolean = false;
  /// 列表排序（默认名称 / 创建日期 / 最近更新，选择持久化）
  @Local sortKey: string = 'name';
  private pathStack: NavPathStack | null = null;

  /// 按当前排序给出展示顺序（名称序 = 接口原顺序）
  private sortedScripts(): WorkerScript[] {
    if (this.sortKey === 'created') {
      return sortByDateDesc(this.vm.scripts, (s: WorkerScript) => s.created_on);
    }
    if (this.sortKey === 'modified') {
      return sortByDateDesc(this.vm.scripts, (s: WorkerScript) => s.modified_on);
    }
    return this.vm.scripts;
  }

  @Builder
  sortBar() {
    Row({ space: 8 }) {
      Blank()
      SymbolGlyph($r('sys.symbol.sort'))
        .fontSize(14)
        .fontColor([$r('sys.color.font_secondary')])
      Select(SORT_KEYS.map((k: string): SelectOption => ({ value: sortLabel(k) })))
        .selected(SORT_KEYS.indexOf(this.sortKey))
        .value(sortLabel(this.sortKey))
        .font({ size: 12 })
        .onSelect((index: number) => {
          this.sortKey = SORT_KEYS[index];
          saveSortKey('workers', this.sortKey).catch(() => {
          });
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4 })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading && this.vm.scripts.length === 0) {
          Column() {
            OCLoading({ text: '正在加载 Workers…' })
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
        } else if (this.vm.scripts.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.bolt'), title: '暂无 Worker', subtitle: '点右下角 + 部署第一个脚本' })
          }
          .width('100%')
          .height('100%')
        } else {
          Column() {
          this.sortBar()
          Refresh({ refreshing: this.refreshing }) {
            List() {
              ForEach(this.sortedScripts(), (script: WorkerScript) => {
                ListItem() {
                  ResourceCard({
                    symbol: $r('sys.symbol.bolt'),
                    title: script.id,
                    subtitle: script.modified_on ? `更新于 ${formatTimeAgo(script.modified_on ?? '')}` : '',
                    onTap: () => {
                      const param: NameParam = { name: script.id };
                      this.pathStack?.pushPathByName(Routes.WORKER_DETAIL, param);
                    },
                  })
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
              }, (script: WorkerScript) => script.id)
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
          .layoutWeight(1)
          }
          .width('100%')
          .height('100%')
        }

        Button('+')
          .width(52)
          .height(52)
          .fontSize(26)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.oc_brand_cta'))
          .borderRadius(26)
          .shadow({ radius: 12, color: '#40000000', offsetY: 4 })
          .margin({ right: 20, bottom: 28 })
          .onClick(() => {
            this.pathStack?.pushPathByName(Routes.WORKER_CREATE, null);
          })
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({ content: { title: { mainTitle: 'Workers' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      loadSortKey('workers').then((key: string) => {
        this.sortKey = key;
      }).catch(() => {
      });
      this.vm.load().catch(() => {
      });
    })
    .onShown(() => {
      if (!this.vm.isLoading) {
        this.vm.load().catch(() => {
        });
      }
    })
  }
}
