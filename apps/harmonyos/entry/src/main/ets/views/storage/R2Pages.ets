import { HdsNavDestination } from '@kit.UIDesignKit';
// R2：存储桶列表 → 对象浏览（游标分页）+ 对象文本/文件上传 + 查看/详情/复制/移动/删除（对齐 Android R2Screens + iOS R2ObjectListView）。
import { R2Bucket, R2Object, R2ObjectPage, R2PreviewKind, previewKindOf, mimeOf, extOf } from '../../models/StorageModels';
import { Routes, NameParam, IdNameParam } from '../../models/Routes';
import { StorageService, CursorPage } from '../../services/StorageService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { formatBytes, formatTimeAgo } from '../../core/util/Format';
import { BRAND_ORANGE, BRAND_ORANGE_BG, InfoRow, OCEmpty, OCError, OCLoading, ResourceCard } from '../common/Components';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { fileUri } from '@kit.CoreFileKit';
import { filePreview } from '@kit.PreviewKit';
import { common } from '@kit.AbilityKit';
import { GlobalContext } from '../../core/system/GlobalContext';
import { withDataTransfer } from '../../core/system/BackgroundTransfer';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

/// 复制/移动客户端内存保护上限：100MB（iOS 上限 300MB，移动端从紧——字节须整段过设备内存）
const MAX_TRANSFER_BYTES = 100 * 1024 * 1024;

/// 复制默认名：在扩展名前插入「-副本」（无扩展名则末尾追加）
function copyDefaultName(key: string): string {
  const ext = extOf(key);
  if (ext === '') {
    return `${key}-副本`;
  }
  const base = key.substring(0, key.length - ext.length - 1);
  return `${base}-副本.${ext}`;
}

@ObservedV2
class BucketsVM {
  @Trace buckets: R2Bucket[] = [];
  @Trace isLoading: boolean = false;
  @Trace error: string = '';
  @Trace isCreating: boolean = false;
  @Trace createError: string = '';
  private service: StorageService = new StorageService();

  async load(): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      this.buckets = await this.service.listBuckets(accountStore.selectedId);
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  async create(name: string): Promise<boolean> {
    this.isCreating = true;
    this.createError = '';
    try {
      await this.service.createBucket(accountStore.selectedId, name);
      await this.load();
      return true;
    } catch (e) {
      this.createError = (e as Error).message ?? '创建失败';
      return false;
    } finally {
      this.isCreating = false;
    }
  }

  async remove(bucket: string): Promise<string> {
    try {
      await this.service.deleteBucket(accountStore.selectedId, bucket);
      this.buckets = this.buckets.filter((b: R2Bucket) => b.name !== bucket);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败（桶需先清空）';
    }
  }
}

