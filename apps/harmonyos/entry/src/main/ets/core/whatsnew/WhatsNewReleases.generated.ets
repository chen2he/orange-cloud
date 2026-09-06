// ⚠️ 自动生成 —— 请勿手改。改 packages/changelog/harmonyos.json 后运行 `pnpm changelog:gen`。
// 文案取 zh-Hans（鸿蒙 App 当前无 i18n），图标由 SF Symbol 名映射到 sys.symbol。
import { WhatsNewRelease } from './WhatsNew';

/// 用函数而非顶层常量：$r() 在函数体内求值，避免模块初始化期取资源。
export function whatsNewReleases(): WhatsNewRelease[] {
  return [
  {
    version: '1.0.0',
    items: [
      {
        symbol: $r('sys.symbol.person_badge_checkmark'),
        title: 'OAuth 一键登录',
        detail: '用 Cloudflare 官方授权登录，无需手动粘贴 API Token；一个 App 可同时登录多个身份与账号，随时切换。',
      },
      {
        symbol: $r('sys.symbol.discover'),
        title: '域名、DNS 与规则中心',
        detail: '域名列表与详情、DNS 记录增删改查、WAF 与速率限制、缓存与 Transform、单条重定向与 Page Rules，都在手机上完成。',
      },
      {
        symbol: $r('sys.symbol.bolt'),
        title: '开发者平台与实时日志',
        detail: 'Workers、Pages、Queues、Durable Objects、Hyperdrive、Workers AI 与 AI Gateway 收在一个 Tab；Worker 实时日志支持搜索、级别筛选与暂停。',
      },
      {
        symbol: $r('sys.symbol.externaldrive'),
        title: 'R2、D1 与 KV 随身管理',
        detail: '浏览 R2 存储桶与对象、跑 D1 SQL 查询并直接改行、读写 KV 键值；大表有截断与分页防线，不怕手机内存吃紧。',
      },
      {
        symbol: $r('sys.symbol.sun_max'),
        title: '随时间走的晨昏界面与桌面卡片',
        detail: '整个 App 的天色随你所在时刻从清晨走到深夜；桌面服务卡片提供「天窗」与「山脊」两张，账号总览一眼可见。',
      },
    ],
  },
  ];
}
