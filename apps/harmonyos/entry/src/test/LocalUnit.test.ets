// 纯逻辑本地单元测试（主机执行，无需真机）：晨昏相位映射 / 单位格式化 / scope 去重排序 /
// 山脊归一化 / 按钟点合并序列 / 山脊卡柱条解析 / 「新功能」版本比较。
// 覆盖跨平台移植中易错的纯算法。
import { describe, it, expect } from '@ohos/hypium';
import { SkyPhase, SkyPhaseColors } from '../main/ets/core/design/SkyPhase';
import { formatBytes, formatCount } from '../main/ets/core/util/Format';
import { Scopes } from '../main/ets/core/auth/Scopes';
import { isNewerVersion } from '../main/ets/core/whatsnew/WhatsNew';

/// 复刻 RidgeChart 的归一化（山脊高度比值），与绘制逻辑同源
function ridgeRatios(data: number[]): number[] {
  let max = 0;
  for (const v of data) {
    if (v > max) {
      max = v;
    }
  }
  if (max <= 0) {
    max = 1;
  }
  return data.map((v: number) => v / max);
}

interface Pt {
  label: string;
  requests: number;
}

/// 复刻 Dashboard 的按钟点合并（各 zone 同 label 请求相加，label 升序）
function mergeByHour(all: Pt[][]): number[] {
  const byHour: Map<string, number> = new Map();
  for (const points of all) {
    for (const p of points) {
      byHour.set(p.label, (byHour.get(p.label) ?? 0) + p.requests);
    }
  }
  const labels = Array.from(byHour.keys()).sort();
  const series: number[] = [];
  for (const l of labels) {
    series.push(byHour.get(l) ?? 0);
  }
  return series;
}

/// 复刻山脊卡柱条解析
function parseBars(series: string): number[] {
  if (series === '') {
    return [];
  }
  const nums = series.split(',').map((p: string) => {
    const n = Number.parseFloat(p);
    return Number.isNaN(n) ? 0 : n;
  });
  let max = 0;
  for (const n of nums) {
    if (n > max) {
      max = n;
    }
  }
  if (max <= 0) {
    max = 1;
  }
  return nums.map((n: number) => Math.max(0.04, n / max));
}

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // —— 晨昏相位映射（与 iOS/Android 同表）——
    it('skyPhase_light', 0, () => {
      expect(SkyPhaseColors.current(false, 6)).assertEqual(SkyPhase.Dawn);
      expect(SkyPhaseColors.current(false, 12)).assertEqual(SkyPhase.Day);
      expect(SkyPhaseColors.current(false, 20)).assertEqual(SkyPhase.Dusk);
    });
    it('skyPhase_dark', 0, () => {
      expect(SkyPhaseColors.current(true, 18)).assertEqual(SkyPhase.Ember);
      expect(SkyPhaseColors.current(true, 23)).assertEqual(SkyPhase.Night);
      expect(SkyPhaseColors.current(true, 3)).assertEqual(SkyPhase.Night);
    });
    it('skyPhase_isDark', 0, () => {
      expect(SkyPhaseColors.isDark(SkyPhase.Ember)).assertTrue();
      expect(SkyPhaseColors.isDark(SkyPhase.Night)).assertTrue();
      expect(SkyPhaseColors.isDark(SkyPhase.Day)).assertFalse();
    });

    // —— 单位格式化（数据单位不本地化，固定拉丁符号）——
    it('formatBytes', 0, () => {
      expect(formatBytes(512)).assertEqual('512 B');
      expect(formatBytes(1024)).assertEqual('1.00 KB');
      expect(formatBytes(1536)).assertEqual('1.50 KB');
      expect(formatBytes(1048576)).assertEqual('1.00 MB');
    });
    it('formatCount', 0, () => {
      expect(formatCount(999)).assertEqual('999');
      expect(formatCount(1500)).assertEqual('1.5K');
      expect(formatCount(1500000)).assertEqual('1.5M');
      expect(formatCount(2000000000)).assertEqual('2.0B');
    });

    // —— scope 去重排序 + offline_access 必带 ——
    it('scopeString_dedupSort', 0, () => {
      expect(Scopes.scopeString(['b', 'a', 'a'])).assertEqual('a b');
    });
    it('scopeString_hasOfflineAccess', 0, () => {
      expect(Scopes.scopeString().indexOf('offline_access') >= 0).assertTrue();
      expect(Scopes.scopeString().indexOf('dns.write') >= 0).assertTrue();
    });

    // —— 山脊归一化：最大值映射到 1，空/全零安全 ——
    it('ridgeRatios', 0, () => {
      const r = ridgeRatios([10, 5, 20, 0]);
      expect(r[2]).assertEqual(1);
      expect(r[1]).assertEqual(0.25);
      expect(ridgeRatios([]).length).assertEqual(0);
      expect(ridgeRatios([0, 0])[0]).assertEqual(0);
    });

    // —— 按钟点合并各 zone 请求（概览山脊数据源）——
    it('mergeByHour', 0, () => {
      const a: Pt[] = [{ label: '01:00', requests: 3 }, { label: '02:00', requests: 5 }];
      const b: Pt[] = [{ label: '01:00', requests: 7 }, { label: '03:00', requests: 2 }];
      const s = mergeByHour([a, b]);
      // label 升序 01/02/03 → [10, 5, 2]
      expect(s.length).assertEqual(3);
      expect(s[0]).assertEqual(10);
      expect(s[1]).assertEqual(5);
      expect(s[2]).assertEqual(2);
    });

    // —— 山脊卡柱条解析：归一化 + 最小可见高度 0.04 ——
    it('parseBars', 0, () => {
      const bars = parseBars('0,50,100');
      expect(bars.length).assertEqual(3);
      expect(bars[0]).assertEqual(0.04);
      expect(bars[2]).assertEqual(1);
      expect(parseBars('').length).assertEqual(0);
    });

    // —— 「新功能」版本比较：按段数值比，不能退化成字典序 ——
    it('whatsNew_isNewerVersion', 0, () => {
      expect(isNewerVersion('1.10.0', '1.9.9')).assertTrue();
      expect(isNewerVersion('1.2.1', '1.2')).assertTrue();
      expect(isNewerVersion('1.0.0', '0')).assertTrue();
      expect(isNewerVersion('1.2', '1.2.0')).assertFalse();
      expect(isNewerVersion('2.0.0', '2.0.0')).assertFalse();
    });
  });
}
