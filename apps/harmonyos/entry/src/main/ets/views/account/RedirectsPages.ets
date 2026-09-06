import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// Bulk Redirects：重定向列表（查看/新建/删除）→ 条目查看（对齐 Android RedirectScreens）。
import { RedirectList, RedirectListItem } from '../../models/AccountModels';
import { Routes, IdNameParam } from '../../models/Routes';
import { AccountModuleService } from '../../services/AccountModuleService';
import { accountStore } from '../../core/store/AccountStore';
import { BRAND_ORANGE, BRAND_ORANGE_BG, OCEmpty, OCError, OCLoading, ResourceCard } from '../common/Components';
import { GlassIsland } from '../common/Daybreak';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

@ObservedV2
class RedirectListsVM {
  @Trace lists: RedirectList[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  @Trace isCreating: boolean = false;
  @Trace createError: string = '';
  private service: AccountModuleService = new AccountModuleService();

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.lists = await this.service.redirectLists(accountStore.selectedId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async create(name: string, description: string): Promise<boolean> {
    this.isCreating = true;
    this.createError = '';
    try {
      await this.service.createRedirectList(accountStore.selectedId, name, description);
      await this.load();
      return true;
    } catch (e) {
      this.createError = (e as Error).message ?? '创建失败';
      return false;
    } finally {
      this.isCreating = false;
    }
  }

  async remove(listId: string): Promise<string> {
    try {
      await this.service.deleteRedirectList(accountStore.selectedId, listId);
      this.lists = this.lists.filter((l: RedirectList) => l.id !== listId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct RedirectListsPage {
  @Local vm: RedirectListsVM = new RedirectListsVM();
  @Local refreshing: boolean = false;
  @Local showCreate: boolean = false;
  @Local fName: string = '';
  @Local fDesc: string = '';
  private pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  @Builder
  createSheet() {
    Column({ space: 12 }) {
      Text('新建重定向列表')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.fName, placeholder: '列表名（小写字母/数字/下划线）' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fName = value;
        })
      TextInput({ text: this.fDesc, placeholder: '描述（可选）' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fDesc = value;
        })
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
        .enabled(!this.vm.isCreating && this.fName.trim() !== '')
        .onClick(() => {
          this.vm.create(this.fName.trim(), this.fDesc.trim()).then((ok: boolean) => {
            if (ok) {
              this.showCreate = false;
              this.fName = '';
              this.fDesc = '';
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
        if (this.vm.isLoading && this.vm.lists.length === 0) {
          Column() {
            OCLoading({ text: '正在加载重定向列表…' })
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
        } else if (this.vm.lists.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.arrow_right'), title: '暂无重定向列表', subtitle: '点右下角 + 创建' })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            List() {
              ForEach(this.vm.lists, (list: RedirectList) => {
                ListItem() {
                  ResourceCard({
                    symbol: $r('sys.symbol.arrow_right'),
                    title: list.name,
                    subtitle: `${list.num_items ?? 0} 条`,
                    onTap: () => {
                      const param: IdNameParam = { id: list.id, name: list.name };
                      this.pathStack?.pushPathByName(Routes.REDIRECT_ITEMS, param);
                    },
                    onLongPress: () => {
                      this.vm.remove(list.id).then((err: string) => {
                        this.toast(err === '' ? '已删除' : err);
                      });
                    },
                  })
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
              }, (list: RedirectList) => list.id)
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
            this.showCreate = true;
          })
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({ content: { title: { mainTitle: '批量重定向' } } })
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

@ObservedV2
class RedirectItemsVM {
  @Trace items: RedirectListItem[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  @Trace isSaving: boolean = false;
  private service: AccountModuleService = new AccountModuleService();

  async load(listId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.items = await this.service.listItems(accountStore.selectedId, listId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async add(listId: string, source: string, target: string, statusCode: number): Promise<string> {
    this.isSaving = true;
    try {
      await this.service.addItem(accountStore.selectedId, listId, source, target, statusCode);
      // bulk operation 异步，稍候刷新
      await this.load(listId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '添加失败';
    } finally {
      this.isSaving = false;
    }
  }

  async remove(listId: string, itemId: string): Promise<string> {
    try {
      await this.service.deleteItem(accountStore.selectedId, listId, itemId);
      this.items = this.items.filter((i: RedirectListItem) => i.id !== itemId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct RedirectItemsPage {
  @Local vm: RedirectItemsVM = new RedirectItemsVM();
  @Local listId: string = '';
  @Local listName: string = '';
  @Local showAdd: boolean = false;
  @Local fSource: string = '';
  @Local fTarget: string = '';
  @Local fStatus: number = 301;

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  @Builder
  addSheet() {
    Column({ space: 12 }) {
      Text('添加重定向条目')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.fSource, placeholder: '源 URL，如 example.com/old' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fSource = value;
        })
      TextInput({ text: this.fTarget, placeholder: '目标 URL，如 https://example.com/new' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fTarget = value;
        })
      Row({ space: 12 }) {
        Text('状态码')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Select([{ value: '301 永久' } as SelectOption, { value: '302 临时' } as SelectOption,
          { value: '307' } as SelectOption, { value: '308' } as SelectOption])
          .selected(this.fStatus === 301 ? 0 : (this.fStatus === 302 ? 1 : (this.fStatus === 307 ? 2 : 3)))
          .value(`${this.fStatus}`)
          .font({ size: 14 })
          .onSelect((index: number) => {
            this.fStatus = [301, 302, 307, 308][index];
          })
      }
      .width('100%')
      Button(this.vm.isSaving ? '正在添加…' : '添加')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isSaving && this.fSource.trim() !== '' && this.fTarget.trim() !== '')
        .onClick(() => {
          this.vm.add(this.listId, this.fSource.trim(), this.fTarget.trim(), this.fStatus).then((err: string) => {
            if (err === '') {
              this.showAdd = false;
              this.fSource = '';
              this.fTarget = '';
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
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载条目…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load(this.listId).catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.items.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.arrow_right'), title: '空列表', subtitle: '点右下角 + 添加条目' })
          }
          .width('100%')
          .height('100%')
        } else {
          List() {
            ForEach(this.vm.items, (item: RedirectListItem) => {
              ListItem() {
                GlassIsland({ pad: 14 }) {
                  Column({ space: 5 }) {
                    Text(item.redirect?.source_url ?? '')
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('sys.color.font_primary'))
                      .width('100%')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Row({ space: 6 }) {
                      Text(`→ ${item.redirect?.target_url ?? ''}`)
                        .fontSize(12)
                        .fontColor($r('app.color.oc_brand_text'))
                        .layoutWeight(1)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(`${item.redirect?.status_code ?? 301}`)
                        .fontSize(11)
                        .fontColor($r('sys.color.font_tertiary'))
                    }
                    .width('100%')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .gesture(LongPressGesture().onAction(() => {
                    const id = item.id;
                    if (id) {
                      this.vm.remove(this.listId, id).then((err: string) => {
                        this.toast(err === '' ? '已删除' : err);
                      });
                    }
                  }))
                }
              }
              .margin({ left: 16, right: 16, top: 5, bottom: 5 })
            }, (item: RedirectListItem, index: number) => item.id ?? `${index}`)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
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
            this.showAdd = true;
          })
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({ content: { title: { mainTitle: this.listName } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.showAdd, this.addSheet(), ocSheet(() => {
      this.showAdd = false;
    }))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as IdNameParam;
      this.listId = param.id;
      this.listName = param.name;
      this.vm.load(param.id).catch(() => {
      });
    })
  }
}
