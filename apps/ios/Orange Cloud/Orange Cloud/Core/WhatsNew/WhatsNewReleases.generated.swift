//
//  WhatsNewReleases.generated.swift
//  Orange Cloud
//
//  ⚠️ 自动生成 —— 请勿手改。改 packages/changelog/ios.json 后运行 `pnpm changelog:gen`。
//  字符串走 WhatsNew.xcstrings（table: "WhatsNew"），与 Localizable.xcstrings 解耦。
//

import Foundation

nonisolated enum WhatsNewGenerated {
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(version: "2.1.3", items: [
            WhatsNewItem(
                icon:   "rectangle.landscape.rotate",
                title:  String(localized: "横屏与大屏适配", table: "WhatsNew"),
                detail: String(localized: "App 现在可以横过来用，宽屏上内容会收在舒适的阅读宽度里，不再被拉得很长；顺带修好了域名页偶尔打开是一片空白的问题。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "list.bullet",
                title:  String(localized: "长列表不再漏项", table: "WhatsNew"),
                detail: String(localized: "R2 存储桶超过 100 个，或邮件路由规则、目标地址、Durable Objects、Hyperdrive 超过 20 条时，后面的内容以前看不到，现在会全部列出；刚添加、还没验证的邮件目标地址也会显示出来。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "checkmark.shield",
                title:  String(localized: "更稳，少打扰", table: "WhatsNew"),
                detail: String(localized: "网络被拦截时（比如公共 Wi-Fi 登录页、WAF 挑战页）不再被误退出登录；修复一处偶发的启动闪退；下拉刷新或快速切换时间范围时，不再提示「已取消」或显示错位的数据。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "2.1.2", items: [
            WhatsNewItem(
                icon:   "clock.badge.checkmark",
                title:  String(localized: "日志可以往回翻了", table: "WhatsNew"),
                detail: String(localized: "以前只有「实时日志」，它只播放你盯着看的那几分钟里发生的请求，退出就没了。现在 Worker 详情多了「历史日志」，可以按 30 分钟到 3 天的范围往回查已经发生过的调用，能按级别筛选、按关键词搜索，点开还能看状态码、耗时和 Ray ID。前提是这个 Worker 已经开启了 Observability。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "wrench.and.screwdriver",
                title:  String(localized: "打开大脚本不再卡死", table: "WhatsNew"),
                detail: String(localized: "用打包工具部署的 Worker，源码常常被压缩成很长的一两行，点「更新代码」会把整个界面卡死。编辑器换了实现，正常体量的脚本编辑起来更跟手；超大或压缩过的脚本转为只读，并给出「导入 .js 文件整体替换」这条路——现有的变量、密钥和绑定照旧保留。Snippets 的编辑器一并改善。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "2.1.1", items: [
            WhatsNewItem(
                icon:   "square.and.pencil",
                title:  String(localized: "触发规则可以编辑了", table: "WhatsNew"),
                detail: String(localized: "Snippet 的触发规则以前只能新建、启停和删除，改一个字都得删掉重加。现在点按规则就能改表达式和描述，规则原来的顺序也不会因此变动。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "2.1.0", items: [
            WhatsNewItem(
                icon:   "checkmark.shield",
                title:  String(localized: "随手管理 Turnstile 人机验证", table: "WhatsNew"),
                detail: String(localized: "概览页新增 Turnstile 入口：查看全部组件，新建、改域名与模式，密钥一键轮换（可留 2 小时宽限平滑过渡），sitekey 和 secret 点按即复制。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "terminal",
                title:  String(localized: "R2 数据目录，直接用 SQL 查", table: "WhatsNew"),
                detail: String(localized: "桶设置的数据目录里新增 R2 SQL 查询控制台：点选表名生成查询，结果表格展示。按扫描量计费（每月 10 GB 免费），控制台内有提示。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "key.fill",
                title:  String(localized: "Workers 密钥，一次批量导入", table: "WhatsNew"),
                detail: String(localized: "粘贴一段 JSON 就能批量写入变量或密钥：走 Cloudflare 新的批量接口，单次调用原子生效，不再逐条保存。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "bolt.horizontal",
                title:  String(localized: "缓存规则认识 JA3/JA4 了", table: "WhatsNew"),
                detail: String(localized: "表达式速插芯片补上 JA3/JA4 指纹字段（需 Bot Management 订阅）；带 Vary 多版本缓存的规则自动只读，避免在 App 里误改丢掉配置。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "2.0.0", items: [
            WhatsNewItem(
                icon:   "brain",
                title:  String(localized: "一个开关拦住 AI 爬虫", table: "WhatsNew"),
                detail: String(localized: "域名详情页新增「AI 爬虫」一栏，三档任选：不拦截、只拦广告页、全站拦截。AI 内容相关的两个设置也挪到了同一页，不必再开控制台。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "waveform.path.ecg",
                title:  String(localized: "源站掉线，Cloudflare 直接推给你", table: "WhatsNew"),
                detail: String(localized: "域名详情页新增独立健康检查：查看每个源站的状态与失败原因，左滑暂停、右滑删除。打开「源站异常时通知我」后，由 Cloudflare 在状态变化时直接推送，App 不用开着。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "calendar.badge.clock",
                title:  String(localized: "域名到期日一眼看到", table: "WhatsNew"),
                detail: String(localized: "概览页新增「域名注册商」：在 Cloudflare 注册的域名，到期日、自动续费与转移锁状态都列在一起，快到期的会标出来。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "scope",
                title:  String(localized: "看清一条请求在 Cloudflare 里走过什么", table: "WhatsNew"),
                detail: String(localized: "概览页新增「请求追踪」：填一个网址就能看到这条请求依次命中了哪些规则——重定向、WAF、缓存规则、Worker，每一步是否生效都写清楚，调规则不用再靠猜。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "lock.shield",
                title:  String(localized: "DNSSEC 与 DNS 进阶设置", table: "WhatsNew"),
                detail: String(localized: "域名详情页新增 DNS 设置：一键开关 DNSSEC 并复制要填到注册商那边的 DS 记录，另可调整 CNAME 展平方式与域名服务器类型。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "hammer",
                title:  String(localized: "Worker 构建失败会提醒你", table: "WhatsNew"),
                detail: String(localized: "Worker 详情页新增构建记录：每次构建的状态、耗时与触发来源都能看到。挑几个关心的 Worker 开启监视，构建失败时会收到通知。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "square.grid.2x2",
                title:  String(localized: "更多模块，以及一处处打磨", table: "WhatsNew"),
                detail: String(localized: "新增 R2 数据目录、托管请求头、URL 安全扫描与 Email 抑制列表。审计日志点进任意一条即可查看同一资源的完整变更历史；缓存规则表达式加了常用字段速插（含 Bot 分数与来源 ASN）；Durable Objects 增加内存分位数。并修复隧道详情页不显示活跃连接的问题。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "1.9.3", items: [
            WhatsNewItem(
                icon:   "pause.circle",
                title:  String(localized: "一键暂停 Cloudflare", table: "WhatsNew"),
                detail: String(localized: "域名详情的「操作」里新增「暂停 Cloudflare」开关。暂停后流量不再经过 Cloudflare——WAF、缓存加速与源站 IP 隐藏都会失效，DNS 仍由 Cloudflare 解析；恢复同样一键完成，两者约 5 分钟生效。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "speedometer",
                title:  String(localized: "概览页更跟手", table: "WhatsNew"),
                detail: String(localized: "从概览页打开 Pro 功能的订阅说明时，整页不再跟着重算，弹出与收起都不会顿挫。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "1.9.2", items: [
            WhatsNewItem(
                icon:   "person.crop.circle.badge.checkmark",
                title:  String(localized: "记住你的默认账号", table: "WhatsNew"),
                detail: String(localized: "有多个 Cloudflare 账号时，App 会记住你上次选中的那一个，下次打开直接进入它，不再固定回到列表里的第一个。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "1.9.1", items: [
            WhatsNewItem(
                icon:   "magnifyingglass",
                title:  String(localized: "一处搜遍所有资源", table: "WhatsNew"),
                detail: String(localized: "概览页顶栏的放大镜可一次搜索域名、Worker、R2 存储桶、D1 数据库、KV 命名空间与隧道，点一下直达；任意资源都能星标固定到概览页。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "bell.badge",
                title:  String(localized: "告警中心", table: "WhatsNew"),
                detail: String(localized: "概览页新增告警卡片，汇总需要注意的资源——未启用的域名、状态异常的隧道等，点一下直达。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "text.magnifyingglass",
                title:  String(localized: "实时日志更好用", table: "WhatsNew"),
                detail: String(localized: "Worker 实时日志支持关键词搜索与级别筛选；长按复制整行，轻点展开完整详情并选取片段。「暂停」现在只冻结画面、日志照常接收，恢复后能看到完整记录。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "clock.arrow.circlepath",
                title:  String(localized: "SQL 历史与收藏", table: "WhatsNew"),
                detail: String(localized: "D1 查询自动记录最近 12 条，常用语句可收藏（按数据库分别保存）；查询结果一键导出 CSV，表详情还能查看索引。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "photo.artframe",
                title:  String(localized: "Workers AI 文生图", table: "WhatsNew"),
                detail: String(localized: "模型试运行新增文生图：输入提示词直接出图，可分享保存。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "1.8.7", items: [
            WhatsNewItem(
                icon:   "globe",
                title:  String(localized: "workers.dev 子域直达", table: "WhatsNew"),
                detail: String(localized: "Worker 开启 workers.dev 子域后，直接显示完整访问地址，点一下即可打开。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "cube.fill",
                title:  String(localized: "快速绑定 D1 / KV", table: "WhatsNew"),
                detail: String(localized: "在变量与密钥页直接把现有 D1 数据库或 KV 命名空间绑定到 Worker，也能一键解除。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "shippingbox.fill",
                title:  String(localized: "快速绑定 R2 存储桶", table: "WhatsNew"),
                detail: String(localized: "资源绑定新增 R2：可把现有存储桶直接绑定到 Worker，与 D1 / KV 一样支持一键解除。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "1.8.5", items: [
            WhatsNewItem(
                icon:   "clock.arrow.circlepath",
                title:  String(localized: "Worker 部署历史", table: "WhatsNew"),
                detail: String(localized: "查看每个 Worker 的历次部署记录，并可删除不再需要的旧部署。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "square.and.pencil",
                title:  String(localized: "就地编辑与删除 Worker", table: "WhatsNew"),
                detail: String(localized: "直接载入线上源码修改后重新部署，变量、密钥与绑定自动保留；也可从 .js 文件导入，或删除整个 Worker。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "tablecells",
                title:  String(localized: "删除 D1 数据表", table: "WhatsNew"),
                detail: String(localized: "在查询控制台长按任意表即可删除，需输入表名二次确认。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "1.8.4", items: [
            WhatsNewItem(
                icon:   "shield.lefthalf.filled",
                title:  String(localized: "编辑 WAF 规则", table: "WhatsNew"),
                detail: String(localized: "WAF 自定义防火墙规则现在支持编辑：点按任意规则即可修改动作、表达式、名称与启用状态，无需再删除后重建。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "wrench.and.screwdriver.fill",
                title:  String(localized: "稳定性修复", table: "WhatsNew"),
                detail: String(localized: "进一步收敛 iOS 17 上由缓存数据库引发的偶发闪退：缓存读写全部加上异常兜底并在启动时预热，个别设备上残留的启动崩溃不再发生。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "1.8.2", items: [
            WhatsNewItem(
                icon:   "arrow.triangle.branch",
                title:  String(localized: "规则中心", table: "WhatsNew"),
                detail: String(localized: "域名详情新增「规则」统一入口：单条重定向、源站、配置、压缩与自定义错误五类规则支持查看、启停、新建、编辑与删除；Page Rules 与 URL 正规化支持查看与启停。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "globe",
                title:  String(localized: "Pages 自定义域名", table: "WhatsNew"),
                detail: String(localized: "Pages 项目现可直接管理自定义域名：添加、删除、重新验证并检查解析状态；域名在当前账号时，还能一键添加指向项目的 CNAME 记录。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "arrow.up.arrow.down",
                title:  String(localized: "列表排序", table: "WhatsNew"),
                detail: String(localized: "Workers 与 Pages 列表新增排序：默认（名称）、创建日期、最近更新，选择会被记住。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "person.badge.key.fill",
                title:  String(localized: "登录更稳定", table: "WhatsNew"),
                detail: String(localized: "根治部分用户「自动退出账号」的问题：授权流程补齐长期凭证，登录状态不再随令牌到期而失效；若授权仍失效，概览页会提供「一键重新授权」引导。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "waveform.path.ecg",
                title:  String(localized: "体验者计划", table: "WhatsNew"),
                detail: String(localized: "新增可随时开关的体验者计划：默认关闭，加入后才会匿名上报诊断信息，帮助我们更快定位闪退与登录问题；不收集任何个人身份数据。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "textformat.123",
                title:  String(localized: "数据单位显示", table: "WhatsNew"),
                detail: String(localized: "存储与流量单位在所有语言下统一显示为国际通用符号（KB / MB / GB），不再随语言翻译。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "wrench.and.screwdriver.fill",
                title:  String(localized: "稳定性修复", table: "WhatsNew"),
                detail: String(localized: "根治 iOS 17.0 上概览页、资源列表与域名详情的多处闪退与冻结；同时修复 Tunnel 页面卡死与冷启动请求翻倍的问题。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "speedometer",
                title:  String(localized: "滑动更流畅", table: "WhatsNew"),
                detail: String(localized: "重做玻璃卡片的渲染方式：观感不变，滚动开销大幅下降，列表与概览页滑动明显更顺滑，旧机型尤其受益。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "1.8.0", items: [
            WhatsNewItem(
                icon:   "bell.badge.fill",
                title:  String(localized: "推送中心", table: "WhatsNew"),
                detail: String(localized: "内置推送服务：拿到一个专属端点，用 curl 或脚本就能把消息推到这台设备，支持标题、分组、铃声与端到端加密。无需登录 Cloudflare 即可使用。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "wrench.and.screwdriver.fill",
                title:  String(localized: "免登录开发者工具箱", table: "WhatsNew"),
                detail: String(localized: "无需登录即可使用一组常用网络工具：DNS 查询、SSL 证书检查、HTTP 头、WHOIS、IP 归属、CIDR 计算与 Cloudflare trace。打开 App 在登录页就能直接进入。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "exclamationmark.bubble.fill",
                title:  String(localized: "把 Cloudflare 告警推到手机", table: "WhatsNew"),
                detail: String(localized: "登录后可直接管理 Cloudflare 告警策略：选择想关注的告警类型（DDoS、健康检查、证书到期、Workers 错误率等），一键接到推送中心，事件发生时直推到这台设备。需账号下有 Pro 及以上套餐的域名。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "rectangle.3.group.fill",
                title:  String(localized: "开发者平台更进一步", table: "WhatsNew"),
                detail: String(localized: "Queues 现可暂停/恢复投递、清空消息、调整保留期与延迟；Hyperdrive 可编辑查询缓存与源数据库连接；Durable Objects 可浏览对象实例；Workers AI 能直接在 App 内试运行文本生成模型，缺权限时可一键补授权、无需退出登录。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "1.7.0", items: [
            WhatsNewItem(
                icon:   "rectangle.3.group.fill",
                title:  String(localized: "全新「开发者平台」", table: "WhatsNew"),
                detail: String(localized: "把 Workers、Pages、Queues、Durable Objects、Hyperdrive、Workers AI、AI Gateway 收进一个按「计算 / 数据与消息 / AI」分组的 Tab，对齐 Cloudflare 的产品布局。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "plus.circle.fill",
                title:  String(localized: "创建资源，不止于查看", table: "WhatsNew"),
                detail: String(localized: "直接新建 R2 存储桶、KV 命名空间、Pages 项目、Queues、Hyperdrive 与 AI Gateway，并可删除。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "square.and.arrow.up.fill",
                title:  String(localized: "部署 Pages 与 Workers", table: "WhatsNew"),
                detail: String(localized: "Pages 支持「直接上传」部署（粘贴代码或选取文件 / ZIP）；Workers 可新建并整体更新代码，变量与密钥支持 JSON 批量导入。受 OAuth 限制无法读取源码，更新为整体替换。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "lock.shield.fill",
                title:  String(localized: "Zero Trust 编辑器", table: "WhatsNew"),
                detail: String(localized: "可视化增删改 Access 自托管应用与策略，以及 Gateway 的 DNS / HTTP / 网络策略，内置带选择器调色板的表达式编辑器。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "shield.lefthalf.filled",
                title:  String(localized: "WAF 可视化规则构建器", table: "WhatsNew"),
                detail: String(localized: "新建自定义防护规则时，可在「书写规则」与「表达式编辑器」之间随时切换，更快写出想要的条件。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "checklist",
                title:  String(localized: "授权更省心", table: "WhatsNew"),
                detail: String(localized: "授权页新增「全部只读 / 全部读写 / 仅必选」快捷预设。本版新增 Queues、AI Gateway、Workers AI 等模块，需重新授权才会点亮对应入口。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "1.6.0", items: [
            WhatsNewItem(
                icon:   "folder.badge.gearshape",
                title:  String(localized: "在「文件」App 中打开 R2", table: "WhatsNew"),
                detail: String(localized: "把 R2 存储桶挂进系统「文件」App，像 iCloud 云盘一样浏览、上传、下载、重命名，并用任意 App 直接打开。Pro 功能。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "sparkles",
                title:  String(localized: "设备端 AI 助手", table: "WhatsNew"),
                detail: String(localized: "用一句话生成 DNS 记录，或为流量分析生成一句话要点摘要——全部在设备上离线完成，不出设备。需 iOS 26 及支持 Apple 智能的机型，Pro 功能。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "globe.americas",
                title:  String(localized: "全球流量地图", table: "WhatsNew"),
                detail: String(localized: "在世界地图上按国家/地区查看请求量与威胁分布，一眼看清流量来自哪里。Pro 功能。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "wrench.and.screwdriver",
                title:  String(localized: "体验与稳定性改进", table: "WhatsNew"),
                detail: String(localized: "新增「减少动画」开关让界面更跟手，优化多账号切换的稳定性，并在后台预热数据，切回前台更快看到最新内容。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "1.5.0", items: [
            WhatsNewItem(
                icon:   "bolt.horizontal",
                title:  String(localized: "缓存规则", table: "WhatsNew"),
                detail: String(localized: "按 URL 自定义边缘与浏览器缓存时长、绕过缓存，直接在手机上管理缓存规则。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "arrow.left.arrow.right",
                title:  String(localized: "负载均衡", table: "WhatsNew"),
                detail: String(localized: "查看与管理负载均衡器、源站池和健康监测，掌握流量分发与源站健康。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "doc.richtext",
                title:  String(localized: "Cloudflare Pages", table: "WhatsNew"),
                detail: String(localized: "浏览 Pages 项目与部署，一键重试 / 回滚 / 删除部署，并编辑构建配置。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "envelope",
                title:  String(localized: "Email Routing", table: "WhatsNew"),
                detail: String(localized: "开关域名的邮件路由，增删改转发规则，并管理账号内的已验证目的地址。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "gauge.with.dots.needle.bottom.50percent",
                title:  String(localized: "Rate Limiting", table: "WhatsNew"),
                detail: String(localized: "新建与管理限速规则：按访客 IP 在时间窗内限制请求次数，超限即阻止或质询。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "lock.shield",
                title:  String(localized: "Zero Trust", table: "WhatsNew"),
                detail: String(localized: "查看受 Cloudflare Access 保护的应用，以及 Gateway 的 DNS / HTTP / 网络过滤策略。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "1.4.0", items: [
            WhatsNewItem(
                icon:   "checkmark.seal",
                title:  String(localized: "SSL 证书与加密设置", table: "WhatsNew"),
                detail: String(localized: "查看域名的边缘证书与到期时间，开关 Universal SSL，并调整 SSL/TLS 加密模式。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "arrow.triangle.branch",
                title:  String(localized: "Transform Rules", table: "WhatsNew"),
                detail: String(localized: "查看并编辑 URL 重写、请求头与响应头规则，直接在手机上管理流量改写。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "hand.raised",
                title:  String(localized: "IP 访问规则", table: "WhatsNew"),
                detail: String(localized: "按 IP、网段、ASN 或国家/地区拦截、质询或放行访问，随时增删规则。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "shippingbox",
                title:  String(localized: "R2 存储升级", table: "WhatsNew"),
                detail: String(localized: "以文件夹方式浏览对象，复制或移动文件，查看各存储桶用量，并管理公开访问域名与 CORS。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "link",
                title:  String(localized: "按 URL 精准清缓存", table: "WhatsNew"),
                detail: String(localized: "无需清空整站，指定单个或多个 URL 精准刷新缓存；并新增性能与缓存设置页。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "globe",
                title:  String(localized: "更多语言与稳定性", table: "WhatsNew"),
                detail: String(localized: "新增德语、法语、阿拉伯语与土耳其语；并改进崩溃诊断，帮助更快定位疑难问题。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "1.3.2", items: [
            WhatsNewItem(
                icon:   "sparkles",
                title:  String(localized: "用自然语言写 WAF 规则", table: "WhatsNew"),
                detail: String(localized: "在支持 Apple 智能的设备上，用一句话描述需求即可生成 WAF 自定义规则，也能把现有规则翻译成大白话；全程在设备上离线完成。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "wrench.and.screwdriver",
                title:  String(localized: "修复启动闪退", table: "WhatsNew"),
                detail: String(localized: "修复了 App 在部分 iOS 17 设备上一启动就闪退的问题。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "key.fill",
                title:  String(localized: "登录更稳定", table: "WhatsNew"),
                detail: String(localized: "登录信息改为仅在本机安全保管，修复了偶尔被登出、需要重新登录的问题；登录状态不再通过 iCloud 在设备间同步。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "1.3.0", items: [
            WhatsNewItem(
                icon:   "globe.badge.chevron.right",
                title:  String(localized: "添加域名", table: "WhatsNew"),
                detail: String(localized: "在 App 里把已注册的域名加入账号，并拿到要去注册商处配置的名称服务器。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "network",
                title:  String(localized: "Tunnel 管理", table: "WhatsNew"),
                detail: String(localized: "不再只是查看——新建隧道、获取连接令牌与命令、配置公共主机名路由。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "cylinder.split.1x2",
                title:  String(localized: "D1 数据库管理", table: "WhatsNew"),
                detail: String(localized: "直接新建 D1 数据库，或在原样确认库名后安全删除。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "key",
                title:  String(localized: "变量与密钥", table: "WhatsNew"),
                detail: String(localized: "管理 Worker 的环境变量与密钥，随手增删改。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "clock",
                title:  String(localized: "定时触发器", table: "WhatsNew"),
                detail: String(localized: "查看与增删 Cron 触发器，让 Worker 按计划自动运行。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "globe",
                title:  String(localized: "域名与路由", table: "WhatsNew"),
                detail: String(localized: "管理 workers.dev 子域、自定义域与路由，掌控 Worker 的访问入口。", table: "WhatsNew")
            )
        ]),
        WhatsNewRelease(version: "1.2.1", items: [
            WhatsNewItem(
                icon:   "applewatch",
                title:  String(localized: "Apple Watch App", table: "WhatsNew"),
                detail: String(localized: "把域名状态与流量概览带上手腕，还能添加到表盘复杂功能随时一瞥。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "curlybraces",
                title:  String(localized: "Snippets", table: "WhatsNew"),
                detail: String(localized: "在域名详情查看、编辑、新建 Cloudflare 边缘代码片段，并管理触发规则——轻量版 Workers，Pro 解锁。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "accessibility",
                title:  String(localized: "全面无障碍", table: "WhatsNew"),
                detail: String(localized: "VoiceOver、更大字体、不只靠颜色区分、足够对比度全面达标，配合系统辅助功能更顺手。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "character.bubble",
                title:  String(localized: "更多语言", table: "WhatsNew"),
                detail: String(localized: "新增西班牙语、韩语、葡萄牙语，现已支持九种语言。", table: "WhatsNew")
            ),
            WhatsNewItem(
                icon:   "arrow.clockwise",
                title:  String(localized: "刷新更省心", table: "WhatsNew"),
                detail: String(localized: "刷新失败不再弹窗打断，下拉刷新更稳定可靠。", table: "WhatsNew")
            )
        ])
    ]
}
