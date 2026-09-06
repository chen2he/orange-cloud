// 域名相关共享组件（对照 iOS ZoneAvatar / PlanBadge / StatusDot）。

/// 头像哈希色板（对照 iOS AvatarPalette / Android AvatarPalette）
const AVATAR_PALETTE: string[] = [
  '#E8743B', '#3D86E0', '#1F9D5B', '#9B59C9', '#E0508C',
  '#C99A1E', '#2BAFA6', '#5B6CE0', '#D85C5C', '#4F7C9C',
];

function avatarBase(domain: string): string {
  let sum = 0;
  for (let i = 0; i < domain.length; i++) {
    sum += domain.charCodeAt(i);
  }
  return AVATAR_PALETTE[sum % AVATAR_PALETTE.length];
}

/// 把 hex 颜色按因子调暗（对照 iOS mixed(with:.black, by:0.28) → factor 0.72）
function darken(hex: string, factor: number): string {
  const h = hex.replace('#', '');
  const r = Math.round(Number.parseInt(h.substring(0, 2), 16) * factor);
  const g = Math.round(Number.parseInt(h.substring(2, 4), 16) * factor);
  const b = Math.round(Number.parseInt(h.substring(4, 6), 16) * factor);
  const to2 = (n: number): string => {
    const s = n.toString(16);
    return s.length < 2 ? `0${s}` : s;
  };
  return `#${to2(r)}${to2(g)}${to2(b)}`;
}

function initialOf(domain: string): string {
  const label = domain.replace('www.', '').replace('https://', '');
  return label.length > 0 ? label.substring(0, 1).toUpperCase() : '?';
}

/// 域名字母头像：哈希色相渐变圆 + 白色首字母
@Component
export struct ZoneAvatar {
  @Prop domain: string;
  @Prop dim: number = 36;

  build() {
    Text(initialOf(this.domain))
      .fontSize(this.dim * 0.44)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .textAlign(TextAlign.Center)
      .width(this.dim)
      .height(this.dim)
      .borderRadius(this.dim / 2)
      .linearGradient({
        angle: 135,
        colors: [[avatarBase(this.domain), 0.0], [darken(avatarBase(this.domain), 0.72), 1.0]],
      })
      .shadow({ radius: 1.5, color: '#2E000000', offsetY: 1 })
  }
}

function planTone(planName: string): string {
  const short = (planName.split(' ')[0] ?? planName).toLowerCase();
  if (short === 'pro') {
    return '#3D86E0';
  }
  if (short === 'business') {
    return '#E8730F';
  }
  if (short === 'enterprise') {
    return '#C99A1E';
  }
  return '#8A8580';
}

function planShort(planName: string): string {
  return planName.split(' ')[0] ?? planName;
}

/// 套餐徽章：胶囊，Free 灰 / Pro 蓝 / Business 橙 / Enterprise 金
@Component
export struct PlanBadge {
  @Prop planName: string;

  build() {
    Text(planShort(this.planName))
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor(planTone(this.planName))
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .backgroundColor(`#24${planTone(this.planName).replace('#', '')}`)
      .borderRadius(20)
  }
}

function statusColor(status: string): string {
  if (status === 'active') {
    return '#22C55E';
  }
  if (status === 'pending' || status === 'initializing') {
    return '#F59E0B';
  }
  return '#EF4444';
}

/// 状态点：实心圆 + 同色光晕
@Component
export struct StatusDot {
  @Prop status: string;
  @Prop dim: number = 8;

  build() {
    Stack() {
      Circle({ width: this.dim + 6, height: this.dim + 6 })
        .fill(`#21${statusColor(this.status).replace('#', '')}`)
      Circle({ width: this.dim, height: this.dim })
        .fill(statusColor(this.status))
    }
    .width(this.dim + 6)
    .height(this.dim + 6)
  }
}

export function statusLabel(status: string): string {
  if (status === 'active') {
    return '已启用';
  }
  if (status === 'pending' || status === 'initializing') {
    return '待激活';
  }
  if (status === 'paused') {
    return '已暂停';
  }
  return status;
}
