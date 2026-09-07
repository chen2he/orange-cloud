import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { HdsListItem } from '@kit.UIDesignKit';
import { ocSnack } from '../common/Snack';
import { HdsNavDestination } from '@kit.UIDesignKit';
// DNS 记录列表（NavDestination）：读 + 新建 / 编辑 / 侧滑删除
import { DNSRecord, DNSRecordPayload } from '../../models/Models';
import { ZoneRouteParam } from '../../models/Routes';
import { DNSListViewModel } from '../../viewmodels/DNSListViewModel';
import { OCLayout } from '../common/Daybreak';
import { BRAND_ORANGE, BRAND_ORANGE_BG } from '../common/Components';
import { ocSheet } from '../common/Sheets';
import { OCSkyBackground } from '../common/OCSky';

const RECORD_TYPES: string[] = ['A', 'AAAA', 'CNAME', 'TXT', 'MX', 'NS', 'SRV', 'CAA', 'PTR'];
const TTL_PRESETS: number[] = [1, 60, 300, 1800, 3600, 86400];
/// 可开启 Cloudflare 代理的记录类型
const PROXYABLE_TYPES: string[] = ['A', 'AAAA', 'CNAME'];

function ttlLabel(ttl: number): string {
  if (ttl === 1) {
    return 'TTL 自动';
  }
  return `TTL ${ttl}s`;
}

function ttlOptionLabel(value: number): string {
  if (value === 1) {
    return '自动';
  }
  if (value < 3600) {
    return `${value / 60} 分钟`;
  }
  if (value < 86400) {
    return `${value / 3600} 小时`;
  }
  return `${value / 86400} 天`;
}

function contentPlaceholder(type: string): string {
  if (type === 'A') {
    return '例如 192.0.2.1';
  }
  if (type === 'AAAA') {
    return '例如 2001:db8::1';
  }
  if (type === 'CNAME') {
    return '例如 example.com';
  }
  if (type === 'MX') {
    return '例如 mail.example.com';
  }
  if (type === 'TXT') {
    return '文本内容';
  }
  return '记录值';
}

@ComponentV2
export struct DNSListPage {
  @Local vm: DNSListViewModel = new DNSListViewModel();
  @Local refreshing: boolean = false;
  @Local zoneId: string = '';
  @Local zoneName: string = '';

  // ---- 编辑表单状态（editingId 为空 = 新建）----
  @Local editorVisible: boolean = false;
  @Local editingId: string = '';
  @Local fType: string = 'A';
  @Local fName: string = '';
  @Local fContent: string = '';
  @Local fTtl: number = 1;
  @Local fTtlOptions: number[] = TTL_PRESETS;
  @Local fProxied: boolean = false;
  @Local fPriority: string = '10';
  @Local fComment: string = '';
  /// 列表搜索关键词（匹配名称 / 内容 / 类型 / 备注）
  @Local keyword: string = '';

  private openEditor(record: DNSRecord | null): void {
    this.vm.saveError = '';
    if (record) {
      this.editingId = record.id;
      this.fType = record.type;
      this.fName = record.name;
      this.fContent = record.content;
      this.fTtl = record.ttl;
      this.fProxied = record.proxied === true;
      this.fPriority = record.priority !== undefined ? `${record.priority}` : '10';
      this.fComment = record.comment ?? '';
      // 非预设 TTL（如企业套餐自定义值）追加为选项，避免打开即被改值
      this.fTtlOptions = TTL_PRESETS.includes(record.ttl)
        ? TTL_PRESETS
        : TTL_PRESETS.concat([record.ttl]);
    } else {
      this.editingId = '';
      this.fType = 'A';
      this.fName = '';
      this.fContent = '';
      this.fTtl = 1;
      this.fProxied = true;
      this.fPriority = '10';
      this.fComment = '';
      this.fTtlOptions = TTL_PRESETS;
    }
    this.editorVisible = true;
  }

  /// 关键词过滤（大小写不敏感，匹配名称 / 内容 / 类型 / 备注）
  private filteredRecords(): DNSRecord[] {
    const q = this.keyword.trim().toLowerCase();
    if (q === '') {
      return this.vm.records;
    }
    return this.vm.records.filter((r: DNSRecord) =>
      r.name.toLowerCase().includes(q) || r.content.toLowerCase().includes(q)
        || r.type.toLowerCase().includes(q) || (r.comment ?? '').toLowerCase().includes(q));
  }

