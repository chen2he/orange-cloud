// Rulesets phase 泛化列表页（对照 iOS ZonePhaseRulesListView + ZoneRuleEditorView）：
// 列表 / 启停 / 删除 / 新建 / 编辑，编辑器按 phase 给出对应 action 参数表单。
// 支持 phase：单条重定向（redirect）/ 源站规则（route）/ 配置规则（set_config）/
// 压缩规则（compress_response）/ 自定义错误（serve_error）。
// 编辑既有规则时以原 action_parameters 对象为底叠加改动，未建模字段原样保留。
import {
  CompressionAlgorithm,
  OriginOverride,
  PhaseMeta,
  RedirectFromValue,
  RedirectTargetUrl,
  RuleActionParameters,
  RulesetPhases,
  RulesetRule,
  RulesetRuleCreate,
  phaseMeta,
} from '../../models/RulesetModels';
import { PhaseRulesParam } from '../../models/Routes';
import { RulesetVM } from '../../services/RulesetService';
import { authManager } from '../../core/auth/AuthManager';
import { BRAND_ORANGE, BRAND_ORANGE_BG, OCEmpty, OCError, OCLoading } from '../common/Components';
import { RuleRow } from './RuleComponents';
import { ExpressionBuilder } from './ExpressionBuilder';
import { lintExpression } from '../../models/RuleExpressionBuilder';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

const REDIRECT_CODES: number[] = [301, 302, 303, 307, 308];
const ALL_ALGORITHMS: string[] = ['auto', 'default', 'gzip', 'brotli', 'zstd', 'none'];
const SSL_OPTIONS: string[] = ['off', 'flexible', 'full', 'strict', 'origin_pull'];
const SECURITY_OPTIONS: string[] = ['off', 'essentially_off', 'low', 'medium', 'high', 'under_attack'];
const POLISH_OPTIONS: string[] = ['off', 'lossless', 'lossy', 'webp'];
/// 三态：不覆盖（不出现在参数里）/ 开启 / 关闭
const TRI_STATE_LABELS: string[] = ['不覆盖', '开启', '关闭'];

function selectOptions(labels: string[]): SelectOption[] {
  const opts: SelectOption[] = [];
  for (const label of labels) {
    opts.push({ value: label } as SelectOption);
  }
  return opts;
}

function triStateIndex(state: string): number {
  if (state === 'on') {
    return 1;
  }
  if (state === 'off') {
    return 2;
  }
  return 0;
}

function triStateFromIndex(index: number): string {
  if (index === 1) {
    return 'on';
  }
  if (index === 2) {
    return 'off';
  }
  return 'unset';
}

function triStateOf(value: boolean | undefined): string {
  if (value === undefined) {
    return 'unset';
  }
  return value ? 'on' : 'off';
}

function boolOfTriState(state: string): boolean | undefined {
  if (state === 'on') {
    return true;
  }
  if (state === 'off') {
    return false;
  }
  return undefined;
}

function phaseSymbol(phase: string): Resource {
  if (phase === RulesetPhases.SINGLE_REDIRECT) {
    return $r('sys.symbol.arrow_right');
  }
  if (phase === RulesetPhases.ORIGIN) {
    return $r('sys.symbol.externaldrive');
  }
  if (phase === RulesetPhases.COMPRESSION) {
    return $r('sys.symbol.square_stack_3d');
  }
  if (phase === RulesetPhases.CUSTOM_ERRORS) {
    return $r('sys.symbol.exclamationmark_triangle');
  }
  return $r('sys.symbol.line_3_horizontal');
}

