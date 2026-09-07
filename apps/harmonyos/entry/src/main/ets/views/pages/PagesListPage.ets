import { OCAddActionBar, OC_ACTION_BAR_CLEARANCE } from '../common/ActionBar';
import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { HdsNavDestination } from '@kit.UIDesignKit';
// Cloudflare Pages 项目列表 + 新建（对齐 Android PagesScreens）。
import { PagesProject } from '../../models/WorkerModels';
import { Routes, NameParam } from '../../models/Routes';
import { PagesService } from '../../services/PagesService';
import { accountStore } from '../../core/store/AccountStore';
import { BRAND_ORANGE, OCEmpty, OCError, OCLoading, ResourceCard } from '../common/Components';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';
import { loadSortKey, saveSortKey, sortByDateDesc, sortLabel, SORT_KEYS } from '../common/ResourceSort';

@ObservedV2
class PagesListVM {
  @Trace projects: PagesProject[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  @Trace isCreating: boolean = false;
  @Trace createError: string = '';
  private service: PagesService = new PagesService();

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.projects = await this.service.listProjects(accountStore.selectedId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async create(name: string, branch: string): Promise<boolean> {
    this.isCreating = true;
    this.createError = '';
    try {
      await this.service.createProject(accountStore.selectedId, name, branch);
      await this.load();
      return true;
    } catch (e) {
      this.createError = (e as Error).message ?? '创建失败';
      return false;
    } finally {
      this.isCreating = false;
    }
  }
}

@ComponentV2
export struct PagesListPage {
  @Local vm: PagesListVM = new PagesListVM();
  @Local refreshing: boolean = false;
  /// 列表排序（默认名称 / 创建日期 / 最近更新，选择持久化）
  @Local sortKey: string = 'name';
  @Local showCreate: boolean = false;
  @Local fName: string = '';
  @Local fBranch: string = 'main';
  private pathStack: NavPathStack | null = null;

  @Builder
  createSheet() {
    Column({ space: 12 }) {
      Text('新建 Pages 项目')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.fName, placeholder: '项目名（小写字母/数字/连字符）' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fName = value;
        })
      TextInput({ text: this.fBranch, placeholder: '生产分支，如 main' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fBranch = value;
        })
      if (this.fName.trim() !== '' && !/^[a-z0-9][a-z0-9-]*$/.test(this.fName.trim())) {
        Text('项目名仅能含小写字母、数字与连字符，CF 会拒绝其它字符')
          .fontSize(12)
          .fontColor('#DC2626')
          .width('100%')
      }
      if (this.vm.createError !== '') {
        Text(this.vm.createError)
          .fontSize(13)
          .fontColor('#DC2626')
          .width('100%')
      }
      Button(this.vm.isCreating ? '正在创建…' : '创建')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isCreating && /^[a-z0-9][a-z0-9-]*$/.test(this.fName.trim()))
        .onClick(() => {
          this.vm.create(this.fName.trim(), this.fBranch.trim() === '' ? 'main' : this.fBranch.trim())
            .then((ok: boolean) => {
              if (ok) {
                this.showCreate = false;
                this.fName = '';
              }
            });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  /// 按当前排序给出展示顺序（名称序 = 接口原顺序；最近更新取最近一次部署的时间）
  private sortedProjects(): PagesProject[] {
    if (this.sortKey === 'created') {
      return sortByDateDesc(this.vm.projects, (p: PagesProject) => p.created_on);
    }
    if (this.sortKey === 'modified') {
      return sortByDateDesc(this.vm.projects, (p: PagesProject) =>
        p.latest_deployment?.modified_on ?? p.latest_deployment?.created_on ?? p.created_on);
    }
    return this.vm.projects;
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
          saveSortKey('pages', this.sortKey).catch(() => {
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
        if (this.vm.isLoading && this.vm.projects.length === 0) {
          Column() {
            OCLoading({ text: '正在加载 Pages…' })
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
        } else if (this.vm.projects.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.doc_text'), title: '暂无 Pages 项目', subtitle: '点右下角 + 创建' })
          }
          .width('100%')
          .height('100%')
        } else {
          Column() {
          this.sortBar()
          Refresh({ refreshing: this.refreshing }) {
            List() {
              ForEach(this.sortedProjects(), (project: PagesProject) => {
                ListItem() {
                  ResourceCard({
                    symbol: $r('sys.symbol.doc_text'),
                    title: project.name,
                    subtitle: project.subdomain ?? `${project.name}.pages.dev`,
                    onTap: () => {
                      const param: NameParam = { name: project.name };
                      this.pathStack?.pushPathByName(Routes.PAGES_DETAIL, param);
                    },
                  })
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
              }, (project: PagesProject) => project.name)
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
          .layoutWeight(1)
          }
          .width('100%')
          .height('100%')
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
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: 'Pages' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.showCreate, this.createSheet(), ocSheet(() => {
      this.showCreate = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      loadSortKey('pages').then((key: string) => {
        this.sortKey = key;
      }).catch(() => {
      });
      this.vm.load().catch(() => {
      });
    })
  }
}
