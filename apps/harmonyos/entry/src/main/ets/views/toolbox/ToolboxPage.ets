import { systemMaterial, OC_TITLE_BAR_INSET } from '../common/Effects';
import { HdsNavDestination } from '@kit.UIDesignKit';
// 免登录工具箱：7 件套集成在一页（工具选择 + 输入 + 结果），对齐 Android ToolboxHub。
// whois / DNS 查询 / GeoIP / HTTP 探测 / CF Trace / SSL 探测 / CIDR 计算。
import { ToolField, ToolboxService } from '../../services/ToolboxService';
import { BRAND_ORANGE, OCEmpty } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';

interface ToolSpec {
  id: string;
  name: string;
  placeholder: string;
  needsType: boolean; // 仅 DNS 查询需要记录类型
}

const TOOLS: ToolSpec[] = [
  { id: 'dns', name: 'DNS 查询', placeholder: 'example.com', needsType: true },
  { id: 'whois', name: 'Whois', placeholder: 'example.com', needsType: false },
  { id: 'geoip', name: 'IP 归属', placeholder: '留空查本机，或输入 IP', needsType: false },
  { id: 'trace', name: 'CF Trace', placeholder: 'cloudflare.com', needsType: false },
  { id: 'http', name: 'HTTP 探测', placeholder: 'https://example.com', needsType: false },
  { id: 'ssl', name: 'SSL 探测', placeholder: 'example.com', needsType: false },
  { id: 'cidr', name: 'CIDR 计算', placeholder: '192.168.1.0/24', needsType: false },
];

const DNS_TYPES: string[] = ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'NS', 'CAA', 'SRV'];

@ComponentV2
export struct ToolboxPage {
  @Local toolIndex: number = 0;
  @Local input: string = '';
  @Local dnsType: string = 'A';
  @Local running: boolean = false;
  @Local error: string = '';
  @Local results: ToolField[] = [];
  private service: ToolboxService = new ToolboxService();

  private tool(): ToolSpec {
    return TOOLS[this.toolIndex];
  }

  private run(): void {
    this.running = true;
    this.error = '';
    this.results = [];
    const id = this.tool().id;
    const value = this.input.trim();
    let promise: Promise<ToolField[]>;
    if (id === 'dns') {
      promise = this.service.dnsLookup(value, this.dnsType);
    } else if (id === 'whois') {
      promise = this.service.whois(value);
    } else if (id === 'geoip') {
      promise = this.service.geoIp(value);
    } else if (id === 'trace') {
      promise = this.service.cfTrace(value);
    } else if (id === 'http') {
      promise = this.service.httpProbe(value);
    } else if (id === 'ssl') {
      promise = this.service.sslInspect(value);
    } else {
      promise = Promise.resolve(this.service.computeCidr(value));
    }
    promise.then((fields: ToolField[]) => {
      this.results = fields;
      this.running = false;
    }).catch((e: Error) => {
      this.error = e.message ?? '查询失败';
      this.running = false;
    });
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        Column({ space: 12 }) {
          // 工具选择（横向滚动 chips）
          Scroll() {
            Row({ space: 8 }) {
              ForEach(TOOLS, (spec: ToolSpec, index: number) => {
                Text(spec.name)
                  .fontSize(13)
                  .fontWeight(this.toolIndex === index ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.toolIndex === index ? $r('app.color.oc_brand_text') : $r('sys.color.font_secondary'))
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .backgroundColor(this.toolIndex === index ? $r('app.color.oc_brand_bg') : $r('sys.color.comp_background_list_card'))
                  .borderRadius(16)
                  .onClick(() => {
                    this.toolIndex = index;
                    this.results = [];
                    this.error = '';
                  })
              }, (spec: ToolSpec) => spec.id)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')

          TextInput({ text: this.input, placeholder: this.tool().placeholder })
            .fontSize(14)
            .width('100%')
            .onChange((value: string) => {
              this.input = value;
            })

          if (this.tool().needsType) {
            Row({ space: 12 }) {
              Text('记录类型')
                .fontSize(14)
                .fontColor($r('sys.color.font_primary'))
              Blank()
              Select(DNS_TYPES.map((t: string): SelectOption => ({ value: t })))
                .selected(DNS_TYPES.indexOf(this.dnsType))
                .value(this.dnsType)
                .font({ size: 14 })
                .onSelect((index: number) => {
                  this.dnsType = DNS_TYPES[index];
                })
            }
            .width('100%')
          }

          Button(this.running ? '查询中…' : '查询')
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.oc_brand_cta'))
            .enabled(!this.running && (this.tool().id === 'geoip' || this.input.trim() !== ''))
            .onClick(() => {
              this.run();
            })

          if (this.error !== '') {
            Text(this.error)
              .fontSize(13)
              .fontColor('#DC2626')
              .width('100%')
          }

          if (this.results.length > 0) {
            Scroll() {
              Column() {
                ForEach(this.results, (field: ToolField, index: number) => {
                  Column({ space: 3 }) {
                    Text(field.label)
                      .fontSize(11)
                      .fontColor($r('sys.color.font_tertiary'))
                      .width('100%')
                    Text(field.value)
                      .fontSize(14)
                      .fontFamily('monospace')
                      .fontColor($r('sys.color.font_primary'))
                      .width('100%')
                      .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                  .border({ width: index === 0 ? 0 : { top: 0.5 }, color: $r('sys.color.comp_divider') })
                }, (field: ToolField, index: number) => `${index}-${field.label}`)
              }
              .width('100%')
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(12)
            }
            .align(Alignment.Top)
            .scrollBar(BarState.Off)
            .layoutWeight(1)
            .width('100%')
          } else if (!this.running && this.error === '') {
            Column() {
              OCEmpty({ symbol: $r('sys.symbol.wrench_and_screwdriver'), title: '免登录网络工具', subtitle: '选择工具、输入目标，点查询' })
            }
            .layoutWeight(1)
          }
        }
        .padding(16)
        .width('100%')
        .height('100%')
      }
      // HDS 标题栏浮在内容上层（供滑动动态模糊），内容要让出标题栏高度
      .padding({ top: OC_TITLE_BAR_INSET })
      .width('100%')
      .height('100%')
    }
    .titleBar({ style: { systemMaterialEffect: systemMaterial() }, content: { title: { mainTitle: '工具箱' } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .backgroundColor($r('sys.color.background_secondary'))
  }
}
