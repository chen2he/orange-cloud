// 「这个请求为什么被拦了」——模拟一条请求打过 Cloudflare，看它逐步走了哪些规则。
import {
  FlatTraceStep, flattenTrace, RequestTracerService, stepTitle, TraceResult,
} from '../../services/RequestTracerService';
import { accountStore } from '../../core/store/AccountStore';
import { OCSkyBackground } from '../common/OCSky';
import { SectionHeader } from '../common/Components';
import { promptAction } from '@kit.ArkUI';

const METHODS: string[] = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD'];
const BRAND_ORANGE: string = '#E8730F';

@ObservedV2
class TracerVM {
  @Trace url: string = '';
  @Trace method: string = 'GET';
  @Trace steps: FlatTraceStep[] = [];
  @Trace statusCode: number = 0;
  @Trace hasResult: boolean = false;
  @Trace isTracing: boolean = false;
  private service: RequestTracerService = new RequestTracerService();

  /// 只做最基本的形态校验，具体是否可达交给接口判断
  canTrace(): boolean {
    return this.url.trim() !== '' && this.url.includes('://') && !this.isTracing;
  }

  async run(): Promise<string> {
    if (!this.canTrace()) {
      return '';
    }
    this.isTracing = true;
    try {
      const result: TraceResult =
        await this.service.trace(accountStore.selectedId, this.method, this.url.trim());
      this.statusCode = result.status_code ?? 0;
      this.steps = flattenTrace(result.trace ?? []);
      this.hasResult = true;
      return '';
    } catch (e) {
      this.steps = [];
      this.hasResult = false;
      return (e as Error).message ?? '追踪失败';
    } finally {
      this.isTracing = false;
    }
  }
}

@ComponentV2
export struct RequestTracerPage {
  @Local vm: TracerVM = new TracerVM();

  private toast(msg: string): void {
    if (msg !== '') {
      promptAction.showToast({ message: msg });
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        Scroll() {
          Column({ space: 4 }) {
            Column() {
              SectionHeader({ title: '模拟请求' })
              Column({ space: 10 }) {
                Row({ space: 6 }) {
                  ForEach(METHODS, (m: string) => {
                    Text(m)
                      .fontSize(12)
                      .fontColor(this.vm.method === m ? $r('app.color.oc_brand_text') : $r('sys.color.font_secondary'))
                      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                      .backgroundColor(this.vm.method === m ? $r('app.color.oc_brand_bg') : $r('sys.color.background_secondary'))
                      .borderRadius(12)
                      .onClick(() => {
                        this.vm.method = m;
                      })
                  }, (m: string) => m)
                }
                .width('100%')

                TextInput({ placeholder: 'https://example.com/path', text: this.vm.url })
                  .fontSize(14)
                  .onChange((value: string) => {
                    this.vm.url = value;
                  })

                Button(this.vm.isTracing ? '追踪中…' : '开始追踪')
                  .width('100%')
                  .enabled(this.vm.canTrace())
                  .backgroundColor($r('app.color.oc_brand'))
                  .onClick(() => {
                    this.vm.run().then((err: string) => this.toast(err));
                  })

                // 说清楚这是模拟而非真实流量，否则用户会以为在看线上请求
                Text('模拟一条请求打过 Cloudflare，看它命中了哪些规则。不会真的发到源站，也不影响线上流量。需要管理员角色。')
                  .fontSize(12)
                  .fontColor($r('sys.color.font_secondary'))
                  .width('100%')
              }
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .backgroundColor($r('sys.color.comp_background_list_card'))
              .borderRadius(14)
              .border({ width: 0.5, color: $r('sys.color.comp_divider') })
              .clip(true)
              .margin({ left: 16, right: 16 })
            }
            .width('100%')

            if (this.vm.hasResult) {
              Column() {
                SectionHeader({ title: this.vm.statusCode > 0 ? `求值过程 · HTTP ${this.vm.statusCode}` : '求值过程' })
                if (this.vm.steps.length === 0) {
                  Text('没有可展示的求值步骤。')
                    .fontSize(13)
                    .fontColor($r('sys.color.font_secondary'))
                    .padding({ left: 20, right: 20, bottom: 16 })
                } else {
                  Column({ space: 8 }) {
                    ForEach(this.vm.steps, (flat: FlatTraceStep, index: number) => {
                      Column({ space: 2 }) {
                        Row({ space: 6 }) {
                          // 命中与否用符号 + 颜色双重编码，不只靠颜色
                          Text(flat.step.matched === true ? '●' : '○')
                            .fontSize(12)
                            .fontColor(flat.step.matched === true
                              ? BRAND_ORANGE : $r('sys.color.font_secondary'))
                          Text(stepTitle(flat.step))
                            .fontSize(14)
                            .fontWeight(flat.step.matched === true ? FontWeight.Medium : FontWeight.Normal)
                            .fontColor($r('sys.color.font_primary'))
                            .layoutWeight(1)
                          if ((flat.step.action ?? '') !== '') {
                            Text(flat.step.action)
                              .fontSize(11)
                              .fontColor(flat.step.matched === true
                                ? BRAND_ORANGE : $r('sys.color.font_secondary'))
                          }
                        }
                        .width('100%')

                        if ((flat.step.expression ?? '') !== '') {
                          Text(flat.step.expression)
                            .fontSize(11)
                            .fontColor($r('sys.color.font_secondary'))
                            .width('100%')
                        }
                      }
                      .width('100%')
                      .padding({ left: 14 + flat.depth * 14, right: 14, top: 8, bottom: 8 })
                    }, (flat: FlatTraceStep, index: number) => `${index}`)
                  }
                  .backgroundColor($r('sys.color.comp_background_list_card'))
                  .borderRadius(14)
                  .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                  .clip(true)
                  .margin({ left: 16, right: 16 })
                }
              }
              .width('100%')
            }
          }
          .width('100%')
          .padding({ top: 8, bottom: 24 })
        }
        .width('100%')
        .height('100%')
      }
    }
    .title('请求追踪')
  }
}