@ComponentV2
export struct PhaseRulesPage {
  @Local vm: RulesetVM = new RulesetVM('');
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local phase: string = '';
  @Local pageTitle: string = '规则';
  @Local editorVisible: boolean = false;
  @Local editingId: string = '';
  // —— 通用字段 ——
  @Local fDescription: string = '';
  @Local fExpression: string = '';
  @Local fEnabled: boolean = true;
  // —— 单条重定向 ——
  @Local fRedirIsExpr: boolean = false;
  @Local fRedirTarget: string = '';
  @Local fRedirStatus: number = 301;
  @Local fRedirPreserve: boolean = false;
  @Local editingFromList: boolean = false;
  // —— 源站规则 ——
  @Local fHostHeader: string = '';
  @Local fOriginHost: string = '';
  @Local fOriginPort: string = '';
  // —— 配置规则（三态开关 + 选项） ——
  @Local fCfgHttps: string = 'unset';
  @Local fCfgBic: string = 'unset';
  @Local fCfgEmailObf: string = 'unset';
  @Local fCfgRocket: string = 'unset';
  @Local fCfgOppEnc: string = 'unset';
  @Local fCfgSecurity: string = 'unset';
  @Local fCfgSsl: string = 'unset';
  @Local fCfgPolish: string = 'unset';
  // —— 压缩规则 ——
  @Local fAlgos: string[] = [];
  // —— 自定义错误 ——
  @Local fErrType: string = 'text/html';
  @Local fErrStatus: string = '';
  @Local fErrContent: string = '';
  @Local editingAssetName: string = '';
  /// 编辑底座：既有规则的 action_parameters 原对象，未建模字段随之保留
  private editBase: RuleActionParameters | null = null;

  private meta(): PhaseMeta {
    return phaseMeta(this.phase);
  }

  private canWrite(): boolean {
    return authManager.hasScope(this.meta().writeScope);
  }

  private guardWrite(): boolean {
    if (!this.canWrite()) {
      this.toast(`当前授权未包含编辑权限（${this.meta().writeScope}）`);
      return false;
    }
    return true;
  }

