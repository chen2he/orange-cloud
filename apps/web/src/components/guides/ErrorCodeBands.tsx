/**
 * 错误码分带图：访客 → Cloudflare → 源站，两个失败区各归一族错误码。
 * 纯 SVG、无 JS；配色全走主题 token，亮/暗两套都成立；竖版布局，窄屏不溢出。
 */
export default function ErrorCodeBands() {
  return (
    <figure className="my-8">
      <svg
        viewBox="0 0 360 306"
        role="img"
        aria-label="Where each family of Cloudflare error codes comes from: a request travels from the visitor's browser to Cloudflare's network, where 1xxx codes are decided and written into the body of the response, and then on to your origin server, where a failure on that second hop produces a 5xx code in the 520 to 527 range."
        className="mx-auto block h-auto w-full max-w-[440px]"
      >
        <title>Which hop each Cloudflare error code describes</title>

        {/* 1 · 访客 */}
        <rect
          x="30"
          y="18"
          width="300"
          height="54"
          rx="14"
          fill="var(--glass-bg)"
          stroke="var(--divider)"
        />
        <text
          x="180"
          y="42"
          textAnchor="middle"
          fontSize="15"
          fontWeight="600"
          fill="var(--t-primary)"
        >
          Visitor&rsquo;s browser
        </text>
        <text
          x="180"
          y="59"
          textAnchor="middle"
          fontSize="12"
          fill="var(--t-secondary)"
        >
          asks for a page
        </text>

        {/* 2 · Cloudflare：1xxx 在这里被决定 */}
        <rect
          x="30"
          y="116"
          width="300"
          height="64"
          rx="14"
          fill="var(--glass-bg)"
          stroke="var(--oc-orange)"
          strokeOpacity="0.55"
        />
        <text
          x="180"
          y="140"
          textAnchor="middle"
          fontSize="15"
          fontWeight="600"
          fill="var(--t-primary)"
        >
          Cloudflare&rsquo;s network
        </text>
        <text
          x="180"
          y="157"
          textAnchor="middle"
          fontSize="12"
          fill="var(--t-secondary)"
        >
          decides whether to go on at all
        </text>
        <text
          x="180"
          y="172"
          textAnchor="middle"
          fontSize="11"
          fill="var(--oc-orange)"
          letterSpacing="0.4"
        >
          1xxx — written into the response body
        </text>

        {/* 3 · 源站 */}
        <rect
          x="30"
          y="234"
          width="300"
          height="54"
          rx="14"
          fill="var(--glass-bg)"
          stroke="var(--divider)"
        />
        <text
          x="180"
          y="258"
          textAnchor="middle"
          fontSize="15"
          fontWeight="600"
          fill="var(--t-primary)"
        >
          Your origin server
        </text>
        <text
          x="180"
          y="275"
          textAnchor="middle"
          fontSize="12"
          fill="var(--t-secondary)"
        >
          the machine Cloudflare fetches from
        </text>

        <defs>
          <marker
            id="ecb-arrow"
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

        <g
          stroke="var(--oc-orange)"
          strokeWidth="1.6"
          markerEnd="url(#ecb-arrow)"
          fill="none"
        >
          <path d="M180 72 L180 110" />
          <path d="M180 180 L180 228" />
        </g>

        {/* 第二跳的带标：520–527 描述的就是这一段 */}
        <text
          x="192"
          y="209"
          fontSize="11"
          fill="var(--t-tertiary)"
          letterSpacing="0.4"
        >
          5xx — 520 to 527 describe
        </text>
        <text
          x="192"
          y="222"
          fontSize="11"
          fill="var(--t-tertiary)"
          letterSpacing="0.4"
        >
          this hop alone
        </text>
      </svg>
    </figure>
  );
}
