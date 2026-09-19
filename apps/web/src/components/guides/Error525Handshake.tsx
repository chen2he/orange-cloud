/**
 * Error 525 的位置图：TCP 已经连上了，死在 TLS 握手这一步。
 * 四道关卡（443 端口 / 有无证书 / SNI / 密码套件交集）任一不成立 → 525，
 * 且 Full 与 Full (strict) 两档都会触发——这是它与 526 的关键分界：
 * 526 是证书**收到了但没通过校验**，只在 strict 下发生，放宽到 Full 就没了；
 * 525 放宽到 Full 依然在。
 * 纯 SVG、无 JS；配色全走主题 token，亮/暗两套都成立；竖版布局，窄屏不溢出。
 */
export default function Error525Handshake() {
  const gates: Array<{ y: number; label: string }> = [
    { y: 122, label: "Port 443 accepts the connection" },
    { y: 166, label: "A certificate is presented" },
    { y: 210, label: "SNI is supported" },
    { y: 254, label: "A cipher suite is shared" },
  ];

  return (
    <figure className="my-8">
      <svg
        viewBox="0 0 400 500"
        role="img"
        aria-label="Where Cloudflare error 525 happens. The TCP connection to the origin has already succeeded; the failure is in the TLS handshake that follows. Four conditions must all hold: port 443 accepts the connection, the origin presents a certificate, the origin supports SNI, and the origin shares at least one cipher suite with Cloudflare. If any one of them fails, the handshake never completes and Cloudflare returns error 525 — in both Full and Full (strict) encryption modes. If all four hold, the handshake completes and the certificate reaches Cloudflare: in Full mode it is accepted without checking, and in Full (strict) it is validated, with a failure there producing error 526 instead."
        className="mx-auto block h-auto w-full max-w-[460px]"
      >
        <title>
          Where a Cloudflare 525 error happens during the TLS handshake to your
          origin
        </title>

        <defs>
          <marker
            id="e525-arrow"
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

        {/* 1 · 边缘：TCP 已通，开始 TLS */}
        <rect
          x="30"
          y="12"
          width="330"
          height="54"
          rx="14"
          fill="var(--glass-bg)"
          stroke="var(--oc-orange)"
          strokeOpacity="0.55"
        />
        <text
          x="195"
          y="37"
          textAnchor="middle"
          fontSize="15"
          fontWeight="600"
          fill="var(--t-primary)"
        >
          Cloudflare edge
        </text>
        <text
          x="195"
          y="55"
          textAnchor="middle"
          fontSize="12"
          fill="var(--t-secondary)"
        >
          TCP is already connected — now it starts TLS
        </text>

        <path
          d="M195 68 L195 96"
          stroke="var(--oc-orange)"
          strokeWidth="1.6"
          fill="none"
          markerEnd="url(#e525-arrow)"
        />

        <text
          x="195"
          y="112"
          textAnchor="middle"
          fontSize="11.5"
          fill="var(--t-tertiary)"
        >
          all four must hold
        </text>

        {/* 2 · 四道关卡：任一不成立就是 525 */}
        {gates.map((gate) => (
          <g key={gate.label}>
            <rect
              x="30"
              y={gate.y}
              width="330"
              height="38"
              rx="10"
              fill="var(--glass-bg)"
              stroke="var(--divider)"
            />
            <text
              x="46"
              y={gate.y + 24}
              fontSize="12.5"
              fill="var(--t-primary)"
            >
              {gate.label}
            </text>
            <text
              x="344"
              y={gate.y + 24}
              textAnchor="end"
              fontSize="11"
              fontWeight="600"
              fill="var(--oc-orange)"
            >
              else 525
            </text>
          </g>
        ))}

        <path
          d="M195 292 L195 320"
          stroke="var(--oc-orange)"
          strokeWidth="1.6"
          fill="none"
          markerEnd="url(#e525-arrow)"
        />

        {/* 3 · 握手完成，证书到手 */}
        <rect
          x="30"
          y="326"
          width="330"
          height="54"
          rx="14"
          fill="var(--glass-bg)"
          stroke="var(--divider)"
        />
        <text
          x="195"
          y="351"
          textAnchor="middle"
          fontSize="15"
          fontWeight="600"
          fill="var(--t-primary)"
        >
          Handshake completes
        </text>
        <text
          x="195"
          y="369"
          textAnchor="middle"
          fontSize="12"
          fill="var(--t-secondary)"
        >
          the origin certificate is now in Cloudflare&rsquo;s hands
        </text>

        <path
          d="M195 382 L195 408"
          stroke="var(--oc-orange)"
          strokeWidth="1.6"
          fill="none"
          markerEnd="url(#e525-arrow)"
        />

        {/* 4 · 两档模式在这里分道：strict 才会再验一次，失败是 526 */}
        <rect
          x="30"
          y="414"
          width="158"
          height="72"
          rx="12"
          fill="none"
          stroke="var(--divider)"
          strokeDasharray="5 4"
        />
        <text
          x="109"
          y="440"
          textAnchor="middle"
          fontSize="13"
          fontWeight="600"
          fill="var(--t-primary)"
        >
          Full
        </text>
        <text
          x="109"
          y="458"
          textAnchor="middle"
          fontSize="11"
          fill="var(--t-tertiary)"
        >
          accepted without
        </text>
        <text
          x="109"
          y="473"
          textAnchor="middle"
          fontSize="11"
          fill="var(--t-tertiary)"
        >
          any checking
        </text>

        <rect
          x="202"
          y="414"
          width="158"
          height="72"
          rx="12"
          fill="none"
          stroke="var(--oc-orange)"
          strokeOpacity="0.7"
          strokeDasharray="5 4"
        />
        <text
          x="281"
          y="440"
          textAnchor="middle"
          fontSize="13"
          fontWeight="600"
          fill="var(--t-primary)"
        >
          Full (strict)
        </text>
        <text
          x="281"
          y="458"
          textAnchor="middle"
          fontSize="11"
          fill="var(--t-tertiary)"
        >
          validated — a failure
        </text>
        <text
          x="281"
          y="473"
          textAnchor="middle"
          fontSize="11"
          fill="var(--t-tertiary)"
        >
          here is 526, not 525
        </text>
      </svg>
      <figcaption className="mt-3 text-center text-[13px] leading-relaxed t-tertiary">
        A 525 is the handshake never finishing, which is why both Full and Full
        (strict) produce it. A 526 is a certificate that arrived and was then
        rejected — only strict validates, so only strict can raise it.
      </figcaption>
    </figure>
  );
}