  private toast(message: string): void {
    if (message !== '') {
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
  }

  private rules(): RulesetRule[] {
    return this.vm.ruleset?.rules ?? [];
  }

  private openEditor(rule: RulesetRule | null): void {
    this.vm.saveError = '';
    if (rule) {
      this.editingId = rule.id;
      this.fDescription = rule.description ?? '';
      this.fExpression = rule.expression ?? '';
      this.fEnabled = rule.enabled !== false;
      this.editBase = rule.action_parameters ?? null;
      const p = rule.action_parameters;
      // 单条重定向
      const target = p?.from_value?.target_url;
      this.fRedirIsExpr = target?.expression !== undefined;
      this.fRedirTarget = target?.expression ?? target?.value ?? '';
      this.fRedirStatus = p?.from_value?.status_code ?? 301;
      this.fRedirPreserve = p?.from_value?.preserve_query_string === true;
      this.editingFromList = p?.from_list !== undefined;
      // 源站规则
      this.fHostHeader = p?.host_header ?? '';
      this.fOriginHost = p?.origin?.host ?? '';
      const port = p?.origin?.port;
      this.fOriginPort = port !== undefined ? `${port}` : '';
      // 配置规则
      this.fCfgHttps = triStateOf(p?.automatic_https_rewrites);
      this.fCfgBic = triStateOf(p?.bic);
      this.fCfgEmailObf = triStateOf(p?.email_obfuscation);
      this.fCfgRocket = triStateOf(p?.rocket_loader);
      this.fCfgOppEnc = triStateOf(p?.opportunistic_encryption);
      this.fCfgSecurity = p?.security_level ?? 'unset';
      this.fCfgSsl = p?.ssl ?? 'unset';
      this.fCfgPolish = p?.polish ?? 'unset';
      // 压缩规则
      const algos: string[] = [];
      for (const algo of p?.algorithms ?? []) {
        if (algo.name !== undefined && algo.name !== '') {
          algos.push(algo.name);
        }
      }
      this.fAlgos = algos;
      // 自定义错误
      this.fErrType = p?.content_type ?? 'text/html';
      const code = p?.status_code;
      this.fErrStatus = code !== undefined ? `${code}` : '';
      this.fErrContent = p?.content ?? '';
      this.editingAssetName = p?.asset_name ?? '';
    } else {
      this.editingId = '';
      this.fDescription = '';
      this.fExpression = '';
      this.fEnabled = true;
      this.editBase = null;
      this.fRedirIsExpr = false;
      this.fRedirTarget = '';
      this.fRedirStatus = 301;
      this.fRedirPreserve = false;
      this.editingFromList = false;
      this.fHostHeader = '';
      this.fOriginHost = '';
      this.fOriginPort = '';
      this.fCfgHttps = 'unset';
      this.fCfgBic = 'unset';
      this.fCfgEmailObf = 'unset';
      this.fCfgRocket = 'unset';
      this.fCfgOppEnc = 'unset';
      this.fCfgSecurity = 'unset';
      this.fCfgSsl = 'unset';
      this.fCfgPolish = 'unset';
      this.fAlgos = [];
      this.fErrType = 'text/html';
      this.fErrStatus = '';
      this.fErrContent = '';
      this.editingAssetName = '';
    }
    this.editorVisible = true;
  }

  private configTouched(): boolean {
    return this.fCfgHttps !== 'unset' || this.fCfgBic !== 'unset' || this.fCfgEmailObf !== 'unset' ||
      this.fCfgRocket !== 'unset' || this.fCfgOppEnc !== 'unset' || this.fCfgSecurity !== 'unset' ||
      this.fCfgSsl !== 'unset' || this.fCfgPolish !== 'unset';
  }

  private canSave(): boolean {
    if (this.vm.isSaving || this.fExpression.trim() === '') {
      return false;
    }
    if (this.phase === RulesetPhases.SINGLE_REDIRECT) {
      return !this.editingFromList && this.fRedirTarget.trim() !== '';
    }
    if (this.phase === RulesetPhases.ORIGIN) {
      const portText = this.fOriginPort.trim();
      if (portText !== '') {
        const port = Number.parseInt(portText);
        if (Number.isNaN(port) || port < 1 || port > 65535) {
          return false;
        }
      }
      return this.fHostHeader.trim() !== '' || this.fOriginHost.trim() !== '' || portText !== '';
    }
    if (this.phase === RulesetPhases.CONFIG) {
      // schema 要求至少一项；编辑时未建模字段随底座保留也算
      return this.configTouched() || this.editingId !== '';
    }
    if (this.phase === RulesetPhases.COMPRESSION) {
      return this.fAlgos.length > 0;
    }
    if (this.phase === RulesetPhases.CUSTOM_ERRORS) {
      const statusText = this.fErrStatus.trim();
      if (statusText !== '') {
        const code = Number.parseInt(statusText);
        if (Number.isNaN(code) || code < 400 || code > 999) {
          return false;
        }
      }
      return this.editingAssetName !== '' || this.fErrContent.trim() !== '';
    }
    return false;
  }

  private buildParams(): RuleActionParameters {
    if (this.phase === RulesetPhases.SINGLE_REDIRECT) {
      // schema 封闭（target_url 恰含一项），整体重建
      const target: RedirectTargetUrl = {};
      if (this.fRedirIsExpr) {
        target.expression = this.fRedirTarget.trim();
      } else {
        target.value = this.fRedirTarget.trim();
      }
      const fromValue: RedirectFromValue = { target_url: target, status_code: this.fRedirStatus };
      if (this.fRedirPreserve) {
        fromValue.preserve_query_string = true;
      }
      const params: RuleActionParameters = { from_value: fromValue };
      return params;
    }
    const base: RuleActionParameters = this.editBase ?? ({} as RuleActionParameters);
    if (this.phase === RulesetPhases.ORIGIN) {
      const hostHeader = this.fHostHeader.trim();
      base.host_header = hostHeader === '' ? undefined : hostHeader;
      const host = this.fOriginHost.trim();
      const port = Number.parseInt(this.fOriginPort.trim());
      const hasPort = !Number.isNaN(port) && port >= 1 && port <= 65535;
      if (host !== '' || hasPort) {
        const origin: OriginOverride = {};
        if (host !== '') {
          origin.host = host;
        }
        if (hasPort) {
          origin.port = port;
        }
        base.origin = origin;
      } else {
        base.origin = undefined;
      }
      return base;
    }
    if (this.phase === RulesetPhases.CONFIG) {
      base.automatic_https_rewrites = boolOfTriState(this.fCfgHttps);
      base.bic = boolOfTriState(this.fCfgBic);
      base.email_obfuscation = boolOfTriState(this.fCfgEmailObf);
      base.rocket_loader = boolOfTriState(this.fCfgRocket);
      base.opportunistic_encryption = boolOfTriState(this.fCfgOppEnc);
      base.security_level = this.fCfgSecurity === 'unset' ? undefined : this.fCfgSecurity;
      base.ssl = this.fCfgSsl === 'unset' ? undefined : this.fCfgSsl;
      base.polish = this.fCfgPolish === 'unset' ? undefined : this.fCfgPolish;
      return base;
    }
    if (this.phase === RulesetPhases.COMPRESSION) {
      const algos: CompressionAlgorithm[] = [];
      for (const name of this.fAlgos) {
        algos.push({ name: name } as CompressionAlgorithm);
      }
      base.algorithms = algos;
      return base;
    }
    // 自定义错误
    base.content_type = this.fErrType;
    const code = Number.parseInt(this.fErrStatus.trim());
    base.status_code = (!Number.isNaN(code) && code >= 400 && code <= 999) ? code : undefined;
    if (this.editingAssetName === '') {
      base.content = this.fErrContent;
    }
    return base;
  }

  private submit(): void {
    const lint: string = lintExpression(this.fExpression.trim());
    if (lint !== '') {
      this.toast(lint);
      return;
    }
    const rule: RulesetRuleCreate = {
      action: this.meta().action,
      expression: this.fExpression.trim(),
      description: this.fDescription.trim(),
      enabled: this.fEnabled,
      action_parameters: this.buildParams(),
    };
    this.vm.save(this.zoneId, this.editingId, rule).then((ok: boolean) => {
      if (ok) {
        this.editorVisible = false;
        this.toast(this.editingId === '' ? '已创建' : '已保存');
      }
    });
  }

  private confirmDelete(rule: RulesetRule): void {
    this.getUIContext().showAlertDialog({
      title: `删除${this.meta().title}`,
      message: `确定删除「${rule.description ?? rule.id}」？此操作不可撤销，规则将立即停止生效。`,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.remove(this.zoneId, rule.id).then((err: string) => {
            this.toast(err === '' ? '已删除' : err);
          });
        },
      },
    });
  }

  // —— 编辑器分段 Builder ——
  // 注意：@Builder 按值传参不具备响应性，涉及 @Local 状态的行一律直接引用 this.* 内联书写。

  @Builder
  redirectFields() {
    Row({ space: 12 }) {
      Text('目标类型')
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
      Blank()
      Select(selectOptions(['静态 URL', '动态表达式']))
        .selected(this.fRedirIsExpr ? 1 : 0)
        .value(this.fRedirIsExpr ? '动态表达式' : '静态 URL')
        .font({ size: 13 })
        .onSelect((index: number) => {
          this.fRedirIsExpr = index === 1;
        })
    }
    .width('100%')

    TextInput({
      text: this.fRedirTarget,
      placeholder: this.fRedirIsExpr
        ? 'concat("https://example.com", http.request.uri.path)'
        : 'https://example.com/new/',
    })
      .fontSize(13)
      .width('100%')
      .onChange((value: string) => {
        this.fRedirTarget = value;
      })

    Row({ space: 12 }) {
      Text('状态码')
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
      Blank()
      Select(selectOptions(REDIRECT_CODES.map((code: number) => `${code}`)))
        .selected(Math.max(REDIRECT_CODES.indexOf(this.fRedirStatus), 0))
        .value(`${this.fRedirStatus}`)
        .font({ size: 13 })
        .onSelect((index: number) => {
          this.fRedirStatus = REDIRECT_CODES[index];
        })
    }
    .width('100%')

    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text('保留查询字符串')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
        Text('301/308 永久跳转，302/303/307 临时跳转')
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.fRedirPreserve })
        .selectedColor(BRAND_ORANGE)
        .onChange((isOn: boolean) => {
          this.fRedirPreserve = isOn;
        })
    }
    .width('100%')
  }

  @Builder
  originFields() {
    TextInput({ text: this.fHostHeader, placeholder: 'Host 标头覆盖（可选），如 origin.example.com' })
      .fontSize(13)
      .width('100%')
      .onChange((value: string) => {
        this.fHostHeader = value;
      })
    TextInput({ text: this.fOriginHost, placeholder: '源站主机（可选）' })
      .fontSize(13)
      .width('100%')
      .onChange((value: string) => {
        this.fOriginHost = value;
      })
    TextInput({ text: this.fOriginPort, placeholder: '源站端口（可选，1–65535）' })
      .type(InputType.Number)
      .fontSize(13)
      .width('100%')
      .onChange((value: string) => {
        this.fOriginPort = value;
      })
    Text('至少设置一项。匹配的请求将按此覆盖回源目标。')
      .fontSize(11)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')
  }

  @Builder
  configLabel(label: string) {
    Text(label)
      .fontSize(14)
      .fontColor($r('sys.color.font_primary'))
  }

  @Builder
  configFields() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        this.configLabel('自动 HTTPS 重写')
        Blank()
        Select(selectOptions(TRI_STATE_LABELS))
          .selected(triStateIndex(this.fCfgHttps))
          .value(TRI_STATE_LABELS[triStateIndex(this.fCfgHttps)])
          .font({ size: 13 })
          .onSelect((index: number) => {
            this.fCfgHttps = triStateFromIndex(index);
          })
      }
      .width('100%')

      Row({ space: 12 }) {
        this.configLabel('浏览器完整性检查')
        Blank()
        Select(selectOptions(TRI_STATE_LABELS))
          .selected(triStateIndex(this.fCfgBic))
          .value(TRI_STATE_LABELS[triStateIndex(this.fCfgBic)])
          .font({ size: 13 })
          .onSelect((index: number) => {
            this.fCfgBic = triStateFromIndex(index);
          })
      }
      .width('100%')

      Row({ space: 12 }) {
        this.configLabel('Email 混淆')
        Blank()
        Select(selectOptions(TRI_STATE_LABELS))
          .selected(triStateIndex(this.fCfgEmailObf))
          .value(TRI_STATE_LABELS[triStateIndex(this.fCfgEmailObf)])
          .font({ size: 13 })
          .onSelect((index: number) => {
            this.fCfgEmailObf = triStateFromIndex(index);
          })
      }
      .width('100%')

      Row({ space: 12 }) {
        this.configLabel('Rocket Loader')
        Blank()
        Select(selectOptions(TRI_STATE_LABELS))
          .selected(triStateIndex(this.fCfgRocket))
          .value(TRI_STATE_LABELS[triStateIndex(this.fCfgRocket)])
          .font({ size: 13 })
          .onSelect((index: number) => {
            this.fCfgRocket = triStateFromIndex(index);
          })
      }
      .width('100%')

      Row({ space: 12 }) {
        this.configLabel('机会性加密')
        Blank()
        Select(selectOptions(TRI_STATE_LABELS))
          .selected(triStateIndex(this.fCfgOppEnc))
          .value(TRI_STATE_LABELS[triStateIndex(this.fCfgOppEnc)])
          .font({ size: 13 })
          .onSelect((index: number) => {
            this.fCfgOppEnc = triStateFromIndex(index);
          })
      }
      .width('100%')

      Row({ space: 12 }) {
        this.configLabel('安全级别')
        Blank()
        Select(selectOptions(['不覆盖'].concat(SECURITY_OPTIONS)))
          .selected(this.fCfgSecurity === 'unset' ? 0 : SECURITY_OPTIONS.indexOf(this.fCfgSecurity) + 1)
          .value(this.fCfgSecurity === 'unset' ? '不覆盖' : this.fCfgSecurity)
          .font({ size: 13 })
          .onSelect((index: number) => {
            this.fCfgSecurity = index === 0 ? 'unset' : SECURITY_OPTIONS[index - 1];
          })
      }
      .width('100%')

      Row({ space: 12 }) {
        this.configLabel('SSL')
        Blank()
        Select(selectOptions(['不覆盖'].concat(SSL_OPTIONS)))
          .selected(this.fCfgSsl === 'unset' ? 0 : SSL_OPTIONS.indexOf(this.fCfgSsl) + 1)
          .value(this.fCfgSsl === 'unset' ? '不覆盖' : this.fCfgSsl)
          .font({ size: 13 })
          .onSelect((index: number) => {
            this.fCfgSsl = index === 0 ? 'unset' : SSL_OPTIONS[index - 1];
          })
      }
      .width('100%')

      Row({ space: 12 }) {
        this.configLabel('Polish')
        Blank()
        Select(selectOptions(['不覆盖'].concat(POLISH_OPTIONS)))
          .selected(this.fCfgPolish === 'unset' ? 0 : POLISH_OPTIONS.indexOf(this.fCfgPolish) + 1)
          .value(this.fCfgPolish === 'unset' ? '不覆盖' : this.fCfgPolish)
          .font({ size: 13 })
          .onSelect((index: number) => {
            this.fCfgPolish = index === 0 ? 'unset' : POLISH_OPTIONS[index - 1];
          })
      }
      .width('100%')

      Text('至少覆盖一项。仅设置为「不覆盖」以外的项会被此规则覆盖；编辑时未列出的既有设置保持不变。')
        .fontSize(11)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
    }
    .width('100%')
  }

  @Builder
  compressionFields() {
    Text('压缩算法（按偏好排序，点击已选项移除，点击待选项追加）')
      .fontSize(12)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.fAlgos, (name: string, index: number) => {
        Text(`${index + 1}. ${name} ×`)
          .fontSize(12)
          .fontColor(Color.White)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(BRAND_ORANGE)
          .borderRadius(12)
          .margin({ right: 8, bottom: 8 })
          .onClick(() => {
            this.fAlgos = this.fAlgos.filter((item: string) => item !== name);
          })
      }, (name: string) => `sel-${name}`)
    }
    .width('100%')

    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(ALL_ALGORITHMS.filter((name: string) => !this.fAlgos.includes(name)), (name: string) => {
        Text(`+ ${name}`)
          .fontSize(12)
          .fontColor(BRAND_ORANGE)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(BRAND_ORANGE_BG)
          .borderRadius(12)
          .margin({ right: 8, bottom: 8 })
          .onClick(() => {
            this.fAlgos = this.fAlgos.concat([name]);
          })
      }, (name: string) => `avail-${name}`)
    }
    .width('100%')

    Text('Cloudflare 使用列表中访客浏览器支持的第一个算法；none 表示不压缩，auto/default 交给 Cloudflare 决定。')
      .fontSize(11)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')
  }

  @Builder
  customErrorFields() {
    Row({ space: 12 }) {
      Text('内容类型')
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
      Blank()
      Select(selectOptions(['text/html', 'application/json', 'text/plain', 'text/xml']))
        .selected(Math.max(['text/html', 'application/json', 'text/plain', 'text/xml'].indexOf(this.fErrType), 0))
        .value(this.fErrType)
        .font({ size: 13 })
        .onSelect((index: number) => {
          this.fErrType = ['text/html', 'application/json', 'text/plain', 'text/xml'][index];
        })
    }
    .width('100%')

    TextInput({ text: this.fErrStatus, placeholder: '状态码（可选，400–999，不填沿用原状态）' })
      .type(InputType.Number)
      .fontSize(13)
      .width('100%')
      .onChange((value: string) => {
        this.fErrStatus = value;
      })

    if (this.editingAssetName !== '') {
      Text(`内容由自定义资产「${this.editingAssetName}」提供，App 内不改动资产本身。`)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
    } else {
      TextArea({ text: this.fErrContent, placeholder: '响应内容（最大 10 KB），将按上方内容类型原样返回' })
        .fontSize(13)
        .height(120)
        .width('100%')
        .onChange((value: string) => {
          this.fErrContent = value;
        })
    }
  }

  @Builder
  editorSheet() {
    Scroll() {
      Column({ space: 12 }) {
        Text(this.editingId === '' ? `新建${this.meta().title}` : `编辑${this.meta().title}`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .margin({ top: 8 })

        if (this.editingFromList) {
          Text('该规则基于批量列表（from_list），请在 Cloudflare Dashboard 编辑。')
            .fontSize(12)
            .fontColor('#DC2626')
            .width('100%')
        }

        TextInput({ text: this.fDescription, placeholder: '规则描述（可选）' })
          .fontSize(14)
          .width('100%')
          .onChange((value: string) => {
            this.fDescription = value;
          })

        Row({ space: 12 }) {
          Text('启用')
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.fEnabled })
            .selectedColor(BRAND_ORANGE)
            .onChange((isOn: boolean) => {
              this.fEnabled = isOn;
            })
        }
        .width('100%')

        ExpressionBuilder({
          expression: this.fExpression,
          onChange: (e: string) => {
            this.fExpression = e;
          },
        })

        if (this.phase === RulesetPhases.SINGLE_REDIRECT) {
          this.redirectFields()
        } else if (this.phase === RulesetPhases.ORIGIN) {
          this.originFields()
        } else if (this.phase === RulesetPhases.CONFIG) {
          this.configFields()
        } else if (this.phase === RulesetPhases.COMPRESSION) {
          this.compressionFields()
        } else if (this.phase === RulesetPhases.CUSTOM_ERRORS) {
          this.customErrorFields()
        }

        if (this.vm.saveError !== '') {
          Text(this.vm.saveError)
            .fontSize(13)
            .fontColor('#DC2626')
            .width('100%')
        }

        Button(this.vm.isSaving ? '正在保存…' : (this.editingId === '' ? '创建' : '保存'))
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor(BRAND_ORANGE)
          .enabled(this.canSave())
          .onClick(() => {
            this.submit();
          })
      }
      .padding({ left: 20, right: 20, bottom: 24 })
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .width('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading) {
          Column() {
            OCLoading({ text: `正在加载${this.pageTitle}…` })
          }
          .width('100%')
          .height('100%')
        } else if (this.vm.error !== '') {
          Column() {
            OCError({
              message: this.vm.error,
              onRetry: () => {
                this.vm.load(this.zoneId).catch(() => {
                });
              },
            })
          }
          .width('100%')
          .height('100%')
        } else if (this.rules().length === 0) {
          Column() {
            OCEmpty({
              symbol: phaseSymbol(this.phase),
              title: `暂无${this.pageTitle}`,
              subtitle: '点右下角 + 创建第一条规则',
            })
          }
          .width('100%')
          .height('100%')
        } else {
          List() {
            ForEach(this.rules(), (rule: RulesetRule) => {
              ListItem() {
                RuleRow({
                  rule: rule,
                  busy: this.vm.isSaving,
                  onEdit: () => {
                    this.openEditor(rule);
                  },
                  onToggle: (enabled: boolean) => {
                    if (!this.guardWrite()) {
                      this.vm.load(this.zoneId).catch(() => {
                      });
                      return;
                    }
                    this.vm.toggle(this.zoneId, rule.id, enabled).then((err: string) => {
                      this.toast(err);
                    });
                  },
                  onDelete: () => {
                    if (!this.guardWrite()) {
                      return;
                    }
                    this.confirmDelete(rule);
                  },
                })
              }
            }, (rule: RulesetRule) => rule.id)
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
          .backgroundColor(BRAND_ORANGE)
          .borderRadius(26)
          .shadow({ radius: 12, color: '#40000000', offsetY: 4 })
          .margin({ right: 20, bottom: 28 })
          .onClick(() => {
            if (!this.guardWrite()) {
              return;
            }
            this.openEditor(null);
          })
      }
      .width('100%')
      .height('100%')
    }
    .title(`${this.zoneName} · ${this.pageTitle}`)
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.editorVisible, this.editorSheet(), ocSheet(() => {
      this.editorVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as PhaseRulesParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      this.phase = param.phase;
      this.pageTitle = param.title;
      this.vm = new RulesetVM(param.phase);
      this.vm.load(param.zoneId).catch(() => {
      });
    })
  }
}
