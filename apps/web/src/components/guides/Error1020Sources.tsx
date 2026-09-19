/**
 * 1020 与它的邻居：同样是「被拦」，不同的 Cloudflare 安全功能吐出不同的 1xxx 码。
 * 刻意不画成流水线——各功能的求值顺序未在官方文档中承诺，这里只做「谁发哪个码」的映射。
 * 纯 SVG、无 JS；配色全走主题 token，亮/暗两套都成立；竖版布局，窄屏不溢出。
 */
export default function Error1020Sources() {
  const rows: Array<{ feature: string; code: string; self?: boolean }> = [
    { feature: "WAF custom rule (Block)", code: "1020", self: true },
    { feature: "IP Access Rules (Block)", code: "1006 / 1007 / 1008" },
    { feature: "Zone Lockdown", code: "1106" },
    { feature: "Browser Integrity Check", code: "1010" },
    { feature: "Rate limiting rule", code: "1015" },
  ];

  return (
    <figure className="my-8">
      <svg
        viewBox="0 0 360 336"
        role="img"
        aria-label="A map of which Cloudflare security feature produces which 1xxx error code. A WAF custom rule with the Block action produces error 1020. Blocking IP Access Rules produce 1006, 1007 or 1008. Zone Lockdown produces 1106. Browser Integrity Check produces 1010. A rate limiting rule produces 1015."
        className="mx-auto block h-auto w-full max-w-[440px]"
      >
        <title>Which Cloudflare security feature emits which error code</title>

        <text x="20" y="16" fontSize="12" fill="var(--t-tertiary)">
          What blocked the request
        </text>
        <text
          x="340"
          y="16"
          textAnchor="end"
          fontSize="12"
          fill="var(--t-tertiary)"
        >
          Code shown
        </text>

        {rows.map((row, i) => {
          const y = 30 + i * 60;
          return (
            <g key={row.code}>
              <rect
                x="20"
                y={y}
                width="320"
                height="48"
                rx="13"
                fill="var(--glass-bg)"
                stroke={row.self ? "var(--oc-orange)" : "var(--divider)"}
                strokeOpacity={row.self ? "0.65" : "1"}
              />
              <text
                x="36"
                y={y + 29}
                fontSize="13.5"
                fontWeight={row.self ? "600" : "400"}
                fill="var(--t-primary)"
              >
                {row.feature}
              </text>
              <text
                x="324"
                y={y + 29}
                textAnchor="end"
                fontSize="13.5"
                fontWeight="600"
                fill={row.self ? "var(--oc-orange)" : "var(--t-secondary)"}
              >
                {row.code}
              </text>
            </g>
          );
        })}
      </svg>
      <figcaption className="mt-3 text-center text-[13px] leading-relaxed t-tertiary">
        The number on the error page narrows the search before you open a single
        log.
      </figcaption>
    </figure>
  );
}