  private submit(): void {
    const payload: DNSRecordPayload = {
      type: this.fType,
      name: this.fName.trim(),
      content: this.fContent.trim(),
      ttl: this.fTtl,
    };
    if (PROXYABLE_TYPES.includes(this.fType)) {
      payload.proxied = this.fProxied;
    }
    if (this.fType === 'MX') {
      const priority = Number.parseInt(this.fPriority);
      payload.priority = Number.isNaN(priority) ? 10 : priority;
    }
    // 备注：留空也要显式传空串，否则改不掉已有备注
    payload.comment = this.fComment.trim();
    this.vm.save(this.editingId, payload).then((ok: boolean) => {
      if (ok) {
        this.editorVisible = false;
      }
    });
  }

  private confirmDelete(record: DNSRecord): void {
    this.getUIContext().showAlertDialog({
      title: '删除记录',
      message: `确定删除 ${record.type} 记录「${record.name}」？此操作不可撤销。`,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#DC2626',
        action: () => {
          this.vm.remove(record).then((errorMessage: string) => {
            if (errorMessage !== '') {
              ocSnack(this.getUIContext(), errorMessage);
            }
          });
        },
      },
    });
  }

  /// 列表项卡片外壳（HdsListItem 的 customItemBuilder 用）
  @Builder
  recordCard(record: DNSRecord) {
    Column() {
      this.recordRow(record)
    }
    .width('100%')
    .backgroundColor($r('sys.color.comp_background_list_card'))
    .borderRadius(OCLayout.chipRadius)
  }

  @Builder
  deleteAction(record: DNSRecord) {
    Button('删除')
      .fontSize(14)
      .fontColor(Color.White)
      .backgroundColor('#DC2626')
      .height('100%')
      .borderRadius(0)
      .padding({ left: 20, right: 20 })
      .onClick(() => {
        this.confirmDelete(record);
      })
  }

  @Builder
  formLabel(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
  }

  @Builder
  editorSheet() {
    Column({ space: 14 }) {
      Text(this.editingId === '' ? '添加 DNS 记录' : '编辑 DNS 记录')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .margin({ top: 8 })

      this.formLabel('类型')
      Select(RECORD_TYPES.map((t: string): SelectOption => ({ value: t })))
        .selected(RECORD_TYPES.indexOf(this.fType))
        .value(this.fType)
        .font({ size: 15 })
        .width('100%')
        .onSelect((index: number) => {
          this.fType = RECORD_TYPES[index];
        })

      this.formLabel('名称')
      TextInput({ text: this.fName, placeholder: '@ 表示根域名，或如 www' })
        .fontSize(15)
        .width('100%')
        .onChange((value: string) => {
          this.fName = value;
        })

      this.formLabel('内容')
      TextInput({ text: this.fContent, placeholder: contentPlaceholder(this.fType) })
        .fontSize(15)
        .width('100%')
        .onChange((value: string) => {
          this.fContent = value;
        })

      if (this.fType === 'MX') {
        this.formLabel('优先级')
        TextInput({ text: this.fPriority, placeholder: '10' })
          .type(InputType.Number)
          .fontSize(15)
          .width('100%')
          .onChange((value: string) => {
            this.fPriority = value;
          })
      }

      this.formLabel('备注')
      TextInput({ text: this.fComment, placeholder: '可选备注（在 Cloudflare 控制台同样可见）' })
        .fontSize(15)
        .width('100%')
        .onChange((value: string) => {
          this.fComment = value;
        })

      Row() {
        Text('TTL')
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Select(this.fTtlOptions.map((v: number): SelectOption => ({ value: ttlOptionLabel(v) })))
          .selected(this.fTtlOptions.indexOf(this.fTtl))
          .value(ttlOptionLabel(this.fTtl))
          .font({ size: 15 })
          .onSelect((index: number) => {
            this.fTtl = this.fTtlOptions[index];
          })
      }
      .width('100%')

      if (PROXYABLE_TYPES.includes(this.fType)) {
        Row() {
          Column({ space: 2 }) {
            Text('Cloudflare 代理')
              .fontSize(15)
              .fontColor($r('sys.color.font_primary'))
            Text(this.fProxied ? '流量经 Cloudflare 加速与防护' : '仅 DNS 解析')
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
          }
          .alignItems(HorizontalAlign.Start)

          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.fProxied })
            .selectedColor($r('app.color.oc_brand'))
            .onChange((isOn: boolean) => {
              this.fProxied = isOn;
            })
        }
        .width('100%')
      }

      if (this.vm.saveError !== '') {
        Text(this.vm.saveError)
          .fontSize(13)
          .fontColor('#DC2626')
          .width('100%')
      }

      Button(this.editingId === '' ? '添加' : '保存')
        .width('100%')
        .height(46)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.oc_brand_cta'))
        .enabled(!this.vm.isSaving && this.fName.trim() !== '' && this.fContent.trim() !== '')
        .onClick(() => {
          this.submit();
        })

      if (this.vm.isSaving) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color($r('app.color.oc_brand'))
          Text('正在保存…')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
      }
    }
    .padding({ left: 20, right: 20, bottom: 24 })
    .width('100%')
  }

  /// 代理状态徽标（对照 iOS ProxiedBadge：橙 = 已代理，灰 = 仅 DNS）
  @Builder
  proxiedBadge(proxied: boolean) {
    Text(proxied ? '☁ 已代理' : '仅 DNS')
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor(proxied ? BRAND_ORANGE : $r('sys.color.font_tertiary'))
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .backgroundColor(proxied ? BRAND_ORANGE_BG : $r('sys.color.comp_background_tertiary'))
      .borderRadius(20)
  }

  @Builder
  recordRow(record: DNSRecord) {
    Row({ space: 12 }) {
      // 类型徽章（对照 iOS：等宽字体 + 橙暖底）
      Text(record.type)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .fontColor($r('app.color.oc_brand_text'))
        .width(52)
        .padding({ top: 5, bottom: 5 })
        .textAlign(TextAlign.Center)
        .backgroundColor($r('app.color.oc_brand_bg'))
        .borderRadius(6)

      Column({ space: 3 }) {
        Text(record.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(record.content)
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if ((record.comment ?? '') !== '') {
          Text(record.comment)
            .fontSize(11)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Text(ttlLabel(record.ttl))
          .fontSize(10)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.proxiedBadge(record.proxied === true)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(OCLayout.islandPadding)
    .onClick(() => {
      this.openEditor(record);
    })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        OCSkyBackground()
        if (this.vm.isLoading && this.vm.records.length === 0) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color($r('app.color.oc_brand'))
            Text('正在加载 DNS 记录…')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.vm.error !== '') {
          Column({ space: 14 }) {
            Text('加载失败')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
            Text(this.vm.error)
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .textAlign(TextAlign.Center)
              .padding({ left: 32, right: 32 })
            Button('重试')
              .fontSize(14)
              .backgroundColor($r('app.color.oc_brand'))
              .onClick(() => {
                if (this.zoneId !== '') {
                  this.vm.load(this.zoneId).catch(() => {
                  });
                }
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.vm.records.length === 0) {
          Column({ space: 8 }) {
            Text('🗒️')
              .fontSize(40)
            Text('暂无 DNS 记录')
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
            Text('点右下角 + 添加第一条记录')
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Column() {
          // 记录搜索（普通输入框：与下拉刷新共存时不抢手势）
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(15)
              .fontColor([$r('sys.color.font_secondary')])
            TextInput({ text: this.keyword, placeholder: '搜索记录（名称 / 内容 / 类型 / 备注）' })
              .fontSize(13)
              .height(34)
              .backgroundColor(Color.Transparent)
              .layoutWeight(1)
              .onChange((value: string) => {
                this.keyword = value;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })

          Refresh({ refreshing: this.refreshing }) {
            List() {
              ForEach(this.filteredRecords(), (record: DNSRecord) => {
                // 横滑删除交给 UI Design Kit：系统删除图标 + 统一横滑动效。
                // 不开 isFullDelete——删 DNS 记录不可撤销，仍要走二次确认弹窗。
                HdsListItem({
                  customItemBuilder: () => {
                    this.recordCard(record)
                  },
                  // swipeActionOptions 接受 HdsSwipeActionOptions | SwipeActionOptions 联合类型。
                  // HDS 的 deleteIconOptions 只给样式、没有点击回调（删除动作只有全滑的
                  // onFullDeleteAction），而删 DNS 记录不可撤销、必须二次确认，
                  // 所以这里传标准 SwipeActionOptions，保留原有的「删除」按钮 + 确认弹窗。
                  swipeActionOptions: {
                    end: {
                      builder: () => {
                        this.deleteAction(record);
                      },
                    },
                  },
                })
                  .margin({ left: 16, right: 16, top: 5, bottom: 5 })
              }, (record: DNSRecord) => record.id)
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Off)
          }
          .width('100%')
          .height('100%')
          .onRefreshing(() => {
            this.refreshing = true;
            this.vm.load(this.zoneId).then(() => {
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

        // 新建记录 FAB
        Button('+')
          .width(52)
          .height(52)
          .fontSize(26)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.oc_brand_cta'))
          .borderRadius(26)
          .margin({ right: 20, bottom: 28 })
          .onClick(() => {
            this.openEditor(null);
          })
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: this.zoneName !== '' ? `${this.zoneName} · DNS` : 'DNS 记录' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .bindSheet(this.editorVisible, this.editorSheet(), ocSheet(() => {
      this.editorVisible = false;
    }))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as ZoneRouteParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      this.vm.load(param.zoneId).catch(() => {
      });
    })
  }
}
