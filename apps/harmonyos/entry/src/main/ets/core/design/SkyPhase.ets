// 「晨昏」天色定义：由时刻 + 外观模式推导（亮=昼，暗=夜）。
// 与 iOS Shared/SkyPhase.swift、Android core/design/SkyPhase.kt 同一相位表，直译保持一致。
// 这是品牌签名层，永不被系统动态取色覆盖。

export enum SkyPhase {
  Dawn, // 清晨（亮）
  Day, // 白天（亮）
  Dusk, // 黄昏（亮）
  Ember, // 入夜，余晖未尽（暗）
  Night, // 深夜（暗）
}

export class SkyPhaseColors {
  /// 天空主体渐变（自上而下）
  static body(phase: SkyPhase): string[] {
    switch (phase) {
      case SkyPhase.Dawn:
        return ['#FFE8D1', '#F5F2ED'];
      case SkyPhase.Day:
        return ['#FCF2E3', '#F2F2F2'];
      case SkyPhase.Dusk:
        return ['#FFDEBF', '#F0EDF2'];
      case SkyPhase.Ember:
        return ['#1F1208', '#0F0E13', '#0A0A0F'];
      case SkyPhase.Night:
        return ['#120D0A', '#0A0A0E'];
      default:
        return ['#FCF2E3', '#F2F2F2'];
    }
  }

  /// 顶部光源（白昼是日光，夜里是城市上空的橙色辉光），带 alpha 前缀的 8 位 hex
  static glow(phase: SkyPhase): string {
    switch (phase) {
      case SkyPhase.Dawn:
        return '#80FFB066';
      case SkyPhase.Day:
        return '#33F48120';
      case SkyPhase.Dusk:
        return '#6BF58542';
      case SkyPhase.Ember:
        return '#4DF48120';
      case SkyPhase.Night:
        return '#26F48120';
      default:
        return '#33F48120';
    }
  }

  static isDark(phase: SkyPhase): boolean {
    return phase === SkyPhase.Ember || phase === SkyPhase.Night;
  }

  /// 由外观模式 + 当前小时推导相位
  static current(isDark: boolean, hour: number): SkyPhase {
    if (isDark) {
      return (hour >= 17 && hour <= 22) ? SkyPhase.Ember : SkyPhase.Night;
    }
    if (hour >= 5 && hour <= 8) {
      return SkyPhase.Dawn;
    }
    if (hour >= 9 && hour <= 15) {
      return SkyPhase.Day;
    }
    if (hour >= 16 && hour <= 23) {
      return SkyPhase.Dusk;
    }
    return SkyPhase.Dawn;
  }
}
