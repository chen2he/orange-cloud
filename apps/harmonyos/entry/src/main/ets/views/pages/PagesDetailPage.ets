import { HdsNavDestination } from '@kit.UIDesignKit';
// Pages 项目详情：信息 + 构建配置（可编辑）+ 环境变量（只读）+ 部署记录（点按进部署详情）
// + 自定义域名 + 删除项目（对齐 iOS PagesProjectDetailView）。
import { PagesDeployment, PagesDomain } from '../../models/WorkerModels';
import { NameParam, PagesDeploymentParam, Routes } from '../../models/Routes';
import {
  PagesBuildConfigPayload,
  PagesEnvConfig,
  PagesProjectDetail,
  PagesProjectUpdate,
  PagesService,
} from '../../services/PagesService';
import { accountStore } from '../../core/store/AccountStore';
import { authManager } from '../../core/auth/AuthManager';
import { Scopes } from '../../core/auth/Scopes';
import { formatTimeAgo } from '../../core/util/Format';
import { BRAND_ORANGE, BRAND_ORANGE_BG, DANGER_RED, InfoRow, NavRow, OCLoading } from '../common/Components';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';
import { PagesDeploySheet, PagesDeployVM } from './PagesDeploy';
import { OCLayout } from '../common/Daybreak';

function stageColor(status: string): string {
  if (status === 'success') {
    return '#22C55E';
  }
  if (status === 'failure' || status === 'canceled') {
    return DANGER_RED;
  }
  if (status === 'active' || status === 'building') {
    return '#EAB308';
  }
  return '#9CA3AF';
}

/// 环境变量展示行（GET 项目时 secret_text 的 value 已脱敏为 null，App 内只读）
interface EnvVarItem {
  key: string;
  value: string;
  isSecret: boolean;
}

function envItems(config: PagesEnvConfig | undefined): EnvVarItem[] {
  const items: EnvVarItem[] = [];
  const vars = config?.env_vars;
  if (vars === undefined) {
    return items;
  }
  for (const key of Object.keys(vars)) {
    const envVar = vars[key];
    items.push({
      key: key,
      value: envVar?.value ?? '',
      isSecret: (envVar?.type ?? '') === 'secret_text',
    } as EnvVarItem);
  }
  return items;
}

@ObservedV2
class PagesDetailVM {
  @Trace project: PagesProjectDetail | null = null;
  @Trace deployments: PagesDeployment[] = [];
  @Trace domains: PagesDomain[] = [];
  @Trace isLoading: boolean = false;
  @Trace isSaving: boolean = false;
  @Trace saveError: string = '';
  private service: PagesService = new PagesService();

  async load(projectName: string): Promise<void> {
    this.isLoading = true;
    const accountId = accountStore.selectedId;
    try {
      this.project = await this.service.getProject(accountId, projectName);
      try {
        this.deployments = await this.service.listDeployments(accountId, projectName);
      } catch (e) {
      }
      try {
        this.domains = await this.service.listDomains(accountId, projectName);
      } catch (e) {
      }
    } finally {
      this.isLoading = false;
    }
  }

  /// 静默刷新部署列表（从部署详情返回后同步重试 / 删除结果）
  async refreshDeployments(projectName: string): Promise<void> {
    try {
      this.deployments = await this.service.listDeployments(accountStore.selectedId, projectName);
    } catch (e) {
    }
  }

