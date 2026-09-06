// Pages 直接上传部署（对照 iOS PagesDeployViewModel + PagesDeployView）。
//
// 四步链路，缺一不可：
//   ① upload-token 换短期 JWT（后面三个资源端点都用它，不是账号 token）
//   ② 本地算每个文件的资源键 = blake3(base64(内容) + 扩展名) 前 32 位 hex，组 manifest
//   ③ check-missing 问服务端缺哪些 → 只传缺的 → upsert-hashes 关联全部（含没传的旧资源）
//   ④ 带 manifest 建部署
// 漏掉 upsert-hashes，本次没重传的旧资源可能被回收，站点会缺文件。
import { util } from '@kit.ArkTS';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { PagesAssetUpload, PagesDeployFile } from '../../models/WorkerModels';
import { PagesService } from '../../services/PagesService';
import { blake3HexPrefix } from '../../core/crypto/Blake3';
import { accountStore } from '../../core/store/AccountStore';
import { BRAND_ORANGE, DANGER_RED } from '../common/Components';
import { OCLayout } from '../common/Daybreak';

/// Pages 单文件上限 25 MiB
const MAX_FILE_BYTES = 25 * 1024 * 1024;
/// 单批上传的累计原始字节（base64 后约 ×1.37），以及条数上限
const BATCH_BYTES = 8 * 1024 * 1024;
const BATCH_COUNT = 50;

/// 常见扩展名 → Content-Type（服务端也会兜底，这里给准一点便于浏览器直接渲染）
function contentTypeOf(path: string): string {
  const dot = path.lastIndexOf('.');
  const ext = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
  switch (ext) {
    case 'html':
    case 'htm':
      return 'text/html';
    case 'css':
      return 'text/css';
    case 'js':
    case 'mjs':
      return 'application/javascript';
    case 'json':
      return 'application/json';
    case 'svg':
      return 'image/svg+xml';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'ico':
      return 'image/x-icon';
    case 'txt':
      return 'text/plain';
    case 'xml':
      return 'application/xml';
    case 'wasm':
      return 'application/wasm';
    default:
      return 'application/octet-stream';
  }
}

/// 扩展名（不含点，用于拼资源键）
function extensionOf(path: string): string {
  const dot = path.lastIndexOf('.');
  if (dot < 0) {
    return '';
  }
  return path.substring(dot + 1);
}

/// 部署阶段（决定进度文案）
export type DeployPhase = 'idle' | 'hashing' | 'uploading' | 'creating' | 'done' | 'failed';

@ObservedV2
export class PagesDeployVM {
  @Trace phase: DeployPhase = 'idle';
  @Trace uploadedCount: number = 0;
  @Trace totalToUpload: number = 0;
  @Trace error: string = '';
  /// 已选择的待部署文件（粘贴模式下只有一个）
  @Trace files: PagesDeployFile[] = [];

  private service: PagesService = new PagesService();

  isDeploying(): boolean {
    return this.phase === 'hashing' || this.phase === 'uploading' || this.phase === 'creating';
  }

  reset(): void {
    this.phase = 'idle';
    this.uploadedCount = 0;
    this.totalToUpload = 0;
    this.error = '';
  }

  clearFiles(): void {
    this.files = [];
    this.reset();
  }

  /// 选本地文件（可多选）读进内存备用
  async pickFiles(): Promise<string> {
    try {
      const documentPicker = new picker.DocumentViewPicker();
      const uris = await documentPicker.select({ maxSelectNumber: 20 });
      if (!uris || uris.length === 0) {
        return '';
      }
      const picked: PagesDeployFile[] = [];
      for (const uri of uris) {
        let fd = -1;
        try {
          const slash = uri.lastIndexOf('/');
          const name = slash >= 0 ? uri.substring(slash + 1) : uri;
          const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
          fd = file.fd;
          const stat = fileIo.statSync(fd);
          const buffer = new ArrayBuffer(stat.size);
          fileIo.readSync(fd, buffer);
          picked.push({ path: `/${name}`, data: buffer, contentType: contentTypeOf(name) });
        } finally {
          if (fd >= 0) {
            try {
              fileIo.closeSync(fd);
            } catch (e) {
            }
          }
        }
      }
      this.files = picked;
      this.reset();
      return '';
    } catch (e) {
      return (e as Error).message ?? '选择文件失败';
    }
  }

