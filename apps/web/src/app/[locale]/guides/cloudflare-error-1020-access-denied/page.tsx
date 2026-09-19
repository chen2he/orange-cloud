import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import GuideShell, { type RelatedLink } from "@/components/guides/GuideShell";
import Error1020Sources from "@/components/guides/Error1020Sources";
import { guideBySlug, GUIDE_LOCALE } from "@/lib/guides/guides";

const SITE_URL = "https://o-c.do";
const guide = guideBySlug("cloudflare-error-1020-access-denied");
const PATH = `/guides/${guide.slug}`;

const DOCS_1XXX =
  "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-1xxx-errors/";
const DOCS_1020 = `${DOCS_1XXX}error-1020/`;
const DOCS_1006 = `${DOCS_1XXX}error-1006/`;
const DOCS_1010 = `${DOCS_1XXX}error-1010/`;
const DOCS_1012 = `${DOCS_1XXX}error-1012/`;
const DOCS_1015 = `${DOCS_1XXX}error-1015/`;
const DOCS_SECURITY_EVENTS =
  "https://developers.cloudflare.com/waf/analytics/security-events/";
const DOCS_RAY_ID =
  "https://developers.cloudflare.com/fundamentals/reference/cloudflare-ray-id/";
const DOCS_IP_ACCESS =
  "https://developers.cloudflare.com/waf/tools/ip-access-rules/";
const DOCS_CUSTOM_RULES = "https://developers.cloudflare.com/waf/custom-rules/";
const DOCS_ZONE_LOCKDOWN =
  "https://developers.cloudflare.com/waf/tools/zone-lockdown/";
const DOCS_BIC =
  "https://developers.cloudflare.com/waf/tools/browser-integrity-check/";
const DOCS_RATE_LIMITING =
  "https://developers.cloudflare.com/waf/rate-limiting-rules/";
const DOCS_ERROR_PAGE_TYPES =
  "https://developers.cloudflare.com/rules/custom-errors/reference/error-page-types/";
const DOCS_CUSTOM_ERRORS_EXAMPLES =
  "https://developers.cloudflare.com/rules/custom-errors/example-rules/";
const DOCS_SKIP = "https://developers.cloudflare.com/waf/custom-rules/skip/";

/** FAQ 一处定义：可见文本与 FAQPage JSON-LD 同源，保证逐字一致 */
const FAQ: Array<{ q: string; a: string }> = [
  {
    q: "What does Cloudflare error 1020 mean?",
    a: "It means the site you are visiting has a Cloudflare security rule that matched your request and blocked it. The block is deliberate and was configured by the site owner. Nothing is broken on your computer, and the site itself is not down.",
  },
  {
    q: "How do I fix error 1020 as a visitor?",
    a: "You mostly cannot, because only the site owner can change the rule that blocked you. Take a screenshot that includes the Ray ID and the timestamp, send it to the site owner, and they can look up the exact rule in their Security Events log. Turning off a VPN or proxy is the one thing worth trying first.",
  },
  {
    q: "What HTTP status code does a Cloudflare 1020 error return?",
    a: "403. Cloudflare documents the WAF block page as returning a 403 status code, and the 1020 text appears in the HTML body rather than in the status line. That is why an automated client sees a generic 403 and never sees the number 1020 at all.",
  },
  {
    q: "What is the difference between Cloudflare error 1020 and 1015?",
    a: "A 1020 means a security rule matched something about your request, such as its country, IP address, path or user agent. A 1015 means you were rate limited for sending too many requests in a short window. A 1015 usually clears on its own after you wait; a 1020 will not.",
  },
  {
    q: "Why do I get error 1020 on only one website?",
    a: "Because these rules are written per zone by each site owner. There is no global Cloudflare blocklist behind this code, so a rule on one site says nothing about any other site. If you see 1020 across many unrelated sites, suspect your network or VPN exit address rather than the sites.",
  },
];

