import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import GuideShell, { type RelatedLink } from "@/components/guides/GuideShell";
import Error524Clocks from "@/components/guides/Error524Clocks";
import { guideBySlug, GUIDE_LOCALE } from "@/lib/guides/guides";

const SITE_URL = "https://o-c.do";
const guide = guideBySlug("cloudflare-error-524-a-timeout-occurred");
const PATH = `/guides/${guide.slug}`;

const DOCS_5XX =
  "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/";
const DOCS_524 = `${DOCS_5XX}error-524/`;
const DOCS_522 = `${DOCS_5XX}error-522/`;
const DOCS_520 = `${DOCS_5XX}error-520/`;
const DOCS_LIMITS =
  "https://developers.cloudflare.com/fundamentals/reference/connection-limits/";
const DOCS_CACHE_RULE =
  "https://developers.cloudflare.com/cache/how-to/cache-rules/settings/#proxy-read-timeout-enterprise-only";
const DOCS_ZONE_SETTING =
  "https://developers.cloudflare.com/api/resources/zones/subresources/settings/methods/edit/";
const DOCS_DNS_ONLY =
  "https://developers.cloudflare.com/dns/proxy-status/#dns-only-records";
const DOCS_ORIGIN_ANALYTICS =
  "https://developers.cloudflare.com/speed/origin-analytics/";
const DOCS_1XX =
  "https://developers.cloudflare.com/support/troubleshooting/http-status-codes/1xx-informational/";
const DOCS_IMAGES = "https://developers.cloudflare.com/images/";

/** FAQ 一处定义：可见文本与 FAQPage JSON-LD 同源，保证逐字一致 */
const FAQ: Array<{ q: string; a: string }> = [
  {
    q: "What does Cloudflare error 524 mean?",
    a: "It means Cloudflare opened a connection to your origin server successfully but never received an HTTP response from it in time. The connection was fine; the application behind it was too slow to answer.",
  },
  {
    q: "Is the Cloudflare 524 timeout 100 seconds or 125 seconds?",
    a: "The current documented default for the Proxy Read Timeout is 125 seconds. The 100-second figure is out of date, and it is the single most common inaccuracy in third-party write-ups about this error.",
  },
  {
    q: "How do I fix error 524 on a free Cloudflare plan?",
    a: "You cannot raise the timeout below Enterprise, so the fix is to stop the request from taking that long. Cloudflare suggests polling the status of large HTTP processes instead of waiting on them, and moving jobs that legitimately run past the limit onto a DNS-only subdomain that bypasses the proxy.",
  },
  {
    q: "What is the difference between Cloudflare error 522 and 524?",
    a: "A 522 means Cloudflare could not establish the connection to your origin at all. A 524 means it established one and then waited without getting a response. Roughly, 522 is a network or firewall problem and 524 is an application performance problem.",
  },
  {
    q: "Can a 524 error happen in under 125 seconds?",
    a: "Yes. A second deadline produces the same code: if Cloudflare cannot finish writing the request to your origin within the 30-second Proxy Write Timeout, that is also a 524, and that timeout cannot be adjusted on any plan.",
  },
];

