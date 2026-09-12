/**
 * 指南板块（/guides）的清单——按语言分列：
 * 英文一套（/guides/…）、简体中文一套（/zh-Hans/guides/…）。
 * 两套选题各自独立、互不翻译：英文追 orange cloud / O2O 这类英文查询，
 * 中文追「内网穿透」「回源」这类中文查询。因此**不为文章写跨语言 hreflang**，
 * 只有索引页两语并列（同一份栏目，两个语言版本）。
 */
export const GUIDE_LOCALE = "en";
export const GUIDE_LOCALE_ZH = "zh-Hans";
export const GUIDE_LOCALES = [GUIDE_LOCALE, GUIDE_LOCALE_ZH] as const;
export type GuideLocale = (typeof GUIDE_LOCALES)[number];

export function isGuideLocale(locale: string): locale is GuideLocale {
	return (GUIDE_LOCALES as readonly string[]).includes(locale);
}

/** 站内绝对路径：默认语言无前缀（与 next-intl 的 as-needed 一致） */
export function guidePath(locale: GuideLocale, path: string) {
	return locale === GUIDE_LOCALE ? path : `/${locale}${path}`;
}

export type GuideMeta = {
	slug: string;
	/** 页面 H1 */
	h1: string;
	/** <title>（≤60 字符） */
	title: string;
	/** meta description（≤155 字符），首句即答案 */
	description: string;
	/** 索引页上的一句话摘要 */
	blurb: string;
	/** ISO 日期，用于 sitemap lastmod 与文章页「Updated」 */
	updated: string;
	readingTime: string;
};

