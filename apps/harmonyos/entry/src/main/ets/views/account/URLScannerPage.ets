// URL 安全扫描：提交链接，看归属、状态与风险判定。需账号，故不在免登录工具箱里。
import { URLScannerService, URLScanResult } from '../../services/URLScannerService';
import { accountStore } from '../../core/store/AccountStore';
import { SectionHeader } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';
import { promptAction } from '@kit.ArkUI';

const BRAND_ORANGE: string = '#E8730F';

@ObservedV2
class ScannerVM {
  @Trace url: string = '';
  @Trace result: URLScanResult | null = null;
  @Trace isScanning: boolean = false;
  private service: URLScannerService = new URLScannerService();

  /// 轮询上限：2 秒一次、最多 30 次（约 1 分钟）。超时按「还没出结果」处理而非报错。
  private readonly maxPolls: number = 30;

  canScan(): boolean {
    return this.url.trim() !== '' && this.url.includes('.') && !this.isScanning;
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => setTimeout(resolve, ms));
  }

  async scan(): Promise<string> {
    if (!this.canScan()) {
      return '';
    }
    this.isScanning = true;
    this.result = null;
    try {
      // 用户多半只输域名，补上协议再提交
      let target = this.url.trim();
      if (!target.includes('://')) {
        target = `https://${target}`;
      }
      const scanId = await this.service.submit(accountStore.selectedId, target);
      if (scanId === '') {
        return '提交成功但没拿到扫描 ID。';
      }
      for (let i = 0; i < this.maxPolls; i++) {
        await this.sleep(2000);
        try {
          this.result = await this.service.result(accountStore.selectedId, scanId);
          break;
        } catch (e) {
          // 未就绪，继续轮询
        }
      }
      return this.result === null ? '扫描仍在进行，请稍后用同一个链接再查一次。' : '';
    } catch (e) {
      return (e as Error).message ?? '扫描失败';
    } finally {
      this.isScanning = false;
    }
  }
}

@ComponentV2
export struct URLScannerPage {
  @Local vm: ScannerVM = new ScannerVM();

  private toast(msg: string): void {
    if (msg !== '') {
      promptAction.showToast({ message: msg });
    }
  }

  @Builder
  infoRow(label: string, value: string) {
    if (value !== '') {
      Row({ space: 10 }) {
        Text(label)
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
        Text(value)
          .fontSize(13)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: 3, bottom: 3 })
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        Scroll() {
          Column({ space: 4 }) {
            Column() {
              SectionHeader({ title: '扫描链接' })
              Column({ space: 10 }) {
                TextInput({ placeholder: 'example.com', text: this.vm.url })
                  .fontSize(14)
                  .onChange((v: string) => {
                    this.vm.url = v;
                  })
                Button(this.vm.isScanning ? '扫描中…' : '开始扫描')
                  .width('100%')
                  .enabled(this.vm.canScan())
                  .backgroundColor($r('app.color.oc_brand'))
                  .onClick(() => {
                    this.vm.scan().then((err: string) => this.toast(err));
                  })
                // 扫描是异步的，且记录会进 Cloudflare 公共扫描库，得说清楚
                Text('由 Cloudflare 打开该链接并生成安全报告，通常需要几十秒。扫描记录会保存在 Cloudflare 的扫描库中。')
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

            if (this.vm.result !== null) {
              Column() {
                SectionHeader({ title: '判定' })
                Column({ space: 6 }) {
                  Row({ space: 8 }) {
                    Text(this.vm.result?.verdicts?.overall?.malicious === true ? '⚠' : '✓')
                      .fontSize(15)
                      .fontColor(this.vm.result?.verdicts?.overall?.malicious === true ? '#C62828' : '#2E7D32')
                    Text(this.vm.result?.verdicts?.overall?.malicious === true ? '判定为恶意' : '未发现恶意特征')
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('sys.color.font_primary'))
                  }
                  .width('100%')

                  this.infoRow('最终地址', this.vm.result?.page?.url ?? this.vm.result?.task?.effectiveUrl ?? '')
                  this.infoRow('IP', this.vm.result?.page?.ip ?? '')
                  this.infoRow('ASN', `${this.vm.result?.page?.asn ?? ''} ${this.vm.result?.page?.asnname ?? ''}`.trim())
                  this.infoRow('国家/地区', this.vm.result?.page?.country ?? '')
                  this.infoRow('服务器', this.vm.result?.page?.server ?? '')
                  this.infoRow('状态码', this.vm.result?.page?.statusCode !== undefined
                    ? `${this.vm.result?.page?.statusCode}` : '')
                }
                .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                .backgroundColor($r('sys.color.comp_background_list_card'))
                .borderRadius(14)
                .border({ width: 0.5, color: $r('sys.color.comp_divider') })
                .clip(true)
                .margin({ left: 16, right: 16 })
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
    .title('URL 扫描')
  }
}