  /// PATCH 构建配置（仅传非空字段，顶层合并）
  async updateBuildConfig(projectName: string, buildCommand: string, destDir: string, rootDir: string,
    productionBranch: string): Promise<boolean> {
    this.isSaving = true;
    this.saveError = '';
    const build: PagesBuildConfigPayload = {} as PagesBuildConfigPayload;
    if (buildCommand !== '') {
      build.build_command = buildCommand;
    }
    if (destDir !== '') {
      build.destination_dir = destDir;
    }
    if (rootDir !== '') {
      build.root_dir = rootDir;
    }
    const update: PagesProjectUpdate = { build_config: build } as PagesProjectUpdate;
    if (productionBranch !== '') {
      update.production_branch = productionBranch;
    }
    try {
      this.project = await this.service.updateProject(accountStore.selectedId, projectName, update);
      return true;
    } catch (e) {
      this.saveError = (e as Error).message ?? '保存失败';
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  async remove(projectName: string): Promise<string> {
    try {
      await this.service.deleteProject(accountStore.selectedId, projectName);
      return '';
    } catch (e) {
      return (e as Error).message ?? '删除失败';
    }
  }
}

@ComponentV2
export struct PagesDetailPage {
  @Local vm: PagesDetailVM = new PagesDetailVM();
  @Local projectName: string = '';
  @Local showBuildConfig: boolean = false;
  @Local fBuildCommand: string = '';
  @Local fOutputDir: string = '';
  @Local fRootDir: string = '';
  @Local fProductionBranch: string = '';
  /// 直接上传部署（对照 iOS PagesDeployView）
  @Local deployVM: PagesDeployVM = new PagesDeployVM();
  @Local showDeploy: boolean = false;
  @Local revealedKeys: string[] = [];
  private pathStack: NavPathStack | null = null;
  private appearedOnce: boolean = false;

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  private confirmDelete(): void {
    this.getUIContext().showAlertDialog({
      title: '删除 Pages 项目',
      message: `确定删除「${this.projectName}」？部署与自定义域名会一并移除。`,
      primaryButton: { value: '取消', action: () => {
      } },
      secondaryButton: {
        value: '删除',
        fontColor: DANGER_RED,
        action: () => {
          this.vm.remove(this.projectName).then((err: string) => {
            if (err === '') {
              this.pathStack?.pop();
            } else {
              this.toast(err);
            }
          });
        },
      },
    });
  }

  private openBuildConfigSheet(): void {
    this.fBuildCommand = this.vm.project?.build_config?.build_command ?? '';
    this.fOutputDir = this.vm.project?.build_config?.destination_dir ?? '';
    this.fRootDir = this.vm.project?.build_config?.root_dir ?? '';
    this.fProductionBranch = this.vm.project?.production_branch ?? '';
    this.vm.saveError = '';
    this.showBuildConfig = true;
  }

  private toggleReveal(revealKey: string): void {
    if (this.revealedKeys.includes(revealKey)) {
      this.revealedKeys = this.revealedKeys.filter((item: string) => item !== revealKey);
    } else {
      this.revealedKeys = this.revealedKeys.concat([revealKey]);
    }
  }

  private envDisplay(envName: string, item: EnvVarItem): string {
    if (item.isSecret) {
      return '••••••';
    }
    if (this.revealedKeys.includes(`${envName}:${item.key}`)) {
      return item.value === '' ? '（空）' : item.value;
    }
    return '••••••';
  }

  // 分组小标签（对照样板 ZoneDetailPage 的组头）
  @Builder
  groupHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 4 })
  }

  /// Hero 卡（对照样板 ZoneDetailPage.heroCard）：Pages 图标 + 项目名大字 + 最近部署状态点·生产分支
  @Builder
  heroCard() {
    Column({ space: 10 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(26)
          .fontColor([$r('app.color.oc_brand_text')])
      }
      .width(52)
      .height(52)
      .backgroundColor($r('app.color.oc_brand_bg'))
      .borderRadius(14)

      Text(this.projectName)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 8 }) {
        if (this.vm.deployments.length > 0) {
          Row({ space: 5 }) {
            Circle({ width: 7, height: 7 })
              .fill(stageColor(this.vm.deployments[0].latest_stage?.status ?? ''))
            Text(`最近部署 ${formatTimeAgo(this.vm.deployments[0].created_on ?? '')}`)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
          }
        }
        Text(`分支 ${this.vm.project?.production_branch ?? '—'}`)
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
      }
    }
    .width('100%')
    .padding(OCLayout.islandPadding)
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(OCLayout.islandRadius)
    .border({ width: 0.5, color: $r('sys.color.comp_divider') })
    .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
  }

  @Builder
  deploySheet() {
    PagesDeploySheet({
      vm: this.deployVM,
      projectName: this.projectName,
      onDeployed: () => {
        this.showDeploy = false;
        // 新部署要落到部署列表里，成功后刷新一次
        this.vm.load(this.projectName).catch(() => {
        });
      },
    })
  }

  @Builder
  buildConfigSheet() {
    Column({ space: 12 }) {
      Text('构建配置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })
      Text('构建命令')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ text: this.fBuildCommand, placeholder: '如 npm run build' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fBuildCommand = value;
        })
      Text('输出目录（构建产物所在目录）')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ text: this.fOutputDir, placeholder: '如 dist' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fOutputDir = value;
        })
      Text('根目录（Monorepo 时构建的子目录，留空为仓库根）')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ text: this.fRootDir, placeholder: '如 apps/web' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fRootDir = value;
        })
      Text('生产分支（推送到该分支才触发生产部署）')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ text: this.fProductionBranch, placeholder: '如 main' })
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.fProductionBranch = value;
        })
      if (this.vm.saveError !== '') {
        Text(this.vm.saveError)
          .fontSize(13)
          .fontColor(DANGER_RED)
          .width('100%')
      }
      Button(this.vm.isSaving ? '正在保存…' : '保存')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isSaving)
        .onClick(() => {
          this.vm.updateBuildConfig(this.projectName,
            this.fBuildCommand.trim(), this.fOutputDir.trim(), this.fRootDir.trim(),
            this.fProductionBranch.trim())
            .then((ok: boolean) => {
              if (ok) {
                this.showBuildConfig = false;
                this.toast('构建配置已保存');
              }
            });
        })
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  @Builder
  envSection(envName: string, label: string, items: EnvVarItem[]) {
    Text(label)
      .fontSize(12)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 2 })
    ForEach(items, (item: EnvVarItem) => {
      Row({ space: 12 }) {
        Text(item.key)
          .fontSize(13)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        if (item.isSecret) {
          Text('密文')
            .fontSize(10)
            .fontColor($r('sys.color.font_secondary'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
            .border({ width: 0.5, color: $r('sys.color.comp_divider') })
        }
        Text(this.envDisplay(envName, item))
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '55%' })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .onClick(() => {
        if (!item.isSecret) {
          this.toggleReveal(`${envName}:${item.key}`);
        }
      })
    }, (item: EnvVarItem) => `${envName}:${item.key}`)
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: '正在加载项目…' })
          }
          .width('100%')
          .height('100%')
        } else {
          Scroll() {
            Column({ space: 18 }) {
              this.heroCard()

              // 项目信息（对照 iOS PagesProjectDetailView 信息组）
              Column({ space: 8 }) {
                this.groupHeader('项目信息')
                Column() {
                  InfoRow({ label: '子域名', value: this.vm.project?.subdomain ?? `${this.projectName}.pages.dev` })
                  InfoRow({ label: '生产分支', value: this.vm.project?.production_branch ?? '—' })
                  InfoRow({ label: '来源', value: this.vm.project?.source?.type ?? '直接上传' })
                }
                .width('100%')
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(OCLayout.chipRadius)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
                .clip(true)
              }
              .width('100%')

              Column({ space: 8 }) {
                this.groupHeader('构建配置')
                Column() {
                  InfoRow({ label: '构建命令', value: this.vm.project?.build_config?.build_command ?? '—' })
                  InfoRow({ label: '输出目录', value: this.vm.project?.build_config?.destination_dir ?? '—' })
                  InfoRow({ label: '根目录', value: this.vm.project?.build_config?.root_dir ?? '—' })
                  InfoRow({ label: '生产分支', value: this.vm.project?.production_branch ?? '—' })
                  if (authManager.hasScope(Scopes.PAGES_WRITE)) {
                    Row() {
                      Text('编辑构建配置')
                        .fontSize(14)
                        .fontColor($r('app.color.oc_brand_text'))
                      Blank()
                      Image($r('sys.media.ohos_ic_public_arrow_right'))
                        .width(16)
                        .height(16)
                        .fillColor($r('sys.color.font_tertiary'))
                    }
                    .width('100%')
                    .padding({ left: 16, right: 12, top: 12, bottom: 12 })
                    .onClick(() => {
                      this.openBuildConfigSheet();
                    })
                  }
                }
                .width('100%')
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(OCLayout.chipRadius)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
                .clip(true)
              }
              .width('100%')

              if (envItems(this.vm.project?.deployment_configs?.production).length > 0 ||
                envItems(this.vm.project?.deployment_configs?.preview).length > 0) {
                Column({ space: 8 }) {
                  this.groupHeader('环境变量 · 只读（点按明文变量可揭示）')
                  Column() {
                    if (envItems(this.vm.project?.deployment_configs?.production).length > 0) {
                      this.envSection('production', '生产环境',
                        envItems(this.vm.project?.deployment_configs?.production))
                    }
                    if (envItems(this.vm.project?.deployment_configs?.preview).length > 0) {
                      this.envSection('preview', '预览环境',
                        envItems(this.vm.project?.deployment_configs?.preview))
                    }
                  }
                  .width('100%')
                  .padding({ bottom: 6 })
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(OCLayout.chipRadius)
                  .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                  .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
                  .clip(true)
                }
                .width('100%')
              }

              Column({ space: 8 }) {
                this.groupHeader(`部署记录（${this.vm.deployments.length}）`)
                Column() {
                  ForEach(this.vm.deployments, (deploy: PagesDeployment) => {
                    Row({ space: 10 }) {
                      Circle({ width: 8, height: 8 })
                        .fill(stageColor(deploy.latest_stage?.status ?? ''))
                      Column({ space: 2 }) {
                        Text(`${deploy.environment ?? 'production'} · ${deploy.short_id ?? deploy.id.substring(0, 8)}`)
                          .fontSize(13)
                          .fontColor($r('sys.color.font_primary'))
                        Text(`${deploy.latest_stage?.name ?? ''} ${deploy.latest_stage?.status ?? ''} · ${formatTimeAgo(deploy.created_on ?? '')}`)
                          .fontSize(11)
                          .fontColor($r('sys.color.font_secondary'))
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Image($r('sys.media.ohos_ic_public_arrow_right'))
                        .width(16)
                        .height(16)
                        .fillColor($r('sys.color.font_tertiary'))
                    }
                    .width('100%')
                    .padding({ left: 14, right: 12, top: 10, bottom: 10 })
                    .onClick(() => {
                      const param: PagesDeploymentParam = {
                        projectName: this.projectName,
                        deploymentId: deploy.id,
                        isProduction: (deploy.environment ?? 'production') === 'production',
                      };
                      this.pathStack?.pushPathByName(Routes.PAGES_DEPLOYMENT, param);
                    })
                  }, (deploy: PagesDeployment) => deploy.id)
                }
                .width('100%')
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(OCLayout.chipRadius)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
                .clip(true)
              }
              .width('100%')

              // 直接上传部署（粘贴代码 / 选文件），对照 iOS 项目详情的「部署」入口
              if (authManager.hasScope(Scopes.PAGES_WRITE)) {
                Column({ space: 8 }) {
                  this.groupHeader('部署')
                  Column() {
                    NavRow({
                      symbol: $r('sys.symbol.arrow_up_circle'),
                      title: '直接上传部署',
                      subtitle: '粘贴代码或选本地文件，跳过 Git 构建',
                      onNav: () => {
                        this.deployVM.clearFiles();
                        this.showDeploy = true;
                      },
                    })
                  }
                  .width('100%')
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(OCLayout.chipRadius)
                  .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                  .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
                  .clip(true)
                }
                .width('100%')
              }

              // 自定义域名：概览只读几行，管理（添加 / 删除 / 验证记录）进独立页
              Column({ space: 8 }) {
                this.groupHeader('自定义域名')
                Column() {
                  if (this.vm.domains.length === 0) {
                    Text('尚无自定义域名')
                      .fontSize(13)
                      .fontColor($r('sys.color.font_tertiary'))
                      .width('100%')
                      .padding(14)
                  } else {
                    ForEach(this.vm.domains, (domain: PagesDomain) => {
                      InfoRow({ label: domain.name, value: domain.status ?? '' })
                    }, (domain: PagesDomain) => domain.id)
                  }
                  Divider()
                    .strokeWidth(0.5)
                    .color($r('sys.color.comp_divider'))
                  NavRow({
                    symbol: $r('sys.symbol.globe_and_keyboard'),
                    title: '管理域名',
                    subtitle: '添加 / 删除 / 归属验证记录',
                    onNav: () => {
                      const param: NameParam = { name: this.projectName };
                      this.pathStack?.pushPathByName(Routes.PAGES_DOMAINS, param);
                    },
                  })
                }
                .width('100%')
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(OCLayout.chipRadius)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .shadow({ radius: 12, color: '#14000000', offsetY: 5 })
                .clip(true)
              }
              .width('100%')

              // 危险区（对照样板底部红色危险操作）
              Button('删除项目')
                .width('100%')
                .height(46)
                .fontSize(15)
                .fontColor(DANGER_RED)
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(OCLayout.chipRadius)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .margin({ bottom: 8 })
                .onClick(() => {
                  this.confirmDelete();
                })
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
      .width('100%')
      .height('100%')
    }
    .titleBar({ content: { title: { mainTitle: this.projectName } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.showDeploy, this.deploySheet(), ocSheet(() => {
      this.showDeploy = false;
    }))
    .bindSheet(this.showBuildConfig, this.buildConfigSheet(), ocSheet(() => {
      this.showBuildConfig = false;
    }))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as NameParam;
      this.projectName = param.name;
      this.vm.load(param.name).catch(() => {
      });
    })
    .onShown(() => {
      // 从部署详情页返回时静默刷新部署列表（重试 / 回滚 / 删除后同步状态）；首次进入由 onReady 全量加载
      if (!this.appearedOnce) {
        this.appearedOnce = true;
        return;
      }
      if (this.projectName !== '') {
        this.vm.refreshDeployments(this.projectName).catch(() => {
        });
      }
    })
  }
}