  /// 粘贴模式：把一段文本按给定文件名当成单文件
  setPastedFile(filename: string, code: string): void {
    const encoder = new util.TextEncoder();
    const bytes = encoder.encodeInto(code);
    const buffer = new ArrayBuffer(bytes.length);
    new Uint8Array(buffer).set(bytes);
    this.files = [{ path: `/${filename}`, data: buffer, contentType: contentTypeOf(filename) }];
    this.reset();
  }

  /// 执行整套直接上传部署；成功返回 true
  async deploy(projectName: string): Promise<boolean> {
    if (this.files.length === 0 || this.isDeploying()) {
      return false;
    }
    this.error = '';
    this.uploadedCount = 0;
    this.totalToUpload = 0;
    this.phase = 'hashing';

    for (const file of this.files) {
      if (file.data.byteLength > MAX_FILE_BYTES) {
        this.error = `文件 ${file.path} 超过 25 MB，超出 Pages 单文件上限`;
        this.phase = 'failed';
        return false;
      }
    }

    // 算哈希建 manifest；base64 缓存下来给上传腿复用，避免二次编码
    const manifest: Record<string, string> = {};
    const fileByHash = new Map<string, PagesDeployFile>();
    const b64ByHash = new Map<string, string>();
    const helper = new util.Base64Helper();
    const encoder = new util.TextEncoder();
    for (const file of this.files) {
      const b64 = helper.encodeToStringSync(new Uint8Array(file.data), util.Type.BASIC);
      const keySource = encoder.encodeInto(b64 + extensionOf(file.path));
      const hash = blake3HexPrefix(keySource, 32);
      manifest[file.path] = hash;
      fileByHash.set(hash, file);
      b64ByHash.set(hash, b64);
    }

    try {
      const accountId = accountStore.selectedId;
      const jwt = await this.service.uploadToken(accountId, projectName);
      const allHashes = Array.from(new Set<string>(Object.values(manifest)));
      const missing = await this.service.checkMissingAssets(jwt, allHashes);

      const pending: string[] = missing.filter((h: string) => fileByHash.has(h) && b64ByHash.has(h));
      this.totalToUpload = pending.length;
      this.phase = 'uploading';

      let batch: PagesAssetUpload[] = [];
      let batchBytes = 0;
      for (const hash of pending) {
        const file = fileByHash.get(hash)!;
        const b64 = b64ByHash.get(hash)!;
        batch.push({
          key: hash,
          value: b64,
          metadata: { contentType: file.contentType },
          base64: true,
        });
        batchBytes += file.data.byteLength;
        if (batch.length >= BATCH_COUNT || batchBytes >= BATCH_BYTES) {
          await this.service.uploadAssets(jwt, batch);
          this.uploadedCount += batch.length;
          batch = [];
          batchBytes = 0;
        }
      }
      if (batch.length > 0) {
        await this.service.uploadAssets(jwt, batch);
        this.uploadedCount += batch.length;
      }

      await this.service.upsertHashes(jwt, allHashes);
      this.phase = 'creating';
      await this.service.createDeployment(accountId, projectName, manifest);
      this.phase = 'done';
      return true;
    } catch (e) {
      this.error = (e as Error).message ?? '部署失败';
      this.phase = 'failed';
      return false;
    }
  }
}

/// 阶段 → 进度文案
export function deployPhaseText(vm: PagesDeployVM): string {
  switch (vm.phase) {
    case 'hashing':
      return '正在计算资源哈希…';
    case 'uploading':
      return vm.totalToUpload === 0
        ? '资源均已存在，跳过上传'
        : `正在上传 ${vm.uploadedCount}/${vm.totalToUpload}…`;
    case 'creating':
      return '正在创建部署…';
    case 'done':
      return '部署已创建，构建结果稍后可在部署列表查看';
    default:
      return '';
  }
}