const RELATED: RelatedLink[] = [
  {
    href: "/guides/cloudflare-error-522-connection-timed-out",
    label: "Cloudflare error 522: connection timed out",
    note: "The error one step earlier on the same connection — the one where the origin never picks up at all.",
  },
  {
    href: "/guides/cloudflare-error-521-web-server-is-down",
    label: "Cloudflare error 521: web server is down",
    note: "A refusal rather than a wait, which is why it lands instantly instead of after a two-minute hang.",
  },
  {
    href: "/guides/what-is-the-orange-cloud-in-cloudflare",
    label: "What does the orange cloud mean in Cloudflare?",
    note: "The proxy status that puts these timeouts in the path — and the switch behind the DNS-only workaround below.",
  },
  {
    href: "/guides/why-is-cloudflare-not-caching-my-site",
    label: "cf-cache-status: DYNAMIC vs BYPASS vs MISS",
    note: "Every request that misses cache has to survive the read timeout, so cacheability and 524s are related problems.",
  },
  {
    href: DOCS_524,
    label: "Cloudflare docs: Error 524",
    note: "The reference this guide was checked against, including the escalation details to give a hosting provider.",
    external: true,
  },
  {
    href: "/guides/cloudflare-error-codes",
    label: "Cloudflare error codes: 5xx vs 1xxx",
    note: "The whole map: which range describes which hop, and the four codes that could be either side.",
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

export default async function Error524Guide({
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
        lede="The connection worked. That is the whole point of this error code — and the reason almost everything you can do about it lives on your side, not Cloudflare's."
        updated={guide.updated}
        readingTime={guide.readingTime}
        related={RELATED}
      >
        <div className="glass r-island note p-6 sm:p-7">
          <p>
            <strong>
              Cloudflare error 524 means the connection to your origin server
              succeeded, but your origin did not return an HTTP response before
              the timeout expired.
            </strong>{" "}
            The default limit is 125 seconds, and only Enterprise zones can
            raise it.
          </p>
        </div>

        <p>
          A 524 error is generated at Cloudflare&rsquo;s edge rather than by
          your application, so the page the visitor sees is Cloudflare&rsquo;s,
          not yours. It only appears on a{" "}
          <Link href="/guides/what-is-the-orange-cloud-in-cloudflare">
            proxied record
          </Link>
          , because a DNS-only record has no proxy in the path to run a clock.
          The full name on the error page is{" "}
          <em>error 524: a timeout occurred</em>, and &ldquo;Cloudflare
          524&rdquo;, &ldquo;CF error 524&rdquo; and &ldquo;524 timeout
          error&rdquo; all describe this same single code — one Cloudflare
          defines for itself, since 524 is not a status code in the HTTP
          standard.
        </p>
        <p>
          What separates it from every other 52x code is the part that{" "}
          <em>worked</em>. Cloudflare reached your server, your server accepted
          the connection, and then nothing came back. That narrows the problem
          enormously: firewalls, IP allowlists, DNS records and encryption modes
          are all doing their jobs, or you would be looking at a different
          number. What is slow is the work your application does after it
          receives the request.
        </p>

        <h2 id="two-clocks">Connected, then silent</h2>
        <Error524Clocks />
        <p>
          Cloudflare documents{" "}
          <a href={DOCS_524} target="_blank" rel="noopener noreferrer">
            error 524
          </a>{" "}
          as the origin failing to provide an HTTP response before the Proxy
          Read Timeout. The wording matters: the timer runs on the{" "}
          <em>response</em>, after the request has been acknowledged. The origin
          acknowledges the request, holds the connection open, and then spends
          longer than the limit doing whatever the request asked for — a large
          data query, a report build, an export.
        </p>
        <p>
          There is a second, much less well known way to produce the same code.
          If Cloudflare connects in order to write data to your origin and the
          write does not complete within the 30-second Proxy Write Timeout, that
          is also a 524. For{" "}
          <a href={DOCS_IMAGES} target="_blank" rel="noopener noreferrer">
            Cloudflare Images
          </a>{" "}
          the write budget is 6.5 seconds. Neither of those can be adjusted on
          any plan, which is worth knowing if you are staring at a 524 that
          arrived far too quickly to be the 125-second one — a slow upload
          endpoint is the usual culprit.
        </p>

        <h2 id="125-seconds">125 seconds, not 100</h2>
        <p>
          The number most third-party articles give for this error is 100
          seconds. Cloudflare&rsquo;s current{" "}
          <a href={DOCS_LIMITS} target="_blank" rel="noopener noreferrer">
            connection limits reference
          </a>{" "}
          puts the default Proxy Read Timeout at 125 seconds. If you have been
          sizing your own application timeouts against 100, they are in the
          wrong place. Here is the full set of deadlines on the
          Cloudflare-to-origin hop, and which code each one produces:
        </p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th scope="col">Limit</th>
                <th scope="col">Default</th>
                <th scope="col">Error</th>
                <th scope="col">Adjustable</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <th scope="row">Complete TCP connection</th>
                <td>19 s</td>
                <td>
                  <a href={DOCS_522} target="_blank" rel="noopener noreferrer">
                    522
                  </a>
                </td>
                <td>No</td>
              </tr>
              <tr>
                <th scope="row">TCP ACK timeout</th>
                <td>90 s</td>
                <td>522</td>
                <td>No</td>
              </tr>
              <tr>
                <th scope="row">TCP keep-alive interval</th>
                <td>30 s</td>
                <td>
                  <a href={DOCS_520} target="_blank" rel="noopener noreferrer">
                    520
                  </a>
                </td>
                <td>No</td>
              </tr>
              <tr>
                <th scope="row">Proxy idle timeout</th>
                <td>900 s</td>
                <td>520</td>
                <td>No</td>
              </tr>
              <tr>
                <th scope="row">Proxy read timeout</th>
                <td>125 s</td>
                <td>524</td>
                <td>Enterprise only</td>
              </tr>
              <tr>
                <th scope="row">Proxy write timeout</th>
                <td>30 s</td>
                <td>524</td>
                <td>No</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p>
          Enterprise zones can raise the read timeout as far as 6,000 seconds,
          by two routes. If the content is cacheable, a{" "}
          <a href={DOCS_CACHE_RULE} target="_blank" rel="noopener noreferrer">
            cache rule
          </a>{" "}
          carrying the Proxy Read Timeout setting will do it — Cloudflare notes
          the content has to be cacheable for the rule to trigger, though it
          does not have to actually be cached. Otherwise the zone-wide value can
          be set through the{" "}
          <a href={DOCS_ZONE_SETTING} target="_blank" rel="noopener noreferrer">
            zone settings API
          </a>
          . One quirk to expect if you do: Cloudflare warns that the error may
          fire about a second earlier than the value you configured, an artefact
          of its Pingora proxy, and suggests simply setting the limit one second
          higher than you need.
        </p>

        <h2 id="fixes">What to do when you cannot raise the limit</h2>
        <p>
          On Free, Pro and Business the timeout is fixed, so every real fix is
          about making the request finish sooner or removing it from the proxy
          path. Cloudflare&rsquo;s own suggestions, in the order that tends to
          pay off:
        </p>
        <ol>
          <li>
            <strong>Stop waiting synchronously.</strong> Cloudflare recommends
            implementing status polling for large HTTP processes: return a job
            ID immediately, do the work in the background, and let the client
            poll for completion. This is the only fix that scales, and it also
            removes a request that was going to fail for slow mobile clients
            regardless of Cloudflare.
          </li>
          <li>
            <strong>Move the long jobs off the proxy.</strong> For requests that
            genuinely need more than 125 seconds — nightly exports, bulk reports
            — Cloudflare suggests putting them behind a{" "}
            <a href={DOCS_DNS_ONLY} target="_blank" rel="noopener noreferrer">
              DNS-only subdomain
            </a>
            . Traffic to a grey-clouded hostname never enters the proxy, so no
            read timeout applies. Note the trade-off: that hostname exposes your
            origin address and loses the WAF, caching and analytics that come
            with proxying.
          </li>
          <li>
            <strong>Find out why the origin is slow.</strong> Cloudflare&rsquo;s
            guidance for escalation splits the cause in two: a single
            long-running process, or a server so loaded it cannot answer
            anything in time. Those need opposite fixes, and your origin&rsquo;s
            own response-time logging is what tells them apart.
          </li>
          <li>
            <strong>Keep the connection alive while you work.</strong>{" "}
            Cloudflare&rsquo;s notes on{" "}
            <a href={DOCS_1XX} target="_blank" rel="noopener noreferrer">
              1xx informational responses
            </a>{" "}
            say that sending interim <code>102 Processing</code> responses helps
            prevent a 524 by keeping the connection active during long
            processing. It is a stopgap, not an architecture, but it can buy a
            slow endpoint room while you rewrite it.
          </li>
        </ol>

        <h2 id="diagnose">Catching it before users do</h2>
        <p>
          Cloudflare now points at{" "}
          <a
            href={DOCS_ORIGIN_ANALYTICS}
            target="_blank"
            rel="noopener noreferrer"
          >
            Origin Analytics
          </a>{" "}
          for this: it charts origin response time at the 50th, 95th and 99th
          percentiles against a reference line for your configured timeout. When
          P95 creeps toward the limit, the Top endpoints table names the slow
          paths before they start returning errors.
        </p>
        <p>
          One detail there is easy to misread. The clock in Origin Analytics
          starts when Cloudflare decides a request must go to the origin and
          stops when it receives the response headers, so it includes DNS
          resolution, the TCP and TLS handshakes and the transfer itself. That
          is deliberately the same round trip the read timeout measures — which
          is why these numbers run higher than the server-side timings in
          Grafana or Datadog, and why a service that looks comfortably fast in
          your own dashboards can still be spending 125 seconds from
          Cloudflare&rsquo;s point of view.
        </p>

        <h2 id="not-524">When it looks like a 524 but is not</h2>
        <p>
          Two neighbours get confused with this one. A{" "}
          <Link href="/guides/cloudflare-error-522-connection-timed-out">
            522
          </Link>{" "}
          is the same silence one step earlier — Cloudflare never got a
          connection open, usually because a firewall is dropping its IP ranges.
          A 520 comes from the keep-alive and idle timers rather than the
          response timer, and shows up as an origin connection that died rather
          than one that stalled. If you are timing the failure with a stopwatch:
          roughly 20 seconds is a 522, a minute and a half or more is a 524, and
          a fast failure on an upload path is the write-timeout flavour of 524
          described above.
        </p>
        <p>
          The useful summary is that error code 524 is not really a Cloudflare
          problem to solve. Every other 52x number points at something between
          the visitor and your application; this one points squarely at the
          application itself, which is why the fixes are all yours.
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
