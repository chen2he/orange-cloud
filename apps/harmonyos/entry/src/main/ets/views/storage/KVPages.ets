import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// KV：命名空间列表 → 键列表（游标分页）+ 读/写/删值（对齐 Android KVScreens）。
import { KVKey, KVNamespace } from '../../models/StorageModels';
import { Routes, IdNameParam } from '../../models/Routes';
import { StorageService, CursorPage } from '../../services/StorageService';
import { accountStore } from '../../core/store/AccountStore';
import { BRAND_ORANGE, BRAND_ORANGE_BG, OCEmpty, OCError, OCLoading, ResourceCard } from '../common/Components';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

@ObservedV2
class NamespacesVM {
  @Trace namespaces: KVNamespace[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  @Trace isCreating: boolean = false;
  private service: StorageService = new StorageService();

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.namespaces = await this.service.listNamespaces(accountStore.selectedId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async create(title: string): Promise<string> {
    this.isCreating = true;
    try {
      const created = await this.service.createNamespace(accountStore.selectedId, title);
      this.namespaces = this.namespaces.concat([created]);
      return '';
    } catch (e) {
      return (e as Error).message ?? '创建失败';
    } finally {
      this.isCreating = false;
    }
  }

  async remove(namespaceId: string): Promise<string> {
    try {
      await this.service.deleteNamespace(accountStore.selectedId, namespaceId);
      this.namespaces = this.namespaces.filter((n: KVNamespace) => n.id !== namespaceId);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct KVNamespacesPage {
  @Local vm: NamespacesVM = new NamespacesVM();
  @Local refreshing: boolean = false;
  @Local showCreate: boolean = false;
  @Local fTitle: string = '';
  private pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  @Builder
  createSheet() {
    Column({ space: 12 }) {
      Text('新建命名空间')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.fTitle, placeholder: '命名空间名称' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fTitle = value;
        })
      Button(this.vm.isCreating ? '正在创建…' : '创建')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isCreating && this.fTitle.trim() !== '')
        .onClick(() => {
          this.vm.create(this.fTitle.trim()).then((err: string) => {
            if (err === '') {
              this.showCreate = false;
              this.fTitle = '';
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
        if (this.vm.isLoading && this.vm.namespaces.length === 0) {
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
        } else if (this.vm.namespaces.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.folder'), title: '暂无 KV 命名空间', subtitle: '点右下角 + 创建' })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            List() {
              ForEach(this.vm.namespaces, (ns: KVNamespace) => {
                ListItem() {
                  ResourceCard({
                    symbol: $r('sys.symbol.folder'),
                    title: ns.title,
                    onTap: () => {
                      const param: IdNameParam = { id: ns.id, name: ns.title };
                      this.pathStack?.pushPathByName(Routes.KV_KEYS, param);
                    },
                    onLongPress: () => {
                      this.vm.remove(ns.id).then((err: string) => {
                        this.toast(err === '' ? '已删除' : err);
                      });
                    },
                  })
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
              }, (ns: KVNamespace) => ns.id)
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
          .margin({ right: 20, bottom: 28 })
          .onClick(() => {
            this.showCreate = true;
          })
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: 'KV 命名空间' } } })
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
class KVKeysVM {
  @Trace keys: KVKey[] = [];
  @Trace isLoading: boolean = false;
  @Trace isLoadingMore: boolean = false;
  @Trace error: string = '';
  @Trace cursor: string = '';
  @Trace editingKey: string = '';
  @Trace editingValue: string = '';
  @Trace valueLoading: boolean = false;
  private service: StorageService = new StorageService();

  async load(nsId: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    this.cursor = '';
    try {
      const page: CursorPage<KVKey> = await this.service.listKeys(accountStore.selectedId, nsId, '');
      this.keys = page.items;
      this.cursor = page.cursor;
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async loadMore(nsId: string): Promise<void> {
    if (this.isLoadingMore || this.cursor === '') {
      return;
    }
    this.isLoadingMore = true;
    try {
      const page: CursorPage<KVKey> = await this.service.listKeys(accountStore.selectedId, nsId, this.cursor);
      this.keys = this.keys.concat(page.items);
      this.cursor = page.cursor;
    } catch (e) {
    } finally {
      this.isLoadingMore = false;
    }
  }

  async openValue(nsId: string, key: string): Promise<void> {
    this.editingKey = key;
    this.editingValue = '';
    this.valueLoading = true;
    try {
      this.editingValue = await this.service.getValue(accountStore.selectedId, nsId, key);
    } catch (e) {
      this.editingValue = '';
    } finally {
      this.valueLoading = false;
    }
  }

  async saveValue(nsId: string, key: string, value: string): Promise<string> {
    try {
      await this.service.putValue(accountStore.selectedId, nsId, key, value);
      if (!this.keys.some((k: KVKey) => k.name === key)) {
        this.keys = [{ name: key } as KVKey].concat(this.keys);
      }
      return '';
    } catch (e) {
      return (e as Error).message ?? '保存失败';
    }
  }

  async remove(nsId: string, key: string): Promise<string> {
    try {
      await this.service.deleteKey(accountStore.selectedId, nsId, key);
      this.keys = this.keys.filter((k: KVKey) => k.name !== key);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct KVKeysPage {
  @Local vm: KVKeysVM = new KVKeysVM();
  @Local refreshing: boolean = false;
  @Local nsId: string = '';
  @Local nsTitle: string = '';
  @Local editorVisible: boolean = false;
  @Local isNewKey: boolean = false;

  private toast(message: string): void {
    if (message !== '') {
      ocSnack(this.getUIContext(), message);
    }
  }

  private confirmDelete(key: KVKey): void {
    this.getUIContext().showAlertDialog({
      title: '删除键',
      message: `确定删除「${key.name}」？`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.remove(this.nsId, key.name).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  @Builder
  editorSheet() {
    Column({ space: 12 }) {
      Text(this.isNewKey ? '写入键值' : this.vm.editingKey)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })

      if (this.isNewKey) {
        TextInput({ text: this.vm.editingKey, placeholder: '键名' })
          .fontSize(14)
          .width('100%')
          .onChange((value: string) => {
            this.vm.editingKey = value;
          })
      }

      if (this.vm.valueLoading) {
        Text('正在加载值…')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
      }

      TextArea({ text: this.vm.editingValue, placeholder: '值' })
        .fontSize(13)
        .height(160)
        .width('100%')
        .onChange((value: string) => {
          this.vm.editingValue = value;
        })

      Button('保存')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(this.vm.editingKey.trim() !== '')
        .onClick(() => {
          this.vm.saveValue(this.nsId, this.vm.editingKey.trim(), this.vm.editingValue).then((err: string) => {
            if (err === '') {
              this.editorVisible = false;
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
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading && this.vm.keys.length === 0) {
          Column() {
            OCLoading({ text: '正在加载键…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load(this.nsId).catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.keys.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.key'), title: '暂无键', subtitle: '点右下角 + 写入第一个键值' })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            List() {
              ForEach(this.vm.keys, (key: KVKey) => {
                ListItem() {
                  ResourceCard({
                    symbol: $r('sys.symbol.key'),
                    title: key.name,
                    subtitle: '',
                    onTap: () => {
                      this.isNewKey = false;
                      this.editorVisible = true;
                      this.vm.openValue(this.nsId, key.name).catch(() => {
                      });
                    },
                    onLongPress: () => {
                      this.confirmDelete(key);
                    },
                  })
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
              }, (key: KVKey) => key.name)
              if (this.vm.cursor !== '') {
                ListItem() {
                  Text(this.vm.isLoadingMore ? '正在加载…' : '加载更多')
                    .fontSize(13)
                    .fontColor($r('app.color.oc_brand_text'))
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .padding(16)
                    .onClick(() => {
                      this.vm.loadMore(this.nsId).catch(() => {
                      });
                    })
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
            this.vm.load(this.nsId).then(() => {
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
          .margin({ right: 20, bottom: 28 })
          .onClick(() => {
            this.isNewKey = true;
            this.vm.editingKey = '';
            this.vm.editingValue = '';
            this.editorVisible = true;
          })
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: this.nsTitle } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.editorVisible, this.editorSheet(), ocSheet(() => {
      this.editorVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as IdNameParam;
      this.nsId = param.id;
      this.nsTitle = param.name;
      this.vm.load(param.id).catch(() => {
      });
    })
  }
}