@ComponentV2
export struct R2BucketsPage {
  @Local vm: BucketsVM = new BucketsVM();
  @Local refreshing: boolean = false;
  @Local showCreate: boolean = false;
  @Local fName: string = '';
  private pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  @Builder
  createSheet() {
    Column({ space: 12 }) {
      Text('新建存储桶')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      TextInput({ text: this.fName, placeholder: '桶名（小写字母/数字/连字符）' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fName = value;
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
          this.vm.create(this.fName.trim()).then((ok: boolean) => {
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

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading && this.vm.buckets.length === 0) {
          Column() {
            OCLoading({ text: '正在加载存储桶…' })
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
        } else if (this.vm.buckets.length === 0) {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.externaldrive'), title: '暂无存储桶', subtitle: '点右下角 + 创建' })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            List() {
              ForEach(this.vm.buckets, (bucket: R2Bucket) => {
                ListItem() {
                  ResourceCard({
                    symbol: $r('sys.symbol.externaldrive'),
                    title: bucket.name,
                    subtitle: bucket.location ?? '',
                    onTap: () => {
                      const param: NameParam = { name: bucket.name };
                      this.pathStack?.pushPathByName(Routes.R2_OBJECTS, param);
                    },
                    onLongPress: () => {
                      this.vm.remove(bucket.name).then((err: string) => {
                        this.toast(err === '' ? '已删除' : err);
                      });
                    },
                  })
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
              }, (bucket: R2Bucket) => bucket.name)
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
    .titleBar({ content: { title: { mainTitle: 'R2 存储桶' } } })
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
class ObjectsVM {
  @Trace objects: R2Object[] = [];
  @Trace folders: string[] = [];
  @Trace currentPrefix: string = '';
  @Trace isLoading: boolean = false;
  @Trace isLoadingMore: boolean = false;
  @Trace error: string = '';
  @Trace cursor: string = '';
  @Trace viewerText: string = '';
  @Trace viewerKey: string = '';
  @Trace isTransferring: boolean = false;
  private service: StorageService = new StorageService();

  /// 对象 key 去掉当前前缀 → 叶子名（当前层文件名）
  leafName(key: string): string {
    if (this.currentPrefix !== '' && key.startsWith(this.currentPrefix)) {
      return key.substring(this.currentPrefix.length);
    }
    return key;
  }

  /// 折叠前缀 → 显示名（末段文件夹名，如 a/b/ 相对 a/ 显示 b）
  folderName(prefix: string): string {
    let rel = prefix;
    if (this.currentPrefix !== '' && prefix.startsWith(this.currentPrefix)) {
      rel = prefix.substring(this.currentPrefix.length);
    }
    const trimmed = rel.endsWith('/') ? rel.substring(0, rel.length - 1) : rel;
    const slash = trimmed.lastIndexOf('/');
    return slash >= 0 ? trimmed.substring(slash + 1) : trimmed;
  }

  /// 上一级前缀（a/b/c/ → a/b/；a/ → 根 ''）
  parentPrefix(): string {
    const trimmed = this.currentPrefix.endsWith('/')
      ? this.currentPrefix.substring(0, this.currentPrefix.length - 1)
      : this.currentPrefix;
    const slash = trimmed.lastIndexOf('/');
    return slash >= 0 ? trimmed.substring(0, slash + 1) : '';
  }

  async load(bucket: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    this.cursor = '';
    try {
      const page: R2ObjectPage = await this.service.listObjects(accountStore.selectedId, bucket, this.currentPrefix, '');
      this.objects = page.objects;
      this.folders = page.folders;
      this.cursor = page.cursor;
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  /// 进入子文件夹：切前缀并重载
  async openFolder(bucket: string, prefix: string): Promise<void> {
    this.currentPrefix = prefix;
    await this.load(bucket);
  }

  /// 返回上一级
  async goUp(bucket: string): Promise<void> {
    this.currentPrefix = this.parentPrefix();
    await this.load(bucket);
  }

  async loadMore(bucket: string): Promise<void> {
    if (this.isLoadingMore || this.cursor === '') {
      return;
    }
    this.isLoadingMore = true;
    try {
      const page: R2ObjectPage = await this.service.listObjects(accountStore.selectedId, bucket, this.currentPrefix, this.cursor);
      this.objects = this.objects.concat(page.objects);
      // 折叠前缀去重合并
      for (const f of page.folders) {
        if (!this.folders.includes(f)) {
          this.folders = this.folders.concat([f]);
        }
      }
      this.cursor = page.cursor;
    } catch (e) {
    } finally {
      this.isLoadingMore = false;
    }
  }

  /// 对象是否可交系统预览（图片/PDF/音视频/文档）——文本/JSON 仍走 App 内查看器。
  isMedia(key: string): boolean {
    return previewKindOf(key) === R2PreviewKind.MEDIA;
  }

  async view(bucket: string, key: string): Promise<void> {
    this.viewerKey = key;
    this.viewerText = '正在加载…';
    try {
      const text = await this.service.getObjectText(accountStore.selectedId, bucket, key);
      this.viewerText = text.length > 5000 ? `${text.substring(0, 5000)}\n…（已截断）` : text;
    } catch (e) {
      this.viewerText = `无法预览：${(e as Error).message ?? ''}`;
    }
  }

  /// 叶子名（含扩展名）——用作临时文件名 / 保存默认名
  private leaf(key: string): string {
    const slash = key.lastIndexOf('/');
    return slash >= 0 ? key.substring(slash + 1) : key;
  }

  /// 把对象字节写入 App 缓存目录的临时文件，返回沙箱路径（供 Preview Kit / 系统预览）
  private async downloadToCache(bucket: string, key: string): Promise<string> {
    const buffer = await withDataTransfer<ArrayBuffer>(() =>
      this.service.getObjectBytes(accountStore.selectedId, bucket, key));
    const context = GlobalContext.get();
    const dir = context.cacheDir;
    // 前缀去重避免同名覆盖冲突；保留原叶子名让预览标题/后缀正确
    const path = `${dir}/preview_${Date.now().toString(16)}_${this.leaf(key)}`;
    const fd = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(fd.fd, buffer);
    } finally {
      fileIo.closeSync(fd.fd);
    }
    return path;
  }

  /// 系统预览：下载到临时文件 → canIUse + canPreview 守卫 → filePreview.openPreview；
  /// 失败/不支持时抛错，由调用方回退到 App 内文本查看器。
  async preview(bucket: string, key: string): Promise<void> {
    const context: common.UIAbilityContext = GlobalContext.get();
    const path = await this.downloadToCache(bucket, key);
    const uri = fileUri.getUriFromPath(path);
    const previewable = await filePreview.canPreview(context, uri);
    if (!previewable) {
      throw new Error('该类型暂不支持系统预览');
    }
    const info: filePreview.PreviewInfo = {
      title: this.leaf(key),
      uri: uri,
      mimeType: mimeOf(key),
    };
    await filePreview.openPreview(context, info);
  }

  /// 保存到设备：DocumentViewPicker save 选目标 → 取对象字节 → 写入所选 URI。
  /// 返回 ''=成功、'cancel'=用户取消、其它=错误信息。
  async saveToDevice(bucket: string, key: string): Promise<string> {
    let fd = -1;
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [this.leaf(key)];
      const documentPicker = new picker.DocumentViewPicker();
      const uris = await documentPicker.save(options);
      if (!uris || uris.length === 0) {
        return 'cancel';
      }
      const destUri = uris[0];
      const buffer = await withDataTransfer<ArrayBuffer>(() =>
        this.service.getObjectBytes(accountStore.selectedId, bucket, key));
      const file = fileIo.openSync(destUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fd = file.fd;
      fileIo.writeSync(fd, buffer);
      return '';
    } catch (e) {
      return (e as Error).message ?? '保存失败';
    } finally {
      if (fd >= 0) {
        try {
          fileIo.closeSync(fd);
        } catch (e) {
        }
      }
    }
  }

  async remove(bucket: string, key: string): Promise<string> {
    try {
      await this.service.deleteObject(accountStore.selectedId, bucket, key);
      this.objects = this.objects.filter((o: R2Object) => o.key !== key);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }

  /// 复制 / 移动（重命名）：无服务端 copy，下载字节 → PUT 新 key；移动先校验目标已写入再删源，
  /// 校验不过绝不删源（对齐 iOS moveObject 防丢数据）。传输期间保持连续后台任务。
  async transfer(bucket: string, sourceKey: string, destKey: string, isMove: boolean): Promise<string> {
    if (this.isTransferring) {
      return '已有传输在进行中';
    }
    this.isTransferring = true;
    try {
      await withDataTransfer<void>(() =>
        this.service.copyObject(accountStore.selectedId, bucket, sourceKey, destKey));
      if (isMove) {
        const written = await this.service.objectExists(accountStore.selectedId, bucket, destKey);
        if (!written) {
          return '复制后未在目标确认到对象，已保留原对象未删除';
        }
        await this.service.deleteObject(accountStore.selectedId, bucket, sourceKey);
      }
      await this.load(bucket);
      return '';
    } catch (e) {
      return (e as Error).message ?? (isMove ? '移动失败' : '复制失败');
    } finally {
      this.isTransferring = false;
    }
  }

  /// 上传文本对象（新建/覆盖），落在当前文件夹前缀下
  async upload(bucket: string, key: string, text: string): Promise<string> {
    try {
      await this.service.putObjectText(accountStore.selectedId, bucket, this.currentPrefix + key, text, 'text/plain');
      await this.load(bucket);
      return '';
    } catch (e) {
      return (e as Error).message ?? '上传失败';
    }
  }

  /// 选本地文件 → 读字节 → 上传二进制对象（key = 文件名）
  async uploadFile(bucket: string): Promise<string> {
    let fd = -1;
    try {
      const documentPicker = new picker.DocumentViewPicker();
      const uris = await documentPicker.select({ maxSelectNumber: 1 });
      if (!uris || uris.length === 0) {
        return '';
      }
      const uri = uris[0];
      const slash = uri.lastIndexOf('/');
      const name = slash >= 0 ? uri.substring(slash + 1) : uri;
      const key = this.currentPrefix + name;
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      fd = file.fd;
      const stat = fileIo.statSync(fd);
      const buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(fd, buffer);
      // 传输期间保持连续后台任务，允许上传在 App 切后台后继续
      await withDataTransfer<void>(() =>
        this.service.putObjectBytes(accountStore.selectedId, bucket, key, buffer, 'application/octet-stream'));
      await this.load(bucket);
      return '';
    } catch (e) {
      return (e as Error).message ?? '上传失败';
    } finally {
      if (fd >= 0) {
        try {
          fileIo.closeSync(fd);
        } catch (e) {
        }
      }
    }
  }
}

@ComponentV2
export struct R2ObjectsPage {
  @Local vm: ObjectsVM = new ObjectsVM();
  @Local refreshing: boolean = false;
  @Local bucket: string = '';
  @Local viewerVisible: boolean = false;
  @Local uploadVisible: boolean = false;
  @Local fKey: string = '';
  @Local fContent: string = '';
  @Local detailVisible: boolean = false;
  @Local detailObj: R2Object | null = null;
  @Local transferVisible: boolean = false;
  @Local transferIsMove: boolean = false;
  @Local transferSourceKey: string = '';
  @Local fDestKey: string = '';
  private pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  /// R2 写权限门控（复制/移动是写操作）
  private guardWrite(): boolean {
    if (authManager.hasScope(Scopes.R2_WRITE)) {
      return true;
    }
    this.toast('当前授权未包含 R2 写权限（workers-r2.write），请重新授权后再试');
    return false;
  }

  /// 打开复制/移动目标 key 表单；超过 100MB 拒绝（客户端内存保护）
  private openTransfer(obj: R2Object, isMove: boolean): void {
    if (!this.guardWrite()) {
      return;
    }
    if ((obj.size ?? 0) > MAX_TRANSFER_BYTES) {
      this.toast('超过 100 MB 的对象暂不支持在 App 内复制/移动');
      return;
    }
    this.transferIsMove = isMove;
    this.transferSourceKey = obj.key;
    this.fDestKey = isMove ? obj.key : copyDefaultName(obj.key);
    this.transferVisible = true;
  }

  private runTransfer(): void {
    const dest = this.fDestKey.trim();
    const source = this.transferSourceKey;
    const isMove = this.transferIsMove;
    this.transferVisible = false;
    this.toast(isMove ? '正在移动…' : '正在复制…');
    this.vm.transfer(this.bucket, source, dest, isMove).then((err: string) => {
      this.toast(err === '' ? (isMove ? '已移动' : '已复制') : err);
    });
  }

  /// 移动会删除原对象，先确认；复制直接执行（表单确认即授权）
  private confirmTransfer(): void {
    if (!this.transferIsMove) {
      this.runTransfer();
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '移动 / 重命名',
      message: `将「${this.transferSourceKey}」移动为「${this.fDestKey.trim()}」？完成后原对象将被删除。`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '移动',
        fontColor: BRAND_ORANGE,
        action: () => {
          this.runTransfer();
        },
      },
    });
  }

  /// 点对象：可预览类型（图片/PDF/音视频/文档）走系统预览，失败/不支持回退 App 内文本查看器；
  /// 文本/JSON 直接开文本查看器。
  private openObject(obj: R2Object): void {
    if (canIUse('SystemCapability.FileManagement.FilePreview.Core') && this.vm.isMedia(obj.key)) {
      this.vm.preview(this.bucket, obj.key).catch(() => {
        // 预览失败：回退文本查看器
        this.viewerVisible = true;
        this.vm.view(this.bucket, obj.key).catch(() => {
        });
      });
      return;
    }
    this.viewerVisible = true;
    this.vm.view(this.bucket, obj.key).catch(() => {
    });
  }

  /// 保存对象到设备（DocumentViewPicker save）
  private saveObject(obj: R2Object): void {
    this.vm.saveToDevice(this.bucket, obj.key).then((err: string) => {
      if (err === 'cancel') {
        return;
      }
      this.toast(err === '' ? '已保存到设备' : err);
    });
  }

  @Builder
  uploadSheet() {
    Column({ space: 12 }) {
      Text('上传对象')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })

      Button('从文件选择上传（任意类型）')
        .width('100%')
        .height(42)
        .fontSize(14)
        .fontColor($r('app.color.oc_brand_text'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .onClick(() => {
          this.vm.uploadFile(this.bucket).then((err: string) => {
            if (err === '') {
              this.uploadVisible = false;
              this.toast('已上传');
            } else {
              this.toast(err);
            }
          });
        })

      Text('或粘贴文本内容：')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')

      TextInput({ text: this.fKey, placeholder: '对象键，如 folder/file.txt' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fKey = value;
        })
      TextArea({ text: this.fContent, placeholder: '文本内容' })
        .fontSize(13)
        .height(140)
        .width('100%')
        .onChange((value: string) => {
          this.fContent = value;
        })
      Button('上传')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(this.fKey.trim() !== '')
        .onClick(() => {
          this.vm.upload(this.bucket, this.fKey.trim(), this.fContent).then((err: string) => {
            if (err === '') {
              this.uploadVisible = false;
              this.fKey = '';
              this.fContent = '';
              this.toast('已上传');
            } else {
              this.toast(err);
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  private confirmDelete(obj: R2Object): void {
    this.getUIContext().showAlertDialog({
      title: '删除对象',
      message: `确定删除「${obj.key}」？`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.remove(this.bucket, obj.key).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  /// 长按对象：动作菜单（详情 / 预览 / 保存 / 复制 / 移动·重命名 / 删除）
  private objectActions(obj: R2Object): void {
    const media = canIUse('SystemCapability.FileManagement.FilePreview.Core') && this.vm.isMedia(obj.key);
    const sheets: SheetInfo[] = [];
    sheets.push({ title: '详情', action: () => {
      this.detailObj = obj;
      this.detailVisible = true;
    } });
    if (media) {
      sheets.push({ title: '预览', action: () => {
        this.openObject(obj);
      } });
    }
    sheets.push({ title: '保存到设备', action: () => {
      this.saveObject(obj);
    } });
    sheets.push({ title: '复制', action: () => {
      this.openTransfer(obj, false);
    } });
    sheets.push({ title: '移动 / 重命名', action: () => {
      this.openTransfer(obj, true);
    } });
    sheets.push({ title: '删除', action: () => {
      this.confirmDelete(obj);
    } });
    this.getUIContext().showActionSheet({
      title: this.vm.leafName(obj.key),
      message: '选择操作',
      sheets: sheets,
    });
  }

  @Builder
  detailSheet() {
    Column({ space: 4 }) {
      Text('对象详情')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8, bottom: 6 })
      if (this.detailObj !== null) {
        Column() {
          InfoRow({ label: 'Key', value: this.detailObj?.key ?? '' })
          InfoRow({ label: '大小', value: formatBytes(this.detailObj?.size ?? 0) })
          if ((this.detailObj?.http_metadata?.contentType ?? '') !== '') {
            InfoRow({ label: 'Content-Type', value: this.detailObj?.http_metadata?.contentType ?? '' })
          }
          if ((this.detailObj?.etag ?? '') !== '') {
            InfoRow({ label: 'ETag', value: this.detailObj?.etag ?? '' })
          }
          if ((this.detailObj?.uploaded ?? this.detailObj?.last_modified ?? '') !== '') {
            InfoRow({
              label: '上传时间',
              value: formatTimeAgo(this.detailObj?.uploaded ?? this.detailObj?.last_modified ?? ''),
            })
          }
          if ((this.detailObj?.storage_class ?? '') !== '') {
            InfoRow({ label: '存储类型', value: this.detailObj?.storage_class ?? '' })
          }
        }
        .backgroundColor($r('sys.color.comp_background_list_card'))
        .borderRadius(14)
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })
        .clip(true)
      }
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  @Builder
  transferSheet() {
    Column({ space: 12 }) {
      Text(this.transferIsMove ? '移动 / 重命名' : '复制对象')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      Text(`源对象：${this.transferSourceKey}`)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      TextInput({ text: this.fDestKey, placeholder: '目标 Key（可含 / 表示文件夹层级）' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fDestKey = value;
        })
      Text('无服务端复制：内容会先下载到设备再上传到目标 Key，超过 100 MB 的对象不支持。')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      Button(this.vm.isTransferring ? '正在传输…' : (this.transferIsMove ? '移动' : '复制'))
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isTransferring && this.fDestKey.trim() !== '' &&
          this.fDestKey.trim() !== this.transferSourceKey)
        .onClick(() => {
          this.confirmTransfer();
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  @Builder
  viewerSheet() {
    Column({ space: 10 }) {
      Text(this.vm.viewerKey)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })
      Row({ space: 10 }) {
        if (canIUse('SystemCapability.FileManagement.FilePreview.Core') && this.vm.isMedia(this.vm.viewerKey)) {
          Button('预览')
            .layoutWeight(1)
            .height(38)
            .fontSize(14)
            .fontColor($r('app.color.oc_brand_text'))
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .onClick(() => {
              this.vm.preview(this.bucket, this.vm.viewerKey).catch((e: Error) => {
                this.toast(e.message ?? '预览失败');
              });
            })
        }
        Button('保存到设备')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .fontColor($r('app.color.oc_brand_text'))
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .onClick(() => {
            this.vm.saveToDevice(this.bucket, this.vm.viewerKey).then((err: string) => {
              if (err !== 'cancel') {
                this.toast(err === '' ? '已保存到设备' : err);
              }
            });
          })
      }
      .width('100%')
      Scroll() {
        Text(this.vm.viewerText)
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
      }
      .align(Alignment.Top)
      .layoutWeight(1)
    }
    .padding({ left: 16, right: 16, bottom: 20 })
    .width('100%')
    .height('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading && this.vm.objects.length === 0 && this.vm.folders.length === 0) {
          Column() {
            OCLoading({ text: '正在加载对象…' })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load(this.bucket).catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.objects.length === 0 && this.vm.folders.length === 0 && this.vm.currentPrefix === '') {
          Column() {
            OCEmpty({ symbol: $r('sys.symbol.archivebox'), title: '空存储桶', subtitle: '点右下角 + 上传文本对象' })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            List() {
              // 非根层：置顶「上级」行
              if (this.vm.currentPrefix !== '') {
                ListItem() {
                  ResourceCard({
                    symbol: $r('sys.symbol.folder'),
                    title: '⬆ 上级',
                    subtitle: this.vm.currentPrefix,
                    onTap: () => {
                      this.vm.goUp(this.bucket).catch(() => {
                      });
                    },
                  })
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
              }
              // 文件夹行（子前缀）在对象之上
              ForEach(this.vm.folders, (folder: string) => {
                ListItem() {
                  ResourceCard({
                    symbol: $r('sys.symbol.folder'),
                    title: this.vm.folderName(folder),
                    subtitle: '文件夹',
                    onTap: () => {
                      this.vm.openFolder(this.bucket, folder).catch(() => {
                      });
                    },
                  })
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
              }, (folder: string) => `dir:${folder}`)
              ForEach(this.vm.objects, (obj: R2Object) => {
                ListItem() {
                  ResourceCard({
                    symbol: $r('sys.symbol.doc_text'),
                    title: this.vm.leafName(obj.key),
                    subtitle: `${formatBytes(obj.size ?? 0)} · ${formatTimeAgo(obj.uploaded ?? '')}`,
                    onTap: () => {
                      this.openObject(obj);
                    },
                    onLongPress: () => {
                      this.objectActions(obj);
                    },
                  })
                }
                .margin({ left: 16, right: 16, top: 5, bottom: 5 })
              }, (obj: R2Object) => `obj:${obj.key}`)
              if (this.vm.cursor !== '') {
                ListItem() {
                  Text(this.vm.isLoadingMore ? '正在加载…' : '加载更多')
                    .fontSize(13)
                    .fontColor($r('app.color.oc_brand_text'))
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .padding(16)
                    .onClick(() => {
                      this.vm.loadMore(this.bucket).catch(() => {
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
            this.vm.load(this.bucket).then(() => {
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
            this.uploadVisible = true;
          })
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({ content: { title: { mainTitle: this.bucket }, menu: { value: [{ content: { icon: $r('sys.symbol.gearshape'), label: '桶设置', action: () => { const param: IdNameParam = { id: this.bucket, name: this.bucket }; this.pathStack?.pushPathByName(Routes.R2_SETTINGS, param); } } }] } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.viewerVisible, this.viewerSheet(), ocSheet(() => {
      this.viewerVisible = false;
    }))
    .bindSheet(this.uploadVisible, this.uploadSheet(), ocSheet(() => {
      this.uploadVisible = false;
    }))
    .bindSheet(this.detailVisible, this.detailSheet(), ocSheet(() => {
      this.detailVisible = false;
    }))
    .bindSheet(this.transferVisible, this.transferSheet(), ocSheet(() => {
      this.transferVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as NameParam;
      this.bucket = param.name;
      this.vm.load(param.name).catch(() => {
      });
    })
  }
}
