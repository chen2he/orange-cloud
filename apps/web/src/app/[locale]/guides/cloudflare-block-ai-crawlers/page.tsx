import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { setRequestLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import GuideShell, { type RelatedLink } from "@/components/guides/GuideShell";
import AiCrawlerLayers from "@/components/guides/AiCrawlerLayers";
import { guideBySlug, GUIDE_LOCALE } from "@/lib/guides/guides";

const SITE_URL = "https://o-c.do";
const guide = guideBySlug("cloudflare-block-ai-crawlers");
const PATH = `/guides/${guide.slug}`;

const DOCS_BLOCK_AI_BOTS =
  "https://developers.cloudflare.com/bots/additional-configurations/block-ai-bots/";
const DOCS_ROBOTS_TXT =
  "https://developers.cloudflare.com/bots/additional-configurations/managed-robots-txt/";
const DOCS_LABYRINTH =
  "https://developers.cloudflare.com/bots/additional-configurations/ai-labyrinth/";
const DOCS_CRAWL_CONTROL = "https://developers.cloudflare.com/ai-crawl-control/";
const DOCS_MANAGE_CRAWLERS =
  "https://developers.cloudflare.com/ai-crawl-control/features/manage-ai-crawlers/";
const DOCS_TRACK_ROBOTS =
  "https://developers.cloudflare.com/ai-crawl-control/features/track-robots-txt/";
const DOCS_PAY_PER_CRAWL =
  "https://developers.cloudflare.com/ai-crawl-control/features/pay-per-crawl/what-is-pay-per-crawl/";
const DOCS_VERIFIED_BOTS =
  "https://developers.cloudflare.com/bots/concepts/bot/verified-bots/";
const DOCS_SAMPLE_TERMS =
  "https://developers.cloudflare.com/bots/reference/sample-terms/";
const DOCS_CUSTOM_RULES = "https://developers.cloudflare.com/waf/custom-rules/";

/** FAQ 一处定义：可见文本与 FAQPage JSON-LD 同源，保证逐字一致 */
const FAQ: Array<{ q: string; a: string }> = [
  {
    q: "How do I block AI crawlers on Cloudflare?",
    a: "Use AI Crawl Control or the AI bot policies in Security Settings, both available on every plan including Free. Setting a crawler to Block refuses its requests at the edge. Managed robots.txt is a separate setting that only states a preference, so on its own it stops nothing.",
  },
  {
    q: "Does robots.txt actually stop AI crawlers?",
    a: "No. Cloudflare states plainly that robots.txt compliance is voluntary: the file expresses your preferences but does not prevent crawlers from accessing your content at a technical level, and some operators disregard it. Use it to declare intent, and use AI Crawl Control to enforce that intent.",
  },
  {
    q: "What changes for AI bots on September 15, 2026?",
    a: "Cloudflare is setting updated defaults for new domains: bots classified as Training or Agent will be blocked on pages that display ads, while Search stays allowed. Mixed-purpose crawlers that do both Search and Training will be blocked by every configuration that blocks AI training, including the legacy Block AI bots option, which is being deprecated on the same date.",
  },
  {
    q: "Can I block AI training but still allow AI search?",
    a: "Yes, and that is the point of the three presets. Search, Agent and Training are configured separately, so you can leave Search allowed to keep earning citations and referrals while blocking Training. Note that a crawler doing both Search and Training counts as mixed-purpose and will be blocked by the training setting.",
  },
  {
    q: "Does blocking AI bots hurt my SEO?",
    a: "Blocking Training and Agent does not affect a conventional search crawler, because those are separate categories from Search. AI Labyrinth is also safe in this respect: Cloudflare states its invisible links do not impact your SEO or your site's appearance and are only seen by bots.",
  },
];

const RELATED: RelatedLink[] = [
  {
    href: "/guides/cloudflare-error-1020-access-denied",
    label: "Cloudflare error 1020: access denied",
    note: "What a visitor sees when a rule you wrote blocks them — including a rule aimed at crawlers that catches a person.",
  },
  {
    href: "/guides/why-is-cloudflare-not-caching-my-site",
    label: "cf-cache-status: DYNAMIC vs BYPASS vs MISS",
    note: "Crawler traffic that survives the cache is the traffic that actually costs you money at the origin.",
  },
  {
    href: "/guides/what-is-the-orange-cloud-in-cloudflare",
    label: "What does the orange cloud mean in Cloudflare?",
    note: "None of these controls apply to a hostname that is not proxied — the prerequisite behind all of it.",
  },
  {
    href: DOCS_BLOCK_AI_BOTS,
    label: "Cloudflare docs: Block AI Bots",
    note: "The reference this guide was checked against, including the September 15 default change.",
    external: true,
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

export default async function BlockAiCrawlersGuide({
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
        lede="Three different tools get described as blocking AI crawlers, and only one of them refuses a request. Knowing which is which is most of the job."
        updated={guide.updated}
        readingTime={guide.readingTime}
        related={RELATED}
      >
        <div className="glass r-island note p-6 sm:p-7">
          <p>
            <strong>
              Block AI crawlers with AI Crawl Control or the AI bot policies in
              Security Settings — both are on every plan, including Free.
            </strong>{" "}
            A managed <code>robots.txt</code> only states a preference and does
            not enforce anything.
          </p>
        </div>

        <p>
          The confusion is worth naming up front, because it is the reason so
          many sites believe they are protected and are not. Cloudflare ships
          three separate features that all get filed under &ldquo;blocking AI
          bots&rdquo;, and they sit at different points on a spectrum from
          asking politely to actually refusing.
        </p>
        <AiCrawlerLayers />
        <p>
          Cloudflare is unusually blunt about the first one. Its{" "}
          <a href={DOCS_ROBOTS_TXT} target="_blank" rel="noopener noreferrer">
            robots.txt documentation
          </a>{" "}
          says compliance is voluntary — the file expresses your preferences but
          does not prevent crawlers from accessing your content at a technical
          level, and some operators will disregard directives like{" "}
          <code>Disallow: /</code> and crawl anyway. The docs then point
          straight at{" "}
          <a
            href={DOCS_CRAWL_CONTROL}
            target="_blank"
            rel="noopener noreferrer"
          >
            AI Crawl Control
          </a>{" "}
          for enforcement, and note the two are designed to be used together:
          state the preference, then enforce it.
        </p>
        <p>
          If you do turn the managed file on, it behaves considerately.
          Cloudflare detects whether your origin already serves a{" "}
          <code>robots.txt</code> — verified by an HTTP <code>200</code> — and
          prepends its managed content to yours rather than replacing it, so
          your existing <code>Disallow</code> lines and sitemap reference
          survive.
        </p>

        <h2 id="september-15">What changes on September 15, 2026</h2>
        <p>
          This is the part with a deadline attached, so it goes before the
          how-to. Cloudflare&rsquo;s{" "}
          <a
            href={DOCS_BLOCK_AI_BOTS}
            target="_blank"
            rel="noopener noreferrer"
          >
            Block AI Bots documentation
          </a>{" "}
          sets out three changes landing on that date:
        </p>
        <ul>
          <li>
            <strong>New domains get new defaults.</strong> Bots classified as
            Training or as Agent will be blocked on pages that display ads.
            Search remains allowed.
          </li>
          <li>
            <strong>Mixed-purpose crawlers stop slipping through.</strong> A
            crawler used for both Search and Training will be blocked by every
            configuration that blocks AI training — including the legacy option.
            Today that legacy setting explicitly excludes them.
          </li>
          <li>
            <strong>The old switch is deprecated.</strong> &ldquo;Block AI
            bots&rdquo; is marked as deprecating on the same date, superseded by
            the behaviour presets below.
          </li>
        </ul>
        <p>
          Cloudflare notes that before September 15 all customers can opt out of
          the new defaults from Security Settings. If you run an ad-supported
          site and have deliberately left AI access open — because you have an
          agreement, or because the referral traffic is worth more to you than
          the crawl — that opt-out is the thing to handle this week rather than
          next month.
        </p>

        <h2 id="presets">The three behaviours you can set separately</h2>
        <p>
          Rather than one on/off switch, Cloudflare now splits AI activity by
          what the crawler is doing with your content. All customers get these
          presets, and each is configured independently:
        </p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th scope="col">Behaviour</th>
                <th scope="col">What it covers</th>
                <th scope="col">Typical call</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <th scope="row">Search</th>
                <td>
                  Crawlers collecting or indexing your content to answer
                  questions about it later
                </td>
                <td>Usually allow — this is where citations come from</td>
              </tr>
              <tr>
                <th scope="row">Agent</th>
                <td>
                  Real-time activity on a person&rsquo;s behalf, such as chat
                  fetch bots and browser-use agents
                </td>
                <td>Depends on whether those visits convert</td>
              </tr>
              <tr>
                <th scope="row">Training</th>
                <td>
                  Crawlers taking content to train or fine-tune a model,
                  including mixed-purpose crawlers
                </td>
                <td>The one most publishers block</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p>
          Each of the three takes one of three mitigations:{" "}
          <strong>Block (on all pages)</strong>, which applies across the whole
          zone; <strong>Block on pages with ads</strong>, which uses
          Cloudflare&rsquo;s automated detection of ad-bearing pages and blocks
          only there; or <strong>Allow</strong>, which adds no blocking. Each
          blocking option covers{" "}
          <a
            href={DOCS_VERIFIED_BOTS}
            target="_blank"
            rel="noopener noreferrer"
          >
            verified bots
          </a>{" "}
          in that class plus unverified bots that behave similarly.
        </p>

        <h2 id="per-crawler">Going crawler by crawler</h2>
        <p>
          Where the presets are broad strokes,{" "}
          <a
            href={DOCS_MANAGE_CRAWLERS}
            target="_blank"
            rel="noopener noreferrer"
          >
            AI Crawl Control
          </a>{" "}
          works one operator at a time. Its Crawlers table lists each crawler
          with its operator, category, request volume and — the column most
          worth your attention — how many times it has violated your{" "}
          <code>robots.txt</code>. That number turns an abstract argument about
          crawler etiquette into a list of names, and it is the cleanest
          justification for moving a specific operator from allow to block.
        </p>
        <p>
          There is an important asterisk on the Free plan. Cloudflare documents
          that free-tier detection identifies AI crawlers by their user agent
          string, which catches well-known, self-identifying crawlers and
          nothing else. Thorough detection using the Bot Management detection ID
          requires a paid plan. So on Free you can reliably block the crawlers
          that announce themselves honestly — which is a real result, just not
          the same as blocking everything.
        </p>
        <p>
          Two adjacent features round it out. Cloudflare tracks{" "}
          <a
            href={DOCS_TRACK_ROBOTS}
            target="_blank"
            rel="noopener noreferrer"
          >
            robots.txt health and violations
          </a>{" "}
          so you can see who is ignoring you, and{" "}
          <a href={DOCS_PAY_PER_CRAWL} target="_blank" rel="noopener noreferrer">
            pay per crawl
          </a>{" "}
          — currently a closed beta — adds charging as a third option beside
          allow and block.
        </p>

        <h2 id="labyrinth">The layer that does not block anything</h2>
        <p>
          <a href={DOCS_LABYRINTH} target="_blank" rel="noopener noreferrer">
            AI Labyrinth
          </a>{" "}
          deserves its own note because it is easy to misfile as a blocking
          tool. It adds invisible, <code>nofollow</code>-tagged links to your
          pages; crawlers that ignore your no-crawl instructions follow them
          into a maze of never-ending links, and what they reveal about
          themselves is fed back into Cloudflare&rsquo;s detection for every
          customer who blocks AI bots. Cloudflare states the links do not affect
          your SEO or your site&rsquo;s appearance and are only seen by bots,
          and that well-behaved crawlers ignore the honeypot safely.
        </p>
        <p>
          For anything the presets do not express — a single path, a specific
          user agent, a rate you want to cap rather than refuse — the general{" "}
          <a href={DOCS_CUSTOM_RULES} target="_blank" rel="noopener noreferrer">
            WAF custom rules
          </a>{" "}
          are still the escape hatch, and a block there produces the same{" "}
          <Link href="/guides/cloudflare-error-1020-access-denied">
            1020 page
          </Link>{" "}
          a human would see. If your objection is contractual as much as
          technical, Cloudflare also publishes{" "}
          <a
            href={DOCS_SAMPLE_TERMS}
            target="_blank"
            rel="noopener noreferrer"
          >
            sample terms of service language
          </a>{" "}
          for restricting AI scraping, which is the piece that gives the
          technical block something to stand on.
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