/// 部署表单（粘贴代码 / 选文件两种来源），由项目详情页以半模态承载
@ComponentV2
export struct PagesDeploySheet {
  @Require @Param vm: PagesDeployVM;
  @Require @Param projectName: string;
  @Param onDeployed: () => void = () => {
  };
  /// 'paste' | 'files'
  @Local source: string = 'paste';
  @Local filename: string = 'index.html';
  @Local code: string = '';

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  /// 提交前把当前来源的内容固化成待部署文件
  private prepare(): boolean {
    if (this.source === 'paste') {
      const name = this.filename.trim();
      if (name === '' || this.code === '') {
        return false;
      }
      this.vm.setPastedFile(name, this.code);
      return true;
    }
    return this.vm.files.length > 0;
  }

  build() {
    Column({ space: 12 }) {
      Text('部署')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })

      Row({ space: 8 }) {
        Text('粘贴代码')
          .fontSize(13)
          .fontWeight(this.source === 'paste' ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.source === 'paste' ? Color.White : $r('sys.color.font_secondary'))
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor(this.source === 'paste' ? BRAND_ORANGE : $r('sys.color.comp_background_list_card'))
          .borderRadius(16)
          .onClick(() => {
            this.source = 'paste';
            this.vm.clearFiles();
          })
        Text('选择文件')
          .fontSize(13)
          .fontWeight(this.source === 'files' ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.source === 'files' ? Color.White : $r('sys.color.font_secondary'))
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor(this.source === 'files' ? BRAND_ORANGE : $r('sys.color.comp_background_list_card'))
          .borderRadius(16)
          .onClick(() => {
            this.source = 'files';
            this.vm.clearFiles();
          })
        Blank()
      }
      .width('100%')

      if (this.source === 'paste') {
        Text('文件名（站点内路径，单文件部署通常用 index.html）')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
        TextInput({ text: this.filename, placeholder: 'index.html' })
          .fontSize(14)
          .width('100%')
          .enabled(!this.vm.isDeploying())
          .onChange((value: string) => {
            this.filename = value;
          })
        TextArea({ text: this.code, placeholder: '粘贴 HTML / JS / CSS 内容' })
          .fontSize(12)
          .fontFamily('monospace')
          .height(220)
          .width('100%')
          .enabled(!this.vm.isDeploying())
          .onChange((value: string) => {
            this.code = value;
          })
      } else {
        Button(this.vm.files.length === 0 ? '选择文件' : `已选 ${this.vm.files.length} 个文件，重新选择`)
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .backgroundColor($r('sys.color.comp_background_list_card'))
          .borderRadius(OCLayout.chipRadius)
          .border({ width: 0.5, color: $r('sys.color.comp_divider') })
          .enabled(!this.vm.isDeploying())
          .onClick(() => {
            this.vm.pickFiles().then((err: string) => {
              this.toast(err);
            });
          })
        if (this.vm.files.length > 0) {
          Column() {
            ForEach(this.vm.files, (file: PagesDeployFile) => {
              Row({ space: 8 }) {
                Text(file.path)
                  .fontSize(12)
                  .fontFamily('monospace')
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(`${Math.max(1, Math.round(file.data.byteLength / 1024))} KB`)
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            }, (file: PagesDeployFile) => file.path)
          }
          .width('100%')
          .backgroundColor($r('sys.color.comp_background_list_card'))
          .borderRadius(OCLayout.chipRadius)
          .border({ width: 0.5, color: $r('sys.color.comp_divider') })
          .clip(true)
        }
        Text('选中的文件会放在站点根目录下；子目录结构请用打包好的产物逐个选取。')
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }

      if (deployPhaseText(this.vm) !== '') {
        Row({ space: 8 }) {
          if (this.vm.isDeploying()) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(BRAND_ORANGE)
          }
          Text(deployPhaseText(this.vm))
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .layoutWeight(1)
        }
        .width('100%')
      }
      if (this.vm.error !== '') {
        Text(this.vm.error)
          .fontSize(12)
          .fontColor(DANGER_RED)
          .width('100%')
      }

      Button(this.vm.isDeploying() ? '正在部署…' : '部署')
        .width('100%')
        .height(46)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(BRAND_ORANGE)
        .enabled(!this.vm.isDeploying() &&
          (this.source === 'files' ? this.vm.files.length > 0 : (this.filename.trim() !== '' && this.code !== '')))
        .onClick(() => {
          if (!this.prepare()) {
            return;
          }
          this.vm.deploy(this.projectName).then((ok: boolean) => {
            if (ok) {
              this.toast('部署已创建');
              this.onDeployed();
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }
}
