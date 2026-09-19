/**
 * 拦 AI 爬虫的三层：表态（robots.txt）、强制（AI Crawl Control / AI bot 策略）、消耗（AI Labyrinth）。
 * 只有中间一层真的会拒绝请求——图的重点就是把这条说清楚，别让人以为写了 robots.txt 就完事。
 * 纯 SVG、无 JS；配色全走主题 token，亮/暗两套都成立；竖版布局，窄屏不溢出。
 */
export default function AiCrawlerLayers() {
  const layers = [
    {
      y: 20,
      title: "State a preference",
      tool: "Managed robots.txt",
      note: "Voluntary — a crawler may simply ignore it",
      tag: "Advisory",
      accent: false,
    },
    {
      y: 112,
      title: "Enforce it",
      tool: "AI Crawl Control · AI bot policies",
      note: "Refused at the edge, whatever robots.txt says",
      tag: "Binding",
      accent: true,
    },
    {
      y: 204,
      title: "Waste their time",
      tool: "AI Labyrinth",
      note: "Honeypot links for crawlers that ignore it",
      tag: "Deterrent",
      accent: false,
    },
  ];

  return (
    <figure className="my-8">
      <svg
        viewBox="0 0 360 300"
        role="img"
        aria-label="Three layers of AI crawler control on Cloudflare. The first layer, managed robots.txt, states a preference and compliance with it is voluntary. The second layer, AI Crawl Control and the AI bot policies, enforces the preference by refusing the request at the edge, and is the only binding layer. The third layer, AI Labyrinth, wastes the time of crawlers that ignored the first layer using invisible honeypot links."
        className="mx-auto block h-auto w-full max-w-[440px]"
      >
        <title>The three layers of AI crawler control, and which one binds</title>

        {layers.map((layer) => (
          <g key={layer.title}>
            <rect
              x="20"
              y={layer.y}
              width="320"
              height="76"
              rx="14"
              fill="var(--glass-bg)"
              stroke={layer.accent ? "var(--oc-orange)" : "var(--divider)"}
              strokeOpacity={layer.accent ? "0.65" : "1"}
            />
            <text
              x="36"
              y={layer.y + 26}
              fontSize="14.5"
              fontWeight="600"
              fill="var(--t-primary)"
            >
              {layer.title}
            </text>
            <text
              x="324"
              y={layer.y + 26}
              textAnchor="end"
              fontSize="11.5"
              fontWeight="600"
              fill={layer.accent ? "var(--oc-orange)" : "var(--t-tertiary)"}
            >
              {layer.tag}
            </text>
            <text
              x="36"
              y={layer.y + 46}
              fontSize="12"
              fill="var(--t-secondary)"
            >
              {layer.tool}
            </text>
            <text
              x="36"
              y={layer.y + 64}
              fontSize="11"
              fill="var(--t-tertiary)"
            >
              {layer.note}
            </text>
          </g>
        ))}
      </svg>
      <figcaption className="mt-3 text-center text-[13px] leading-relaxed t-tertiary">
        Only the middle layer refuses a request. The other two ask, or annoy.
      </figcaption>
    </figure>
  );
}
