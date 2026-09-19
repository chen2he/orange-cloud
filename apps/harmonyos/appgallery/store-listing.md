# Orange Cloud — AppGallery 上架素材（HarmonyOS）

> 图标：同目录 `icon_216.png` / `icon_512.png` / `icon_1024.png`（AGC 表单按要求的尺寸取用）。
> 截图：`screenshots/720x1280/`（AGC 手机竖屏规范 9:16、720×1280，5 张，按顺序上传：概览 / 域名 / 分析 / DNS / 开发者平台）；`screenshots/1080x1920/` 为同图高清版。2026-09-20 用 Mate 80 真机 + mock 虚构数据（Sunrise Studio / sunrise.dev 等）出图，已去掉状态栏，无任何真实账号信息。
> 可直接粘贴的完整审核备注（含测试账号凭据）：`review-notes.local.md`（本地，不入库）。
> 隐私政策 https://o-c.do/privacy ｜ 使用条款 https://o-c.do/terms

## 应用名称
Orange Cloud

## 简介（一句话，≤80 字）
优雅的 Cloudflare 管理客户端：官方 OAuth 授权登录，域名、DNS、Workers、存储、安全规则，尽在掌上。

## 应用介绍（详细）
Orange Cloud 是一款为 Cloudflare 用户打造的原生鸿蒙管理客户端。无需手动创建和粘贴 API Token——使用 Cloudflare 官方 OAuth 2.0 授权登录，权限自己勾选，最小化授权，安全透明。

【核心功能】
· 域名管理：域名列表与状态一目了然，DNS 记录增删改查、代理开关、按记录类型智能表单
· 流量分析：24 小时 / 7 天 / 30 天请求、带宽、威胁与访客趋势，缓存命中率仪表与全球流量地图
· 安全防护：WAF 自定义规则（可视化表达式构建器）、IP 访问规则、速率限制、Under Attack 一键开启
· 规则中心：重定向、源站、配置、压缩、自定义错误、Transform、缓存规则、Snippets、Page Rules 与 URL 规范化
· 开发者平台：Workers 脚本管理、实时日志、部署历史、密钥与定时触发器；Pages 项目与部署回滚；Queues、Hyperdrive、AI Gateway、Workers AI 试运行
· 存储：R2 对象浏览与上传下载、桶设置（自定义域 / CORS）；D1 SQL 查询控制台与表浏览；KV 键值管理
· 网络：Cloudflare Tunnel、Zero Trust Access 与 Gateway、负载均衡（含源站池与健康监测）、批量重定向
· 更多：邮件路由、SSL/TLS 证书、审计日志、通知告警、Cloudflare 服务状态
· 工具箱：DNS 查询、Whois、IP 归属、HTTP 探测、CF 节点检测、SSL 检查、CIDR 计算器
· 指南：Cloudflare 常见问题排障与科普长文，读过的文章可离线查看
· 桌面卡片：「天窗」与「流量山脊」两款服务卡片

【设计】
原生鸿蒙设计：采用 HarmonyOS Design 系统分层色与 UI Design Kit 组件，深浅色随系统自动切换；标题栏与页签栏使用光感材质，品牌橙只用于强调与选中态，信息密度与可读性优先。

【Pro 会员】
免费版始终可用：单账号登录、域名与 DNS 全功能、24 小时流量分析、工具箱、指南与桌面卡片。
Pro 解锁：多账号切换、存储模块（R2 / D1 / KV）、Workers 实时日志、WAF 自定义规则、Cloudflare Tunnel、7 天与 30 天流量分析。提供「Pro 年度」自动续期订阅与「Pro 终身」一次性买断两种方式，可在华为账号中随时管理或取消订阅。

【隐私】
不注册自有账号、不接入第三方统计或广告 SDK。访问令牌仅加密存储在本机，网络请求仅发往 Cloudflare API 与本应用官网。

本应用为第三方客户端，与 Cloudflare, Inc. 无隶属关系。Cloudflare 是 Cloudflare, Inc. 的商标。

## 更新说明（首版）
Orange Cloud 首次登陆 HarmonyOS：
· Cloudflare 官方 OAuth 授权登录，支持多账号
· 域名 / DNS / 分析 / 安全规则 / Workers / 存储 / 网络 全模块管理
· 原生鸿蒙设计与桌面服务卡片
· Pro 会员：年度订阅或一次性买断

## 分类与分级建议
- 分类：实用工具（或 商务/办公 → 效率）
- 年龄分级：3+（无用户生成内容、无社交、无广告）
- 收费：免费下载，含应用内购买（Pro 年度 ¥128 自动续期订阅 / Pro 终身 ¥298 非消耗型，商品配置见 iap-products.md）

## 提审备注（对齐 iOS App Store 审核备注，凭据同源 apps/ios/fastlane/metadata/review_information/）
感谢审核本应用。

本应用是 Cloudflare（国际云服务商）的非官方第三方客户端，通过 Cloudflare 官方 OAuth 2.0 与官方 API 让用户管理自己账号下的资源，不存在自建账号体系。

【测试账号】
Cloudflare 账号：
- 邮箱：oc.test@hz.do
- 密码：（见本地 apps/ios/fastlane/metadata/review_information/，不入库）

两步验证（TOTP）：
- 密钥：（同上，不入库）
- 如登录时要求两步验证码，请将上述密钥导入任意标准身份验证器（Authenticator）应用生成 6 位动态码。

【测试步骤】
1. 启动应用，首次启动阅读并同意隐私政策；
2. 点击「使用 Cloudflare 登录」，在弹出的授权页选择权限后跳转 cloudflare.com；
3. 使用上述测试账号登录，按需完成两步验证；
4. 在 Cloudflare 授权页点击同意，自动跳回应用；
5. 登录后即可测试全部功能；「设置 → 工具箱」提供 DNS 查询、Whois、HTTP 探测等 7 个工具，「设置 → 指南」可阅读 Cloudflare 排障与科普文章。

【补充说明】
- 本应用为独立第三方客户端，与 Cloudflare, Inc. 无隶属或背书关系；
- 应用仅经 Cloudflare 官方 API 访问已授权用户有权管理的资源；
- 测试无需任何额外注册；用户数据仅本机存储，详见隐私政策 https://o-c.do/privacy ；
- 如需其他信息或另一个测试账号，请通过审核意见联系我们（support@zhe.ltd）。

## AGC 隐私标签（个人信息收集清单申报口径）
- 收集的个人信息：无主动收集。用户 Cloudflare 访问令牌由用户授权后仅存于本机（Asset Store 加密），不上传本应用服务器。
- 网络访问目标：api.cloudflare.com（产品功能）、o-c.do（OAuth 回调中转 / 政策页面 / 指南内容，公开只读、不带任何用户数据）、cloudflarestatus.com（服务状态，免登录）。
- 第三方 SDK：无。
- 权限：仅 INTERNET（网络）；文件选择走系统 Picker 无需存储权限。
