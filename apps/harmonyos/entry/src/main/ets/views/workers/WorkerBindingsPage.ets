// Worker 变量与密钥（对照 iOS WorkerSecretsView / WorkerBindingsViewModel）：
// 密钥（secret_text，专用端点）+ 环境变量（plain_text，PATCH settings）+ 只读绑定清单
// + D1/KV/R2 快速绑定。
//
// 铁律：改任一绑定都要**整组回写**——变更项为实体、其余一律 inherit，
// 否则没写进去的绑定会被服务端当作删除（密钥值读不到，丢了就找不回来）。
import { R2Bucket, D1Database, KVNamespace } from '../../models/StorageModels';
import { NameParam } from '../../models/Routes';
import {
  WorkerBindingInfo,
  WorkerBindingInput,
  WorkerSecret,
  WorkerSettingsInfo,
  bindingIsPlainText,
  bindingIsQuickManaged,
  bindingIsSecret,
  bindingTypeLabel,
  inheritedBindings,
} from '../../models/WorkerModels';
import { WorkerService } from '../../services/WorkerService';
import { StorageService } from '../../services/StorageService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { BRAND_ORANGE, BRAND_ORANGE_BG, DANGER_RED, OCLoading } from '../common/Components';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';
import { GlassIsland, OCLayout, RevealBox } from '../common/Daybreak';

/// 批量导入结果（成功计数用于 toast）
interface ImportOutcome {
  success: boolean;
  message: string;
}

/// 快速绑定可选的资源类型
type BindKind = 'd1' | 'kv_namespace' | 'r2_bucket';

interface BindKindOption {
  kind: BindKind;
  label: string;
}

const BIND_KINDS: BindKindOption[] = [
  { kind: 'd1', label: 'D1' },
  { kind: 'kv_namespace', label: 'KV' },
  { kind: 'r2_bucket', label: 'R2' },
];

/// 绑定选择器里的一个候选项（三类资源归一化后统一渲染）
interface BindCandidate {
  /// 展示名
  title: string;
  /// 绑定引用值：D1=uuid，KV=namespace id，R2=桶名
  value: string;
}

@ObservedV2
class WorkerBindingsVM {
  @Trace secrets: WorkerSecret[] = [];
  @Trace settings: WorkerSettingsInfo | null = null;
  @Trace isLoading: boolean = false;
  @Trace isSaving: boolean = false;
  @Trace loaded: boolean = false;
  @Trace error: string = '';
  // 快速绑定的候选资源（打开选择器时惰性加载）
  @Trace d1Databases: D1Database[] = [];
  @Trace kvNamespaces: KVNamespace[] = [];
  @Trace r2Buckets: R2Bucket[] = [];
  @Trace resourcesLoading: boolean = false;
  @Trace resourcesLoaded: boolean = false;

  private service: WorkerService = new WorkerService();
  private storage: StorageService = new StorageService();

  /// 环境变量（plain_text），按名排序
  get variables(): WorkerBindingInfo[] {
    const out = (this.settings?.bindings ?? []).filter(bindingIsPlainText);
    return out.sort((a: WorkerBindingInfo, b: WorkerBindingInfo) => (a.name ?? '').localeCompare(b.name ?? ''));
  }

  /// 其它绑定（非变量非密钥）：KV / D1 / R2 / DO / 队列等
  get otherBindings(): WorkerBindingInfo[] {
    const out = (this.settings?.bindings ?? [])
      .filter((b: WorkerBindingInfo) => !bindingIsPlainText(b) && !bindingIsSecret(b));
    return out.sort((a: WorkerBindingInfo, b: WorkerBindingInfo) => (a.name ?? '').localeCompare(b.name ?? ''));
  }

  /// 已占用的绑定名（新增时查重）
  hasName(name: string): boolean {
    return (this.settings?.bindings ?? []).some((b: WorkerBindingInfo) => (b.name ?? '') === name);
  }