const RELATED: RelatedLink[] = [
  {
    href: "/guides/what-is-the-orange-cloud-in-cloudflare",
    label: "What does the orange cloud mean in Cloudflare?",
    note: "A 1020 can only happen on a proxied hostname — this is the switch that puts the rules in the path.",
  },
  {
    href: "/guides/cloudflare-block-ai-crawlers",
    label: "How do you block AI crawlers on Cloudflare?",
    note: "The most common reason people write a blocking rule in the first place, and the presets that do it without one.",
  },
  {
    href: "/guides/cloudflare-error-1000-dns-points-to-prohibited-ip",
    label: "Cloudflare error 1000: DNS points to prohibited IP",
    note: "Another 1xxx code, but a configuration fault rather than a deliberate block.",
  },
  {
    href: DOCS_1020,
    label: "Cloudflare docs: Error 1020",
    note: "The reference this guide was checked against, including the Security Events lookup steps.",
    external: true,
  },
  {
    href: "/guides/cloudflare-error-codes",
    label: "Cloudflare error codes: 5xx vs 1xxx",
    note: "Why your monitoring only ever saw a 403, and how the two families of codes differ.",
  },
  {
    href: "/contact",
    label: "Something wrong on this page?",
    note: "Corrections and questions are welcome — we read every message.",
  },
];

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: guide.title,
  description: guide.description,
  alternates: {
    canonical: PATH,
    languages: { en: PATH, "x-default": PATH },
  },
  openGraph: {
    title: guide.title,
    description: guide.description,
    url: PATH,
    siteName: "Orange Cloud",
    type: "article",
    locale: "en_US",
    images: [{ url: "/og/en.jpg", width: 1280, height: 640, alt: guide.h1 }],
  },
  twitter: {
    card: "summary_large_image",
    title: guide.title,
    description: guide.description,
    images: ["/og/en.jpg"],
  },
};