export const GUIDES: GuideMeta[] = [
	{
		slug: "what-is-the-orange-cloud-in-cloudflare",
		h1: "What Does the Orange Cloud Mean in Cloudflare?",
		title: "Proxied vs DNS Only: Cloudflare Orange vs Grey Cloud",
		description:
			"Proxied (orange cloud) routes HTTP traffic through Cloudflare; DNS only (grey cloud) sends visitors straight to your origin. What each changes, and when.",
		blurb:
			"Proxied vs DNS only, in plain terms: what the orange and grey cloud each change, which record types and ports qualify, and how to read the errors the toggle causes.",
		updated: "2026-08-24",
		readingTime: "8 min read",
	},
	{
		slug: "cloudflare-orange-to-orange",
		h1: "Cloudflare Orange-to-Orange (O2O), Explained",
		title: "Cloudflare Orange-to-Orange (O2O), Explained",
		description:
			"Orange-to-Orange is when a proxied hostname routes through two Cloudflare zones — yours and your SaaS provider's. How requests flow and which zone's settings win.",
		blurb:
			"Two Cloudflare zones, one request: how O2O routing works with Cloudflare for SaaS, which zone each setting applies in, and what breaks.",
		updated: "2026-08-19",
		readingTime: "7 min read",
	},
	{
		slug: "cloudflare-ssl-tls-encryption-modes",
		h1: "Which Cloudflare SSL/TLS Encryption Mode Should You Use?",
		title: "Cloudflare SSL Modes: Flexible vs Full vs Full (strict)",
		description:
			"Use Full (strict) unless your origin has no valid certificate. Flexible leaves the Cloudflare-to-origin hop unencrypted and causes redirect loops.",
		blurb:
			"Off, Flexible, Full, Full (strict): what each does to the second hop, which error each one produces, and why Cloudflare may now pick for you.",
		updated: "2026-08-20",
		readingTime: "8 min read",
	},
	{
		slug: "why-is-cloudflare-not-caching-my-site",
		h1: "What Does cf-cache-status DYNAMIC, BYPASS, or MISS Mean?",
		title: "Cloudflare cf-cache-status: DYNAMIC vs BYPASS vs MISS",
		description:
			"cf-cache-status names the cache decision: DYNAMIC was never eligible, BYPASS was blocked by the origin response, MISS was cacheable but not stored yet.",
		blurb:
			"One header names the decision Cloudflare made. DYNAMIC, BYPASS and a MISS that never becomes a HIT are three different failures with three different fixes.",
		updated: "2026-09-04",
		readingTime: "8 min read",
	},
	{
		slug: "why-is-my-cloudflare-dns-change-not-working",
		h1: "Why Isn\u2019t My Cloudflare DNS Change Working Yet?",
		title: "Cloudflare DNS Change Not Working? Propagation Explained",
		description:
			"Cloudflare publishes zone changes globally within five minutes. The wait is a cache: a record TTL, a negatively cached NXDOMAIN, or a stale delegation.",
		blurb:
			"Nothing propagates \u2014 caches expire. Which of the four layers is holding your old answer, and why lowering the TTL cannot fix a cached NXDOMAIN.",
		updated: "2026-08-21",
		readingTime: "8 min read",
	},
	{
		slug: "cloudflare-purge-cache-not-working",
		h1: "Why Isn\u2019t My Cloudflare Cache Purge Working?",
		title: "Cloudflare Purge Cache Not Working? What to Check",
		description:
			"A purge clears one exact cache key \u2014 nothing else. Custom cache keys, transformed URLs and the copy already in a browser all survive a purge by URL.",
		blurb:
			"Instant Purge really is instant, so a stale file means the purge matched nothing \u2014 or the copy you are looking at was never Cloudflare\u2019s to delete.",
		updated: "2026-08-22",
		readingTime: "7 min read",
	},
	{
		slug: "cloudflare-cname-flattening",
		h1: "What Is CNAME Flattening in Cloudflare?",
		title: "Cloudflare CNAME Flattening: Root Domain CNAMEs Explained",
		description:
			"CNAME flattening means Cloudflare resolves the CNAME itself and returns the target's IP address. It is what lets a root domain point at a hostname.",
		blurb:
			"Why a root domain cannot hold a real CNAME, what Cloudflare returns instead, and the three setups flattening quietly breaks.",
		updated: "2026-08-23",
		readingTime: "8 min read",
	},
	{
		slug: "cloudflare-error-1000-dns-points-to-prohibited-ip",
		h1: "Why Am I Seeing Cloudflare Error 1000: DNS Points to Prohibited IP?",
		title: "Cloudflare Error 1000: DNS Points to Prohibited IP",
		description:
			"Error 1000 means the origin address Cloudflare resolved for your hostname is Cloudflare itself. The five things that cause that loop, and who fixes each.",
		blurb:
			"The proxy refuses to forward a request to itself. Which records, reverse proxies, and request headers trigger it \u2014 and how 1000 differs from 1002, 1003, and 1014.",
		updated: "2026-08-26",
		readingTime: "8 min read",
	},
	{
		slug: "cloudflare-error-522-connection-timed-out",
		h1: "Why Am I Getting Cloudflare Error 522: Connection Timed Out?",
		title: "Cloudflare Error 522: Connection Timed Out, Explained",
		description:
			"Error 522 means Cloudflare could not open a TCP connection to your origin within 19 seconds. The usual cause is a firewall dropping Cloudflare's IPs.",
		blurb:
			"Two deadlines produce the same error code, and a 522 is silence rather than refusal \u2014 which is what separates it from 521, 523 and 524.",
		updated: "2026-08-27",
		readingTime: "8 min read",
	},
	{
		slug: "cloudflare-real-visitor-ip-cf-connecting-ip",
		h1: "Why Do My Server Logs Show Cloudflare\u2019s IP, Not the Visitor\u2019s?",
		title: "Server Logs Show Cloudflare IPs Instead of Visitors",
		description:
			"Because Cloudflare is the client now. The visitor\u2019s address moves into the CF-Connecting-IP request header, and your server has to be told to read it.",
		blurb:
			"Every entry is a Cloudflare address, so the rate limiter, the ban list and the geo rules all quietly stopped meaning anything \u2014 and a firewall that reacts on its own can take the site down.",
		updated: "2026-09-12",
		readingTime: "9 min read",
	},
	{
		slug: "cloudflare-error-521-web-server-is-down",
		h1: "Why Am I Getting Cloudflare Error 521: Web Server Is Down?",
		title: "Cloudflare Error 521: Web Server Is Down, Explained",
		description:
			"Error 521 means your origin refused Cloudflare's connection. Either the web server is not running, or it is not listening on the port your SSL mode needs.",
		blurb:
			"A refusal, not a timeout — which is why it appears instantly. The four causes, and the one that starts the moment you change an encryption mode.",
		updated: "2026-09-01",
		readingTime: "7 min read",
	},
	{
		slug: "cloudflare-error-526-invalid-ssl-certificate",
		h1: "Why Am I Getting Cloudflare Error 526: Invalid SSL Certificate?",
		title: "Cloudflare Error 526: Invalid SSL Certificate, Explained",
		description:
			"Error 526 means Cloudflare could not validate your origin\u2019s certificate while the encryption mode is Full (strict). Both conditions must be true.",
		blurb:
			"Two conditions have to hold at once \u2014 which is why 526 differs from 525, and why a site nobody touched starts failing the day an origin certificate quietly expires.",
		updated: "2026-09-03",
		readingTime: "8 min read",
	},
	{
		slug: "cloudflare-error-524-a-timeout-occurred",
		h1: "Why Am I Getting Cloudflare Error 524: A Timeout Occurred?",
		title: "Cloudflare Error 524: A Timeout Occurred, Explained",
		description:
			"Error 524 means Cloudflare connected to your origin but got no HTTP response in time. The default limit is 125 seconds, not the 100 usually quoted.",
		blurb:
			"The connection succeeded \u2014 that is what makes 524 different from every other 52x code. The two clocks behind it, and what to do when your plan cannot raise either one.",
		updated: "2026-09-05",
		readingTime: "8 min read",
	},
	{
		slug: "cloudflare-error-1020-access-denied",
		h1: "Why Am I Seeing Cloudflare Error 1020: Access Denied?",
		title: "Cloudflare Error 1020: Access Denied, Explained",
		description:
			"Error 1020 means a security rule on that site blocked your request on purpose. It is a decision by the site owner, not an outage, and arrives as HTTP 403.",
		blurb:
			"Someone wrote a rule and you matched it. Which Cloudflare feature emits 1020 rather than 1015 or 1106, and the one log that names the rule that did it.",
		updated: "2026-09-09",
		readingTime: "8 min read",
	},
	{
		slug: "cloudflare-hide-origin-ip",
		h1: "Can Someone Still Find My Origin IP Behind Cloudflare?",
		title: "Hide Your Origin IP Behind Cloudflare: What Works",
		description:
			"Proxying hides your origin address from DNS, but does not make it secret. Anyone who learns it can skip Cloudflare unless your origin refuses them.",
		blurb:
			"The orange cloud hides an address; it does not defend one. The five ways an origin IP gets out, and why only a rule at the origin itself actually closes the door.",
		updated: "2026-09-09",
		readingTime: "9 min read",
	},
	{
		slug: "cloudflare-error-525-ssl-handshake-failed",
		h1: "Why Am I Getting Cloudflare Error 525: SSL Handshake Failed?",
		title: "Cloudflare Error 525: SSL Handshake Failed, Explained",
		description:
			"Error 525 means the TLS handshake between Cloudflare and your origin failed. The origin is reachable \u2014 it just would not negotiate a secure connection.",
		blurb:
			"The handshake has four gates and only three of them emit a 525. Which one you failed decides whether this is a missing certificate, a missing SNI, or a cipher list somebody hardened.",
		updated: "2026-09-13",
		readingTime: "8 min read",
	},
	{
		slug: "cloudflare-block-ai-crawlers",
		h1: "How Do You Block AI Crawlers on Cloudflare?",
		title: "Block AI Crawlers on Cloudflare: Defaults Change Sept 15",
		description:
			"robots.txt only states a preference. Enforcement comes from AI Crawl Control or the AI bot policies, and new-domain defaults change on September 15, 2026.",
		blurb:
			"Stating a preference, enforcing it, and wasting a crawler's time are three different tools. Which one actually stops a crawler, and what changes on September 15.",
		updated: "2026-09-09",
		readingTime: "9 min read",
	},
];