  async load(accountId: string, scriptName: string): Promise<void> {
    this.isLoading = true;
    this.error = '';
    try {
      try {
        this.secrets = await this.service.listSecrets(accountId, scriptName);
      } catch (e) {
        // 密钥列表失败不该挡住变量与绑定
      }
      this.settings = await this.service.scriptSettings(accountId, scriptName);
      this.loaded = true;
    } catch (e) {
      this.error = (e as Error).message ?? '加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  // MARK: - 密钥

  async putSecret(accountId: string, scriptName: string, name: string, text: string): Promise<string> {
    if (this.isSaving) {
      return '正在保存，请稍候';
    }
    this.isSaving = true;
    try {
      await this.service.putSecret(accountId, scriptName, name, text);
      this.secrets = await this.service.listSecrets(accountId, scriptName);
      return '';
    } catch (e) {
      return (e as Error).message ?? '保存失败';
    } finally {
      this.isSaving = false;
    }
  }

  async deleteSecret(accountId: string, scriptName: string, name: string): Promise<string> {
    try {
      await this.service.deleteSecret(accountId, scriptName, name);
      this.secrets = this.secrets.filter((s: WorkerSecret) => s.name !== name);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }

  // MARK: - 环境变量与绑定（整组回写）

  /// 写入 / 覆盖一个 plain_text 变量
  async setVariable(accountId: string, scriptName: string, name: string, value: string): Promise<string> {
    const input: WorkerBindingInput = { type: 'plain_text', name: name, text: value };
    return await this.writeBindings(accountId, scriptName, name, input);
  }

  /// 绑定一个 D1 / KV / R2 资源
  async bindResource(accountId: string, scriptName: string, kind: BindKind,
    name: string, value: string): Promise<string> {
    let input: WorkerBindingInput;
    if (kind === 'd1') {
      input = { type: 'd1', name: name, id: value };
    } else if (kind === 'kv_namespace') {
      input = { type: 'kv_namespace', name: name, namespace_id: value };
    } else {
      input = { type: 'r2_bucket', name: name, bucket_name: value };
    }
    return await this.writeBindings(accountId, scriptName, name, input);
  }

  /// 移除一条绑定（变量 / D1 / KV / R2 共用）：其余 inherit 回写即为删除
  async removeBinding(accountId: string, scriptName: string, name: string): Promise<string> {
    return await this.writeBindings(accountId, scriptName, name, null);
  }

  /// 整组回写：excluded 之外全部 inherit；entry 非空则追加为实体
  private async writeBindings(accountId: string, scriptName: string, excluded: string,
    entry: WorkerBindingInput | null): Promise<string> {
    const current = this.settings;
    if (current === null) {
      return '脚本设置未就绪';
    }
    if (this.isSaving) {
      return '正在保存，请稍候';
    }
    this.isSaving = true;
    try {
      const bindings = inheritedBindings(current, excluded);
      if (entry !== null) {
        bindings.push(entry);
      }
      await this.service.patchSettings(accountId, scriptName, bindings, current);
      this.settings = await this.service.scriptSettings(accountId, scriptName);
      return '';
    } catch (e) {
      return (e as Error).message ?? '保存失败';
    } finally {
      this.isSaving = false;
    }
  }

  // MARK: - 批量导入

  /// 变量批量导入：**单次 PATCH** 原子写入（导入项为实体、其余 inherit，同名覆盖）
  async importVariables(accountId: string, scriptName: string, jsonText: string): Promise<ImportOutcome> {
    const parsed = parsePairs(jsonText);
    if (parsed.error !== '') {
      return { success: false, message: parsed.error };
    }
    const current = this.settings;
    if (current === null) {
      return { success: false, message: '脚本设置未就绪' };
    }
    this.isSaving = true;
    try {
      const importedNames = parsed.names;
      const bindings: WorkerBindingInput[] = [];
      for (const binding of current.bindings ?? []) {
        const name = binding.name ?? '';
        if (name === '' || importedNames.includes(name)) {
          continue;
        }
        bindings.push({ type: 'inherit', name: name });
      }
      for (let i = 0; i < parsed.names.length; i++) {
        bindings.push({ type: 'plain_text', name: parsed.names[i], text: parsed.values[i] });
      }
      await this.service.patchSettings(accountId, scriptName, bindings, current);
      this.settings = await this.service.scriptSettings(accountId, scriptName);
      return { success: true, message: `已导入 ${parsed.names.length} 个变量` };
    } catch (e) {
      return { success: false, message: (e as Error).message ?? '导入失败' };
    } finally {
      this.isSaving = false;
    }
  }

  /// 密钥批量导入：走 secrets-bulk 单次 PATCH **原子生效**（同名覆盖，未提及的密钥不受影响）。
  /// 端点单次上限 100 项，超出自动分批（每批各自原子）；某批失败即停并报告已写入数量。
  async importSecrets(accountId: string, scriptName: string, jsonText: string): Promise<ImportOutcome> {
    const parsed = parsePairs(jsonText);
    if (parsed.error !== '') {
      return { success: false, message: parsed.error };
    }
    this.isSaving = true;
    let done = 0;
    try {
      const total = parsed.names.length;
      for (let start = 0; start < total; start += 100) {
        const end = Math.min(start + 100, total);
        await this.service.bulkPatchSecrets(accountId, scriptName,
          parsed.names.slice(start, end), parsed.values.slice(start, end));
        done = end;
      }
      return { success: true, message: `已导入 ${done} 个密钥` };
    } catch (e) {
      return { success: false, message: `已导入 ${done}/${parsed.names.length} 项后失败：${(e as Error).message}` };
    } finally {
      try {
        this.secrets = await this.service.listSecrets(accountId, scriptName);
      } catch (e) {
        // 列表刷新失败不影响导入结果判定
      }
      this.isSaving = false;
    }
  }

  /// 打开绑定选择器时按需加载候选资源（缺对应读权限就静默跳过那一类）
  async loadResources(accountId: string): Promise<void> {
    if (this.resourcesLoading || this.resourcesLoaded) {
      return;
    }
    this.resourcesLoading = true;
    try {
      if (authManager.hasScope(Scopes.D1_READ)) {
        try {
          this.d1Databases = await this.storage.listDatabases(accountId);
        } catch (e) {
        }
      }
      if (authManager.hasScope(Scopes.KV_READ)) {
        try {
          this.kvNamespaces = await this.storage.listNamespaces(accountId);
        } catch (e) {
        }
      }
      if (authManager.hasScope(Scopes.R2_READ)) {
        try {
          this.r2Buckets = await this.storage.listBuckets(accountId);
        } catch (e) {
        }
      }
      this.resourcesLoaded = true;
    } finally {
      this.resourcesLoading = false;
    }
  }
}

/// JSON 对象 → 键值两列（批量导入共用）
interface ParsedPairs {
  names: string[];
  values: string[];
  error: string;
}

function parsePairs(jsonText: string): ParsedPairs {
  let record: Record<string, Object>;
  try {
    record = JSON.parse(jsonText) as Record<string, Object>;
  } catch (e) {
    return { names: [], values: [], error: 'JSON 解析失败，请检查格式' };
  }
  if (record === null || typeof record !== 'object' || record instanceof Array) {
    return { names: [], values: [], error: '需为 JSON 对象，如 {"KEY":"value"}' };
  }
  const names: string[] = [];
  const values: string[] = [];
  for (const key of Object.keys(record)) {
    const raw = record[key];
    names.push(key);
    values.push(typeof raw === 'string' ? raw as string : JSON.stringify(raw));
  }
  if (names.length === 0) {
    return { names: [], values: [], error: '没有可导入的键' };
  }
  return { names: names, values: values, error: '' };
}

@ComponentV2
export struct WorkerBindingsPage {
  @Local vm: WorkerBindingsVM = new WorkerBindingsVM();
  @Local scriptName: string = '';
  @Local secretSheetVisible: boolean = false;
  @Local variableSheetVisible: boolean = false;
  @Local importSheetVisible: boolean = false;
  @Local bindSheetVisible: boolean = false;
  @Local refreshing: boolean = false;
  // 表单字段
  @Local fName: string = '';
  @Local fValue: string = '';
  /// 编辑已有变量时锁定名字（改名等于删旧建新，容易误伤）
  @Local fNameLocked: boolean = false;
  @Local fImportJson: string = '';
  /// 批量导入目标：'secret' | 'variable'
  @Local importTarget: string = 'secret';
  @Local bindKind: BindKind = 'd1';
  @Local bindValue: string = '';
  private pathStack: NavPathStack | null = null;

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  /// 写操作 scope 门控：缺 workers-scripts.write 时拦截并提示
  private canWrite(): boolean {
    if (!authManager.hasScope(Scopes.WORKERS_WRITE)) {
      this.toast('当前授权未包含 Workers 写权限（workers-scripts.write）');
      return false;
    }
    return true;
  }

  /// 至少能读到一类资源才提供快速绑定入口
  private canBind(): boolean {
    return authManager.hasScope(Scopes.WORKERS_WRITE) &&
      (authManager.hasScope(Scopes.D1_READ) || authManager.hasScope(Scopes.KV_READ) ||
        authManager.hasScope(Scopes.R2_READ));
  }

  private reload(): void {
    this.vm.load(accountStore.selectedId, this.scriptName).catch(() => {
    });
  }

  private openSecretSheet(): void {
    if (!this.canWrite()) {
      return;
    }
    this.fName = '';
    this.fValue = '';
    this.secretSheetVisible = true;
  }

  private openVariableSheet(binding: WorkerBindingInfo | null): void {
    if (!this.canWrite()) {
      return;
    }
    this.fName = binding?.name ?? '';
    this.fValue = binding?.text ?? '';
    this.fNameLocked = binding !== null;
    this.variableSheetVisible = true;
  }

  private openImportSheet(target: string): void {
    if (!this.canWrite()) {
      return;
    }
    this.importTarget = target;
    this.fImportJson = '';
    this.importSheetVisible = true;
  }

  private openBindSheet(): void {
    if (!this.canWrite()) {
      return;
    }
    this.fName = '';
    this.bindValue = '';
    this.bindKind = 'd1';
    this.bindSheetVisible = true;
    this.vm.loadResources(accountStore.selectedId).catch(() => {
    });
  }

  /// 当前类型下的候选资源（三类归一化后统一渲染）
  private candidates(): BindCandidate[] {
    const out: BindCandidate[] = [];
    if (this.bindKind === 'd1') {
      for (const db of this.vm.d1Databases) {
        out.push({ title: db.name, value: db.uuid });
      }
    } else if (this.bindKind === 'kv_namespace') {
      for (const ns of this.vm.kvNamespaces) {
        out.push({ title: ns.title, value: ns.id });
      }
    } else {
      for (const bucket of this.vm.r2Buckets) {
        out.push({ title: bucket.name, value: bucket.name });
      }
    }
    return out;
  }

  private confirmRemove(title: string, message: string, onConfirm: () => void): void {
    this.getUIContext().showAlertDialog({
      title: title,
      message: message,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '删除',
        fontColor: DANGER_RED,
        action: onConfirm,
      },
    });
  }

  @Builder
  sectionHeader(title: string, actionA: string, onA: () => void, actionB: string, onB: () => void) {
    Row() {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .layoutWeight(1)
        .padding({ left: 4 })
      if (actionA !== '') {
        Text(actionA)
          .fontSize(13)
          .fontColor($r('app.color.oc_brand_text'))
          .padding({ left: 8 })
          .onClick(onA)
      }
      if (actionB !== '') {
        Text(actionB)
          .fontSize(13)
          .fontColor($r('app.color.oc_brand_text'))
          .padding({ left: 12, right: 4 })
          .onClick(onB)
      }
    }
    .width('100%')
  }


  @Builder
  emptyRow(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')
      .padding(14)
  }

  /// 通用条目行：徽章 + 名字 + 副文本，长按触发操作
  @Builder
  entryRow(badge: string, name: string, detail: string, onLongPress: () => void, onTap: () => void) {
    Row({ space: 12 }) {
      Text(badge)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.oc_brand_text'))
        .padding({ left: 7, right: 7, top: 3, bottom: 3 })
        .backgroundColor($r('app.color.oc_brand_bg'))
        .borderRadius(8)
      Column({ space: 3 }) {
        Text(name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (detail !== '') {
          Text(detail)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .onClick(onTap)
    .gesture(LongPressGesture().onAction(onLongPress))
  }

  @Builder
  divider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.comp_divider'))
      .margin({ left: 14 })
  }

  // MARK: - Sheets

  @Builder
  secretSheet() {
    Column({ space: 14 }) {
      Text('添加密钥')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Text('密钥值写入后不可读取，只能覆盖或删除。同名将直接覆盖。')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ placeholder: '变量名，如 API_TOKEN', text: this.fName })
        .onChange((value: string) => {
          this.fName = value;
        })
      TextInput({ placeholder: '密钥值', text: this.fValue })
        .type(InputType.Password)
        .onChange((value: string) => {
          this.fValue = value;
        })
      Button(this.vm.isSaving ? '正在保存…' : '保存')
        .width('100%')
        .height(46)
        .backgroundColor($r('app.color.oc_brand'))
        .enabled(!this.vm.isSaving && this.fName.trim() !== '' && this.fValue !== '')
        .onClick(() => {
          this.vm.putSecret(accountStore.selectedId, this.scriptName, this.fName.trim(), this.fValue)
            .then((err: string) => {
              if (err === '') {
                this.secretSheetVisible = false;
                this.toast('密钥已保存');
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
  variableSheet() {
    Column({ space: 14 }) {
      Text(this.fNameLocked ? '编辑变量' : '添加变量')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Text('环境变量以明文保存，可随时读取修改。敏感值请用密钥。')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ placeholder: '变量名，如 API_BASE', text: this.fName })
        .enabled(!this.fNameLocked)
        .onChange((value: string) => {
          this.fName = value;
        })
      TextArea({ placeholder: '变量值', text: this.fValue })
        .height(110)
        .onChange((value: string) => {
          this.fValue = value;
        })
      Button(this.vm.isSaving ? '正在保存…' : '保存')
        .width('100%')
        .height(46)
        .backgroundColor($r('app.color.oc_brand'))
        .enabled(!this.vm.isSaving && this.fName.trim() !== '')
        .onClick(() => {
          const name = this.fName.trim();
          if (!this.fNameLocked && this.vm.hasName(name)) {
            this.toast('已有同名绑定，请换一个变量名');
            return;
          }
          this.vm.setVariable(accountStore.selectedId, this.scriptName, name, this.fValue)
            .then((err: string) => {
              if (err === '') {
                this.variableSheetVisible = false;
                this.toast('变量已保存');
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
  importSheet() {
    Column({ space: 14 }) {
      Text(this.importTarget === 'secret' ? '批量导入密钥' : '批量导入变量')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Text(this.importTarget === 'secret'
        ? '粘贴 JSON 对象：键为密钥名、值为密钥值。走批量接口单次原子生效（每 100 项一批），同名覆盖。'
        : '粘贴 JSON 对象：键为变量名、值为变量值。单次整组回写，要么全成要么不动。')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextArea({ placeholder: '{"API_TOKEN":"xxx","REGION":"apac"}', text: this.fImportJson })
        .height(180)
        .onChange((value: string) => {
          this.fImportJson = value;
        })
      Button(this.vm.isSaving ? '正在导入…' : '导入')
        .width('100%')
        .height(46)
        .backgroundColor($r('app.color.oc_brand'))
        .enabled(!this.vm.isSaving && this.fImportJson.trim() !== '')
        .onClick(() => {
          const json = this.fImportJson.trim();
          const task = this.importTarget === 'secret'
            ? this.vm.importSecrets(accountStore.selectedId, this.scriptName, json)
            : this.vm.importVariables(accountStore.selectedId, this.scriptName, json);
          task.then((outcome: ImportOutcome) => {
            this.toast(outcome.message);
            if (outcome.success) {
              this.importSheetVisible = false;
              this.fImportJson = '';
            }
          });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  @Builder
  resourceSheet() {
    Column({ space: 14 }) {
      Text('绑定资源')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Text('把 D1 数据库 / KV 命名空间 / R2 存储桶挂到脚本上，代码里按绑定名访问。')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')

      Row({ space: 8 }) {
        ForEach(BIND_KINDS, (option: BindKindOption) => {
          Text(option.label)
            .fontSize(13)
            .fontWeight(this.bindKind === option.kind ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.bindKind === option.kind ? $r('app.color.oc_brand_text') : $r('sys.color.font_secondary'))
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .backgroundColor(this.bindKind === option.kind ? $r('app.color.oc_brand_bg') : $r('sys.color.comp_background_list_card'))
            .borderRadius(16)
            .onClick(() => {
              this.bindKind = option.kind;
              this.bindValue = '';
            })
        }, (option: BindKindOption) => option.kind)
        Blank()
      }
      .width('100%')

      TextInput({ placeholder: '绑定名，如 DB / CACHE / BUCKET', text: this.fName })
        .onChange((value: string) => {
          this.fName = value;
        })

      if (this.vm.resourcesLoading) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(BRAND_ORANGE)
          Text('正在加载可选资源…')
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
        }
      } else if (this.candidates().length === 0) {
        Text('没有可绑定的资源，或当前授权未包含该类资源的读权限')
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      } else {
        List({ space: 6 }) {
          ForEach(this.candidates(), (item: BindCandidate) => {
            ListItem() {
              Row({ space: 10 }) {
                Radio({ value: item.value, group: 'bindTarget' })
                  .checked(this.bindValue === item.value)
                  .radioStyle({ checkedBackgroundColor: BRAND_ORANGE })
                  .onChange((checked: boolean) => {
                    if (checked) {
                      this.bindValue = item.value;
                    }
                  })
                Text(item.title)
                  .fontSize(14)
                  .fontColor($r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .onClick(() => {
                this.bindValue = item.value;
              })
            }
          }, (item: BindCandidate) => item.value)
        }
        .height(180)
        .width('100%')
        .backgroundColor($r('sys.color.comp_background_list_card'))
        .borderRadius(OCLayout.chipRadius)
        .border({ width: 0.5, color: $r('sys.color.comp_divider') })
      }

      Button(this.vm.isSaving ? '正在绑定…' : '绑定')
        .width('100%')
        .height(46)
        .backgroundColor($r('app.color.oc_brand'))
        .enabled(!this.vm.isSaving && this.fName.trim() !== '' && this.bindValue !== '')
        .onClick(() => {
          const name = this.fName.trim();
          if (this.vm.hasName(name)) {
            this.toast('已有同名绑定，请换一个绑定名');
            return;
          }
          this.vm.bindResource(accountStore.selectedId, this.scriptName, this.bindKind, name, this.bindValue)
            .then((err: string) => {
              if (err === '') {
                this.bindSheetVisible = false;
                this.toast('已绑定');
              } else {
                this.toast(err);
              }
            });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  // MARK: - 分区

  @Builder
  secretsSection() {
    Column({ space: 8 }) {
      this.sectionHeader('密钥（长按删除）', '批量导入', () => {
        this.openImportSheet('secret');
      }, '添加', () => {
        this.openSecretSheet();
      })
      GlassIsland({ pad: 0, cornerRadius: OCLayout.chipRadius }) {
        if (this.vm.secrets.length === 0) {
          this.emptyRow('尚无密钥')
        } else {
          ForEach(this.vm.secrets, (secret: WorkerSecret, index: number) => {
            this.entryRow('密钥', secret.name, '值不可读取，可覆盖或删除', () => {
              if (!this.canWrite()) {
                return;
              }
              this.confirmRemove('删除密钥', `将删除 ${secret.name}，脚本内读取该密钥的代码会失效。`, () => {
                this.vm.deleteSecret(accountStore.selectedId, this.scriptName, secret.name)
                  .then((err: string) => {
                    this.toast(err === '' ? '已删除' : err);
                  });
              });
            }, () => {
            })
            if (index < this.vm.secrets.length - 1) {
              this.divider()
            }
          }, (secret: WorkerSecret) => secret.name)
        }
      }
    }
    .width('100%')
  }

  @Builder
  variablesSection() {
    Column({ space: 8 }) {
      this.sectionHeader('环境变量（点按编辑，长按删除）', '批量导入', () => {
        this.openImportSheet('variable');
      }, '添加', () => {
        this.openVariableSheet(null);
      })
      GlassIsland({ pad: 0, cornerRadius: OCLayout.chipRadius }) {
        if (this.vm.variables.length === 0) {
          this.emptyRow('尚无环境变量')
        } else {
          ForEach(this.vm.variables, (binding: WorkerBindingInfo, index: number) => {
            this.entryRow('变量', binding.name ?? '', binding.text ?? '', () => {
              if (!this.canWrite()) {
                return;
              }
              this.confirmRemove('删除变量', `将删除 ${binding.name ?? ''}。`, () => {
                this.vm.removeBinding(accountStore.selectedId, this.scriptName, binding.name ?? '')
                  .then((err: string) => {
                    this.toast(err === '' ? '已删除' : err);
                  });
              });
            }, () => {
              this.openVariableSheet(binding);
            })
            if (index < this.vm.variables.length - 1) {
              this.divider()
            }
          }, (binding: WorkerBindingInfo) => binding.name ?? '')
        }
      }
    }
    .width('100%')
  }

  @Builder
  otherSection() {
    Column({ space: 8 }) {
      this.sectionHeader('其它绑定（长按解绑 D1 / KV / R2）', '', () => {
      }, this.canBind() ? '绑定资源' : '', () => {
        this.openBindSheet();
      })
      GlassIsland({ pad: 0, cornerRadius: OCLayout.chipRadius }) {
        if (this.vm.otherBindings.length === 0) {
          this.emptyRow('尚无其它绑定')
        } else {
          ForEach(this.vm.otherBindings, (binding: WorkerBindingInfo, index: number) => {
            this.entryRow(
              bindingTypeLabel(binding.type ?? ''),
              binding.name ?? '',
              bindingIsQuickManaged(binding) ? '长按可解绑' : '在 Cloudflare 控制台管理',
              () => {
                if (!bindingIsQuickManaged(binding)) {
                  this.toast('该类型绑定本客户端只读，请到 Cloudflare 控制台管理');
                  return;
                }
                if (!this.canWrite()) {
                  return;
                }
                this.confirmRemove('解除绑定', `将解除 ${binding.name ?? ''}，脚本内使用该绑定的代码会失效。`, () => {
                  this.vm.removeBinding(accountStore.selectedId, this.scriptName, binding.name ?? '')
                    .then((err: string) => {
                      this.toast(err === '' ? '已解绑' : err);
                    });
                });
              },
              () => {
              })
            if (index < this.vm.otherBindings.length - 1) {
              this.divider()
            }
          }, (binding: WorkerBindingInfo) => `${binding.type ?? ''}/${binding.name ?? ''}`)
        }
      }
    }
    .width('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading && !this.vm.loaded) {
          Column() {
            OCLoading({ text: '正在加载变量与密钥…' })
          }
          .width('100%')
          .height('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            Scroll() {
              Column({ space: 18 }) {
                if (this.vm.error !== '') {
                  Text(this.vm.error)
                    .fontSize(12)
                    .fontColor(DANGER_RED)
                    .width('100%')
                }
                RevealBox({ idx: 0 }) {
                  this.secretsSection()
                }
                RevealBox({ idx: 1 }) {
                  this.variablesSection()
                }
                RevealBox({ idx: 2 }) {
                  this.otherSection()
                }
              }
              .width('100%')
              .padding(OCLayout.pagePadding)
            }
            .align(Alignment.Top)
            .scrollBar(BarState.Off)
            .width('100%')
            .height('100%')
          }
          .onRefreshing(() => {
            this.refreshing = true;
            this.vm.load(accountStore.selectedId, this.scriptName).then(() => {
              this.refreshing = false;
            }).catch(() => {
              this.refreshing = false;
            });
          })
        }
      }
      .width('100%')
      .height('100%')
    }
    .title('变量与密钥')
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.secretSheetVisible, this.secretSheet(), ocSheet(() => {
      this.secretSheetVisible = false;
    }))
    .bindSheet(this.variableSheetVisible, this.variableSheet(), ocSheet(() => {
      this.variableSheetVisible = false;
    }))
    .bindSheet(this.importSheetVisible, this.importSheet(), ocSheet(() => {
      this.importSheetVisible = false;
    }))
    .bindSheet(this.bindSheetVisible, this.resourceSheet(), ocSheet(() => {
      this.bindSheetVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as NameParam;
      this.scriptName = param.name;
      this.reload();
    })
  }
}
