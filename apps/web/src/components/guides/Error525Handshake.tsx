/**
 * Error 525 的位置图：把 Cloudflare → 源站这一跳的 TLS 握手拆成四道闸。
 * 第一道（TCP 能不能连上）失败给的是 521/522，不是 525；
 * 后面三道（端口上说不说 TLS、认不认 SNI 名字、有没有共同的密码套件）
 * 任何一道失败都是 525；四道全过、证书递出来之后才轮到验证，那一步才可能 526。
 * 纯 SVG、无 JS；配色全走主题 token，亮/暗两套都成立；竖版布局，窄屏不溢出。
 */
export default function Error525Handshake() {
	const col = { x: 20, width: 212, rx: 14 };
	const note = { x: 244, fontSize: 11, fill: "var(--t-tertiary)" };

	return (
		<figure className="my-8">
			<svg
				viewBox="0 0 400 510"
				role="img"
				aria-label="Where Cloudflare error 525 happens: the Cloudflare edge opens an HTTPS connection to your origin, then the TLS handshake passes through four gates. If the port will not accept TCP at all, the result is error 521 or 522 rather than 525. If the port opens but the origin does not speak TLS there, if the origin does not accept the SNI hostname Cloudflare sends, or if the two sides share no cipher suite, the handshake fails and Cloudflare returns error 525, SSL handshake failed. Only once all four gates pass does the origin present a certificate, and only then can validation fail with error 526."
				className="mx-auto block h-auto w-full max-w-[440px]"
			>
				<title>The four gates a Cloudflare-to-origin TLS handshake has to pass</title>

				<defs>
					<marker id="e525-arrow" viewBox="0 0 8 8" refX="6" refY="4" markerWidth="6" markerHeight="6" orient="auto">
						<path d="M0 0 L8 4 L0 8 z" fill="var(--oc-orange)" />
					</marker>
				</defs>

				{/* 起点 · Cloudflare 边缘向源站开 HTTPS */}
				<rect {...col} y="12" height="54" fill="var(--glass-bg)" stroke="var(--oc-orange)" strokeOpacity="0.55" />
				<text x="126" y="37" textAnchor="middle" fontSize="15" fontWeight="600" fill="var(--t-primary)">
					Cloudflare edge
				</text>
				<text x="126" y="54" textAnchor="middle" fontSize="12" fill="var(--t-secondary)">
					opens HTTPS to your origin
				</text>

				<path d="M126 70 L126 94" stroke="var(--oc-orange)" strokeWidth="1.6" fill="none" markerEnd="url(#e525-arrow)" />

				{/* 闸 1 · TCP —— 失败不是 525 */}
				<rect {...col} y="100" height="52" fill="var(--glass-bg)" stroke="var(--divider)" />
				<text x="126" y="124" textAnchor="middle" fontSize="13" fontWeight="600" fill="var(--t-primary)">
					1 · Port accepts TCP
				</text>
				<text x="126" y="141" textAnchor="middle" fontSize="11.5" fill="var(--t-secondary)">
					443, or your custom secure port
				</text>
				<text {...note} y="120">
					fails here
				</text>
				<text {...note} y="135">
					→ 521 or 522
				</text>

				<path
					d="M126 156 L126 180"
					stroke="var(--oc-orange)"
					strokeWidth="1.6"
					fill="none"
					markerEnd="url(#e525-arrow)"
				/>

				{/* 闸 2 · 端口上说不说 TLS */}
				<rect {...col} y="186" height="52" fill="var(--glass-bg)" stroke="var(--divider)" />
				<text x="126" y="210" textAnchor="middle" fontSize="13" fontWeight="600" fill="var(--t-primary)">
					2 · TLS spoken there
				</text>
				<text x="126" y="227" textAnchor="middle" fontSize="11.5" fill="var(--t-secondary)">
					a certificate is installed at all
				</text>
				<text {...note} y="206">
					fails here
				</text>
				<text {...note} y="221">
					→ 525
				</text>

				<path
					d="M126 242 L126 266"
					stroke="var(--oc-orange)"
					strokeWidth="1.6"
					fill="none"
					markerEnd="url(#e525-arrow)"
				/>

				{/* 闸 3 · SNI */}
				<rect {...col} y="272" height="52" fill="var(--glass-bg)" stroke="var(--divider)" />
				<text x="126" y="296" textAnchor="middle" fontSize="13" fontWeight="600" fill="var(--t-primary)">
					3 · SNI name accepted
				</text>
				<text x="126" y="313" textAnchor="middle" fontSize="11.5" fill="var(--t-secondary)">
					origin supports SNI, knows the host
				</text>
				<text {...note} y="292">
					fails here
				</text>
				<text {...note} y="307">
					→ 525
				</text>

				<path
					d="M126 328 L126 352"
					stroke="var(--oc-orange)"
					strokeWidth="1.6"
					fill="none"
					markerEnd="url(#e525-arrow)"
				/>

				{/* 闸 4 · 密码套件 */}
				<rect {...col} y="358" height="52" fill="var(--glass-bg)" stroke="var(--divider)" />
				<text x="126" y="382" textAnchor="middle" fontSize="13" fontWeight="600" fill="var(--t-primary)">
					4 · A shared cipher
				</text>
				<text x="126" y="399" textAnchor="middle" fontSize="11.5" fill="var(--t-secondary)">
					one suite both sides will use
				</text>
				<text {...note} y="378">
					fails here
				</text>
				<text {...note} y="393">
					→ 525
				</text>

				<path
					d="M126 414 L126 438"
					stroke="var(--oc-orange)"
					strokeWidth="1.6"
					fill="none"
					markerEnd="url(#e525-arrow)"
				/>

				{/* 终点 · 握手成了，才轮到验证 */}
				<rect
					{...col}
					y="444"
					height="54"
					fill="none"
					stroke="var(--oc-orange)"
					strokeOpacity="0.7"
					strokeDasharray="5 4"
				/>
				<text x="126" y="469" textAnchor="middle" fontSize="14" fontWeight="600" fill="var(--t-primary)">
					Certificate presented
				</text>
				<text x="126" y="486" textAnchor="middle" fontSize="11.5" fill="var(--t-secondary)">
					now it can be validated
				</text>
				<text {...note} y="464">
					rejected here
				</text>
				<text {...note} y="479">
					→ 526
				</text>
			</svg>
			<figcaption className="mt-3 text-center text-[13px] leading-relaxed t-tertiary">
				Three of the four gates produce a 525. The first one produces a different error entirely, which is why a
				525 is proof that your origin is reachable.
			</figcaption>
		</figure>
	);
}
