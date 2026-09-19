/**
 * 代理只是把源站地址从 DNS 应答里拿掉，并没有在源站前面立一道门。
 * 图要说清的就是这件事：正常路径走 Cloudflare，而知道 IP 的人可以从下方直连进来。
 * 纯 SVG、无 JS；配色全走主题 token，亮/暗两套都成立；竖版布局，窄屏不溢出。
 */
export default function OriginExposurePaths() {
  const rows = [
    {
      y: 20,
      title: "Visitor requests example.com",
      note: "DNS answers with a Cloudflare address",
      accent: false,
    },
    {
      y: 116,
      title: "Cloudflare proxy",
      note: "WAF, caching and DDoS filtering apply here",
      accent: false,
    },
    {
      y: 212,
      title: "Your origin server",
      note: "the only machine that actually holds the site",
      accent: false,
    },
  ];

  return (
    <figure className="my-8">
      <svg
        viewBox="0 0 360 352"
        role="img"
        aria-label="Two routes reach the same origin server. A visitor requesting the hostname is answered with a Cloudflare address and passes through the Cloudflare proxy, where the firewall, caching and DDoS filtering apply. Below, anyone who has learned the origin IP address connects to the origin directly, and no Cloudflare rule is in that path."
        className="mx-auto block h-auto w-full max-w-[440px]"
      >
        <title>The proxied path and the direct path to the same origin</title>

        <defs>
          <marker
            id="oxp-arrow"
            viewBox="0 0 8 8"
            refX="6"
            refY="4"
            markerWidth="6"
            markerHeight="6"
            orient="auto"
          >
            <path d="M0 0 L8 4 L0 8 z" fill="var(--oc-orange)" />
          </marker>
        </defs>

        {rows.map((row) => (
          <g key={row.title}>
            <rect
              x="20"
              y={row.y}
              width="320"
              height="60"
              rx="14"
              fill="var(--glass-bg)"
              stroke="var(--divider)"
            />
            <text
              x="180"
              y={row.y + 26}
              textAnchor="middle"
              fontSize="14.5"
              fontWeight="600"
              fill="var(--t-primary)"
            >
              {row.title}
            </text>
            <text
              x="180"
              y={row.y + 45}
              textAnchor="middle"
              fontSize="11.5"
              fill="var(--t-secondary)"
            >
              {row.note}
            </text>
          </g>
        ))}

        {/* 直连绕过：知道 IP 的人从下面直接进来，路径上没有任何 Cloudflare 规则 */}
        <rect
          x="20"
          y="292"
          width="320"
          height="48"
          rx="14"
          fill="none"
          stroke="var(--oc-orange)"
          strokeOpacity="0.7"
          strokeDasharray="5 5"
        />
        <text
          x="180"
          y="312"
          textAnchor="middle"
          fontSize="13"
          fontWeight="600"
          fill="var(--oc-orange)"
        >
          Anyone who learns the IP connects here
        </text>
        <text
          x="180"
          y="329"
          textAnchor="middle"
          fontSize="11.5"
          fill="var(--t-secondary)"
        >
          no Cloudflare rule is in this path
        </text>

        <g
          stroke="var(--oc-orange)"
          strokeWidth="1.6"
          markerEnd="url(#oxp-arrow)"
          fill="none"
        >
          <path d="M180 80 L180 112" />
          <path d="M180 176 L180 208" />
          <path d="M180 290 L180 276" />
        </g>
      </svg>
      <figcaption className="mt-3 text-center text-[13px] leading-relaxed t-tertiary">
        Proxying removes the address from the answer. It does not remove the
        route.
      </figcaption>
    </figure>
  );
}
