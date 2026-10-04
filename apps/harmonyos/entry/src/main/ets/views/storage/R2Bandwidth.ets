// R2 带宽卡：「带宽（近 30 天）」上传 / 下载合计 + 口径脚注。
// R2 概览（桶列表顶部，全账号）与桶设置页（单桶）共用。数据集不可用 / 未授权时整卡隐藏。
import { R2Bandwidth, R2BandwidthService } from '../../services/R2BandwidthService';
import { accountStore } from '../../core/store/AccountStore';
import { formatBytes } from '../../core/util/Format';
import { OCLayout, StatIsland } from '../common/Daybreak';

@ComponentV2
export struct R2BandwidthCard {
  /// 空串 = 全账号；否则只统计该桶
  @Param bucketName: string = '';
  /// 桶的数据区域（区域桶在数据集里的桶名带前缀）
  @Param jurisdiction: string = '';
  @Local bandwidth: R2Bandwidth | null = null;
  private service: R2BandwidthService = new R2BandwidthService();
  /// 目标变化后晚到的旧结果一律丢弃
  private generation: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  /// 进页时桶名可能还没从路由参数就位，变化后补拉
  @Monitor('bucketName', 'jurisdiction')
  onTargetChange(): void {
    this.load();
  }

  private load(): void {
    this.generation++;
    const gen = this.generation;
    accountStore.loadIfNeeded().then(() => {
      const accountId = accountStore.selectedId;
      if (accountId === '' || gen !== this.generation) {
        return;
      }
      this.service.last30Days(accountId, this.bucketName, this.jurisdiction).then((b: R2Bandwidth) => {
        if (gen === this.generation) {
          this.bandwidth = b;
        }
      }).catch(() => {
        if (gen === this.generation) {
          this.bandwidth = null;
        }
      });
    }).catch(() => {
    });
  }

  build() {
    Column({ space: 8 }) {
      if (this.bandwidth !== null) {
        Text('带宽（近 30 天）')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 4 })
        Row({ space: 10 }) {
          StatIsland({ label: '上传', value: formatBytes(this.bandwidth!.uploadBytes) })
          StatIsland({ label: '下载', value: formatBytes(this.bandwidth!.downloadBytes) })
        }
        .width('100%')
        Text('不含小于 100 KiB 的传输')
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .padding({ left: 4 })
      }
    }
    .width('100%')
    .padding({ left: OCLayout.pagePadding, right: OCLayout.pagePadding })
  }
}