export const GUIDES_ZH: GuideMeta[] = [
	{
		slug: "cloudflare-pingbi-ai-paichong",
		h1: "Cloudflare 怎么屏蔽 AI 爬虫？robots.txt 为什么挡不住？",
		title: "Cloudflare 怎么屏蔽 AI 爬虫：9 月默认值有变",
		description:
			"robots.txt 只是表态，真正能拦住的是 AI Crawl Control 与 AI bot 策略，免费方案就能用，落地是一条 WAF 自定义规则。2026 年 9 月 15 日新域名默认值还要变。",
		blurb:
			"表态、强制执行、消耗，三层手段只有两层真的会拦人。两个入口各管什么、免费方案卡在识别精度而非功能、9 月 15 日混合用途爬虫的含义变化，以及国内站长要多想的三件事。",
		updated: "2026-09-01",
		readingTime: "约 10 分钟",
	},
	{
		slug: "goumai-yuming-jieru-cloudflare",
		h1: "怎么买一个域名，再把它接到 Cloudflare 上？",
		title: "新手怎么买域名并接入 Cloudflare",
		description:
			"域名要先在注册商那里花钱买下来才归你。在面板里添加一个域名只是建了一份配置，不会让它变成你的。两条路线：直接在 Cloudflare 买，或在腾讯云买完再改 NS。",
		blurb:
			"从零讲清域名、解析、服务器是三件事而不是一件。Cloudflare Registrar 与腾讯云两条购买路线的完整步骤、实名认证与备案各自卡在哪、买完接入的三步，以及新手最容易踩的六个坑。",
		updated: "2026-08-28",
		readingTime: "约 11 分钟",
	},
	{
		slug: "cloudflare-dns-jiexi-bu-shengxiao",
		h1: "改了 DNS 解析，为什么一直不生效？",
		title: "Cloudflare 改了 DNS 为什么不生效",
		description:
			"先分清是哪一种「不生效」：域名的 NS 还没指到 Cloudflare，你改的记录压根不参与解析；已经指过来了，剩下的就只是 TTL 和沿途缓存在拖时间。",
		blurb:
			"改动没进解析链路，和进了但被缓存挡着，是两件完全不同的事。三种域名状态各自会返回什么、卡在 Pending 的四个原因、开着小黄云时 dig 为什么看不出变化，以及国内解析器那一层该怎么验。",
		updated: "2026-08-28",
		readingTime: "约 10 分钟",
	},
	{
		slug: "cloudflare-huancun-mingzhonglv",
		h1: "Cloudflare 到底缓存了什么？为什么命中率一直上不去",
		title: "Cloudflare 缓存了什么：命中率为什么上不去",
		description:
			"Cloudflare 默认只按文件扩展名缓存静态资源，HTML 和 JSON 一概不缓存。命中率上不去，先看 cf-cache-status：DYNAMIC 是请求时就没资格，BYPASS 是响应本身不让存。",
		blurb:
			"国内 CDN 那套「买了就是全站加速」的心智，在 Cloudflare 这里不成立。默认缓存哪些扩展名、DYNAMIC 与 BYPASS 差在哪、反复未命中该查什么，以及国内访客散落境外节点为什么让回源次数天然更多。",
		updated: "2026-08-27",
		readingTime: "约 11 分钟",
	},
	{
		slug: "cloudflare-cname-zhanping",
		h1: "Cloudflare 的 CNAME 展平（拉平）到底做了什么？",
		title: "Cloudflare CNAME 展平是什么，能关掉吗",
		description:
			"展平就是 Cloudflare 替你把 CNAME 解析成 IP，返回 A 记录而不是 CNAME。根域名上的 CNAME 所有方案强制展平、关不掉，付费方案那两个开关只管子域名。",
		blurb:
			"顶点上填的是 CNAME，对外返回的却是 A 记录。展平的触发条件、两种代理状态下截然不同的 TTL 规则、四种会被咬到的场景，以及它为什么会让国内 CDN 的调度整个失效。",
		updated: "2026-08-26",
		readingTime: "约 10 分钟",
	},
	{
		slug: "cloudflare-mianfeiban-shipin-tucang",
		h1: "Cloudflare 免费版能拿来放视频、当图床吗？",
		title: "Cloudflare 免费版能放视频、当图床吗",
		description:
			"图片一般没问题，视频不行。免费、Pro、Business 方案的 CDN 不得用来分发视频，或让大文件占到失衡的比例，官方给的正路是 Images、Stream 与 R2。",
		blurb:
			"默认缓存的扩展名表里就有 MP4，所以它当然跑得起来——但跑得起来不等于被允许。条款那一节到底写了什么、100 MB 与 512 MB 两道硬上限卡在哪，以及大文件真正该去的地方。",
		updated: "2026-08-25",
		readingTime: "约 9 分钟",
	},
	{
		slug: "cloudflare-ssl-jiami-moshi",
		h1: "Cloudflare 的 SSL/TLS 加密模式该选哪一个？",
		title: "Cloudflare 加密模式：灵活、完全、严格怎么选",
		description:
			"加密模式管的只是 Cloudflare 到源站这一段：源站有公开受信任的证书就选完全（严格），只有自签证书选完全，两样都没有才退到灵活。",
		blurb:
			"四档模式的真实差别只在验不验证源站证书。灵活为什么会让回源那一段裸奔、525 与 526 各自卡在哪一步，以及源站只有自签证书时不必退回灵活的那条路。",
		updated: "2026-08-24",
		readingTime: "约 9 分钟",
	},
	{
		slug: "cloudflare-xiaohuangyun",
		h1: "Cloudflare 的小黄云到底是什么？什么时候该关掉？",
		title: "Cloudflare 小黄云是什么：开还是关",
		description:
			"小黄云是 DNS 记录上的代理开关。开着，域名解析到 Cloudflare 的任播 IP，流量先过 Cloudflare 再回源站；关掉（灰云）就直接解析到源站真实 IP。",
		blurb:
			"橙云、橙色云朵、代理开关说的都是它。能开的只有 A / AAAA / CNAME 三种记录，端口也只覆盖固定那几个——先看清边界，再决定每条记录的开关。",
		updated: "2026-08-24",
		readingTime: "约 9 分钟",
	},
	{
		slug: "cloudflare-huoqu-zhenshi-ip",
		h1: "开了 Cloudflare 之后，怎么在源站拿到访客真实 IP？",
		title: "Cloudflare 下怎么拿到访客真实 IP",
		description:
			"访客真实 IP 在 CF-Connecting-IP 请求头里，让 Web 服务器读这个头即可。但必须先限定只信任来自 Cloudflare IP 段的连接，否则任何人都能伪造它。",
		blurb:
			"日志里全是 Cloudflare 的 IP 不是配错了。真实地址在哪个头、Nginx 与 Apache 怎么配，以及为什么不划信任边界等于把封禁和风控拱手让人。",
		updated: "2026-08-23",
		readingTime: "约 10 分钟",
	},
	{
		slug: "cloudflare-yuanzhan-ip-xielou",
		h1: "套了 Cloudflare，源站真实 IP 还会泄露吗？",
		title: "Cloudflare 下源站 IP 怎么泄露的，怎么堵",
		description:
			"会。橙云只挡住 A、AAAA、CNAME 上的 HTTP 流量，灰云子域、MX 的 _dc-mx 应答、SPF 里的 ip4:、历史解析与证书透明度日志都会把源站 IP 交出去。",
		blurb:
			"五条绕开代理的泄露路径、一条能自查的 dig 命令，以及为什么真正的防线不在 DNS 里，而在源站自己身上。",
		updated: "2026-08-22",
		readingTime: "约 10 分钟",
	},
	{
		slug: "cloudflare-522-error",
		h1: "Cloudflare 为什么会报 522 错误？",
		title: "Cloudflare 522 错误：连接超时的成因与排查",
		description:
			"522 的意思是 Cloudflare 在 19 秒内没能和源站建立 TCP 连接。最常见的原因是源站防火墙挡了回源 IP，其次是源站过载、IP 填错，或跨境回源链路丢包。",
		blurb:
			"19 秒、90 秒、125 秒各对应哪种失败，521 与 522 的分界在哪，以及国内源站配境外边缘节点时那种查不出原因的间歇性 522。",
		updated: "2026-08-21",
		readingTime: "约 9 分钟",
	},
	{
		slug: "cloudflare-tunnel-neiwang-chuantou",
		h1: "没有公网 IP，怎么用 Cloudflare Tunnel 做内网穿透？",
		title: "Cloudflare Tunnel 内网穿透：没有公网 IP 也能用",
		description:
			"cloudflared 从内网主动向 Cloudflare 建立出站连接，所以不需要公网 IP，也不用在路由器上开放端口。本文讲清它与 frp 的差别、配置步骤，以及免费方案的真实限制。",
		blurb:
			"出站连接模型、三种隧道形态的取舍、五分钟配置流程，以及 100 MB 上传上限、视频类内容条款、大陆访问绕境外这些必须先知道的边界。",
		updated: "2026-08-21",
		readingTime: "约 9 分钟",
	},
];

export function guideBySlug(slug: string, locale: GuideLocale = GUIDE_LOCALE): GuideMeta {
	const guide = guidesFor(locale).find((g) => g.slug === slug);
	if (!guide) throw new Error(`Unknown guide: ${locale} ${slug}`);
	return guide;
}

export function guidesFor(locale: GuideLocale): GuideMeta[] {
	return locale === GUIDE_LOCALE_ZH ? GUIDES_ZH : GUIDES;
}

export const GUIDES_INDEX = {
	title: "Guides — Orange Cloud",
	h1: "Guides",
	description:
		"Plain-language guides to the Cloudflare settings people actually search for: the orange cloud, proxy status, SSL/TLS encryption modes, and caching.",
};

export const GUIDES_INDEX_ZH = {
	title: "Cloudflare 指南 — Orange Cloud",
	h1: "Cloudflare 指南",
	description:
		"用人话讲清楚 Cloudflare 里那些真正被搜索的问题：内网穿透、代理状态、回源与缓存、SSL/TLS 加密模式。每篇都对着官方文档逐条核过。",
};

export function guidesIndexFor(locale: GuideLocale) {
	return locale === GUIDE_LOCALE_ZH ? GUIDES_INDEX_ZH : GUIDES_INDEX;
}