export default async function Error1020Guide({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (locale !== GUIDE_LOCALE) notFound();
  setRequestLocale(locale);

  const jsonLd = [
    {
      "@context": "https://schema.org",
      "@type": "TechArticle",
      headline: guide.h1,
      description: guide.description,
      url: `${SITE_URL}${PATH}`,
      inLanguage: "en",
      datePublished: guide.updated,
      dateModified: guide.updated,
      image: `${SITE_URL}/og/en.jpg`,
      author: { "@type": "Organization", name: "Orange Cloud", url: SITE_URL },
      publisher: {
        "@type": "Organization",
        name: "Orange Cloud",
        url: SITE_URL,
      },
      mainEntityOfPage: { "@type": "WebPage", "@id": `${SITE_URL}${PATH}` },
    },
    {
      "@context": "https://schema.org",
      "@type": "FAQPage",
      mainEntity: FAQ.map((item) => ({
        "@type": "Question",
        name: item.q,
        acceptedAnswer: { "@type": "Answer", text: item.a },
      })),
    },
    {
      "@context": "https://schema.org",
      "@type": "BreadcrumbList",
      itemListElement: [
        {
          "@type": "ListItem",
          position: 1,
          name: "Guides",
          item: `${SITE_URL}/guides`,
        },
        {
          "@type": "ListItem",
          position: 2,
          name: guide.h1,
          item: `${SITE_URL}${PATH}`,
        },
      ],
    },
  ];

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
      <GuideShell
        title={guide.h1}
        lede="Nothing is broken. Somebody wrote a rule, your request matched it, and this page is the rule working exactly as intended — which is why the fix almost never lives on your side."
        updated={guide.updated}
        readingTime={guide.readingTime}
        related={RELATED}
      >
        <div className="glass r-island note p-6 sm:p-7">
          <p>
            <strong>
              Cloudflare error 1020 means a security rule on that website
              matched your request and blocked it on purpose.
            </strong>{" "}
            It is a decision made by the site owner, not an outage, and only
            they can change it.
          </p>
        </div>

        <p>
          The page is served by Cloudflare rather than by the website, which is
          why it looks the same on every site that shows it. The full wording is{" "}
          <em>error 1020: access denied</em>, and &ldquo;Cloudflare 1020&rdquo;,
          &ldquo;error code 1020&rdquo; and &ldquo;CF error 1020&rdquo; are all
          the same thing. It can only appear on a{" "}
          <Link href="/guides/what-is-the-orange-cloud-in-cloudflare">
            proxied hostname
          </Link>
          , because a DNS-only record never passes through the proxy where these
          rules are evaluated.
        </p>
        <p>
          The single most useful thing to know is that 1020 is not a diagnosis
          of you. There is no global Cloudflare blocklist that this code draws
          from. Each site owner writes their own rules for their own zone, so
          the same request that is denied on one site sails through on the next
          one.
        </p>

        <h2 id="which-feature">The number tells you which switch did it</h2>
        <p>
          Cloudflare has several features that can deny a request, and they emit
          different codes. That is more useful than it sounds: before anyone
          opens a log, the number on the screen has already eliminated most of
          the configuration surface.
        </p>
        <Error1020Sources />
        <p>
          Cloudflare&rsquo;s{" "}
          <a href={DOCS_1020} target="_blank" rel="noopener noreferrer">
            reference for this error
          </a>{" "}
          attributes it to Firewall Rules, a feature that is now deprecated and
          whose replacement is{" "}
          <a href={DOCS_CUSTOM_RULES} target="_blank" rel="noopener noreferrer">
            WAF custom rules
          </a>
          . In practice, on a zone configured any time recently, a 1020 means a
          custom rule with the <em>Block</em> action. The neighbours are worth
          knowing so you do not go looking in the wrong screen:
        </p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th scope="col">Code</th>
                <th scope="col">What produced it</th>
                <th scope="col">Clears by waiting?</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <th scope="row">1020</th>
                <td>A WAF custom rule (or legacy firewall rule) set to block</td>
                <td>No</td>
              </tr>
              <tr>
                <th scope="row">
                  <a href={DOCS_1006} target="_blank" rel="noopener noreferrer">
                    1006 / 1007 / 1008
                  </a>
                </th>
                <td>
                  Your IP address was banned, typically by{" "}
                  <a
                    href={DOCS_IP_ACCESS}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    IP Access Rules
                  </a>
                </td>
                <td>No</td>
              </tr>
              <tr>
                <th scope="row">1106</th>
                <td>
                  A{" "}
                  <a
                    href={DOCS_ZONE_LOCKDOWN}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    Zone Lockdown
                  </a>{" "}
                  rule — the URL is restricted to an allowlist you are not on
                </td>
                <td>No</td>
              </tr>
              <tr>
                <th scope="row">
                  <a href={DOCS_1010} target="_blank" rel="noopener noreferrer">
                    1010
                  </a>
                </th>
                <td>
                  <a href={DOCS_BIC} target="_blank" rel="noopener noreferrer">
                    Browser Integrity Check
                  </a>{" "}
                  disliked your browser&rsquo;s signature
                </td>
                <td>No</td>
              </tr>
              <tr>
                <th scope="row">
                  <a href={DOCS_1012} target="_blank" rel="noopener noreferrer">
                    1012
                  </a>
                </th>
                <td>
                  Blocked on the basis of malicious activity seen from your
                  address or network
                </td>
                <td>Sometimes</td>
              </tr>
              <tr>
                <th scope="row">
                  <a href={DOCS_1015} target="_blank" rel="noopener noreferrer">
                    1015
                  </a>
                </th>
                <td>
                  A{" "}
                  <a
                    href={DOCS_RATE_LIMITING}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    rate limiting rule
                  </a>{" "}
                  — too many requests in a window
                </td>
                <td>Usually</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p>
          One detail catches people running scripts rather than browsers.
          Cloudflare&rsquo;s{" "}
          <a
            href={DOCS_ERROR_PAGE_TYPES}
            target="_blank"
            rel="noopener noreferrer"
          >
            error page reference
          </a>{" "}
          records the WAF block page as returning a <strong>403</strong> status
          code, while a rate limiting block returns <strong>429</strong>. The
          1020 itself lives in the HTML body, not the status line — so a client
          that only logs status codes sees a bare 403 and never learns the
          number at all. If you are debugging an API integration that suddenly
          returns 403 from a Cloudflare-fronted host, fetch the response body
          before assuming it is an authentication problem.
        </p>

        <h2 id="as-a-visitor">If you are the one being blocked</h2>
        <p>
          Your options are genuinely limited, and most advice on this subject
          overstates them. Clearing cookies and cache does not help, because the
          rule is evaluated before any of that is read. In rough order of how
          often it works:
        </p>
        <ol>
          <li>
            <strong>Turn off a VPN or proxy and retry.</strong> Commercial VPN
            exit addresses and datacenter ranges are among the most commonly
            blocked things in these rules, and this is the one fix entirely in
            your hands.
          </li>
          <li>
            <strong>Try a different network.</strong> Switching from office
            Wi-Fi to a phone hotspot tells you within seconds whether the rule
            keys on your address or on something about your browser.
          </li>
          <li>
            <strong>Send the owner a screenshot.</strong> Cloudflare&rsquo;s
            guidance to site owners is to search their logs by{" "}
            <a href={DOCS_RAY_ID} target="_blank" rel="noopener noreferrer">
              Ray ID
            </a>{" "}
            or client IP, both printed on the error page. A screenshot with
            those visible turns a vague report into a one-minute lookup.
          </li>
        </ol>
        <p>
          What will not work is contacting Cloudflare. Their documentation is
          explicit that support cannot override a customer&rsquo;s security
          settings, and only the domain owner can raise a technical ticket at
          all.
        </p>

        <h2 id="as-the-owner">If it is your site blocking your users</h2>
        <p>
          There is exactly one place that answers &ldquo;which rule did
          this&rdquo;, and it is the{" "}
          <a
            href={DOCS_SECURITY_EVENTS}
            target="_blank"
            rel="noopener noreferrer"
          >
            Security Events
          </a>{" "}
          log under <strong>Security</strong> &gt; <strong>Analytics</strong>.
          Search it for the Ray ID from the visitor&rsquo;s screenshot, and the
          matching entry names the rule, the action it took and the field that
          matched.
        </p>
        <p>
          One trap here wastes more time than the rest of the process combined:
          Cloudflare timestamps these events in UTC, and their own instructions
          include a note to convert the time on the error page to your local
          timezone before searching. Search the wrong hour and the log looks
          empty, which reads exactly like &ldquo;it was not us&rdquo;.
        </p>
        <p>Once you have found the rule, there are three honest fixes:</p>
        <ul>
          <li>
            <strong>Narrow the rule.</strong> The usual culprit is a rule
            written broadly during an incident — a whole country, ASN or
            datacenter range — that nobody revisited afterwards.
          </li>
          <li>
            <strong>Allow the specific visitor.</strong> Cloudflare&rsquo;s
            documented resolution is to update the rule or allow the address in{" "}
            <a
              href={DOCS_IP_ACCESS}
              target="_blank"
              rel="noopener noreferrer"
            >
              IP Access Rules
            </a>
            . Be aware of what that buys: an allow there bypasses custom rules,
            rate limiting rules and Managed Rules, so it is a wide exemption for
            a narrow problem.
          </li>
          <li>
            <strong>Use a skip rule instead.</strong> For a known good client,
            the{" "}
            <a href={DOCS_SKIP} target="_blank" rel="noopener noreferrer">
              skip action
            </a>{" "}
            in a custom rule lets you exempt a request from specific features
            rather than all of them. Cloudflare notes it does not bypass every
            app security feature, which is precisely why it is the safer choice.
          </li>
        </ul>
        <p>
          If the block is intentional and you simply want it to read better than
          a bare error number, the page is customisable. Cloudflare&rsquo;s{" "}
          <a
            href={DOCS_CUSTOM_ERRORS_EXAMPLES}
            target="_blank"
            rel="noopener noreferrer"
          >
            custom error examples
          </a>{" "}
          include a rule matching{" "}
          <code>cf.response.1xxx_code eq 1020</code> and returning your own
          HTML, which is a much better experience than leaving legitimate
          customers to work out what a four-digit number means.
        </p>

        <h2 id="faq">FAQ</h2>
        {FAQ.map((item) => (
          <div key={item.q}>
            <h3>{item.q}</h3>
            <p>{item.a}</p>
          </div>
        ))}
      </GuideShell>
    </>
  );
}
