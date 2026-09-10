import { useState, useRef, useEffect } from 'react'
import { Link } from 'react-router-dom'
import {
  collection, query, where, orderBy, limit, onSnapshot, addDoc, serverTimestamp,
} from 'firebase/firestore'
import { db } from '../firebase'
import GuidePrompt from '../components/GuidePrompt'

/**
 * Public landing page at `/`.
 *
 * Redesigned with a magazine-style layout: bold typography, floating cards,
 * diagonal accents, and a more dynamic visual hierarchy.
 */

const PILLARS = [
  {
    icon: '/assets/doctor.svg',
    title: 'Medical',
    body: 'Ambulance crews and practitioners dispatched to trauma, cardiac and maternal emergencies — the calls where the first hour decides the outcome.',
    meta: 'Ambulance · Practitioner',
  },
  {
    icon: '/assets/fire.svg',
    title: 'Fire',
    body: 'Fire incidents routed to the stations equipped to answer them, with the caller tracked live rather than described down a phone line.',
    meta: 'Fire service',
  },
  {
    icon: '/assets/flood.svg',
    title: 'Flood & disaster',
    body: 'Flooding and disaster events treated as a first-class category, not something bolted onto an ambulance app.',
    meta: 'Rescue · Disaster response',
  },
  {
    icon: '/assets/police.svg',
    title: 'Security',
    body: 'Security incidents reach the responders and posts able to act on them, with location shared the moment the call is raised.',
    meta: 'Police · Private security',
  },
  {
    icon: '/assets/ambulance.svg',
    title: 'Onward referral',
    body: 'When a crew arrives and the patient needs more than they can give, they refer on to a hospital or clinic — every leg timestamped.',
    meta: 'Hospitals · Clinics',
  },
  {
    icon: '/assets/user.svg',
    title: 'Private cover',
    body: 'Hospitals, insurers and employers register their own clients, and their own crews answer them directly instead of the public queue.',
    meta: 'Organisations',
  },
]

const CAPABILITIES = [
  ['One-tap SOS', 'Hold for a second to confirm. Long enough to prevent an accident, short enough never to slow a real emergency.'],
  ['AI voice triage', 'Describe what is happening out loud. The type, severity and key facts are drafted for the responder before they arrive.'],
  ['Live tracking', 'Watch the responder approach with real road distance, travel time and arrival time.'],
  ['In-app navigation', 'Turn-by-turn guidance with spoken prompts, so a crew never leaves the job to open another app.'],
  ['Verified responders', 'Nobody puts themselves on the network. Every crew is promoted and verified by an administrator.'],
  ['999 always available', 'The emergency line sits on every screen. A faster route to help, never a replacement for one.'],
]

const STATS = [
  ['4,748', 'road traffic deaths in Kenya, 2024', 'NTSA'],
  ['13', 'lives lost on Kenyan roads each day', 'NTSA'],
  ['93.7%', 'live within an hour of an emergency department', 'National EMS study'],
  ['<20 min', 'target average response time', 'eKonnect target'],
]

/**
 * Institutions behind the project. Logos are served from `public/assets/` —
 * hotlinking the originals would break the page the moment a CDN token
 * expires, and the two university marks shipped on hard white, so their
 * backgrounds are flooded to the card colour to sit on cream.
 */
const PARTNERS = [
  { name: 'MMUST Innovation Academy', logo: '/assets/partners/mmust-innovation-academy.png' },
  { name: 'Masinde Muliro University of Science and Technology', logo: '/assets/partners/mmust-logo.png' },
  { name: 'Tafiti Research & Innovation Hub', logo: '/assets/partners/tafiti-hub.png' },
]

/**
 * Audiences.
 *
 * Photographs rather than icons. All three frames come from the same
 * mass-casualty simulation exercise — real Kenyan crews, real equipment — and
 * the section says so underneath rather than passing a drill off as an
 * incident. Each card carries three checkable facts instead of a mood
 * sentence; a claim someone can hold you to is what makes a page read as real.
 */
const AUDIENCES = [
  {
    title: 'Citizens',
    tag: 'Free, always',
    photo: '/assets/photos/on-scene-care.jpg',
    focus: 'center',
    body: 'Press SOS and reach the public responder network at no cost. No subscription, no paywall.',
    facts: [
      'No account fee, now or later',
      'Voice reporting if you cannot type',
      '999 stays on every screen',
    ],
  },
  {
    title: 'Responders',
    tag: 'Verified crews',
    photo: '/assets/photos/crew-scene.jpg',
    focus: 'center',
    body: 'Ambulance drivers and practitioners work a duty toggle, accept calls and navigate — all in one app.',
    facts: [
      'Promoted by an administrator, never self-registered',
      'Dispatched only while your duty toggle is on',
      'Voice-guided navigation without leaving the job',
    ],
  },
  {
    title: 'Providers',
    tag: 'Private networks',
    photo: '/assets/photos/hero-ambulance.jpg',
    // Different crop from the hero, so the same frame does not read twice.
    focus: '72% center',
    body: 'Hospitals, insurers and employers register their own clients and answer them with their own crews.',
    facts: [
      'Your crews reach your clients first',
      'Your own roster and coverage area',
      'Every leg of the journey timestamped in the console',
    ],
  },
]

/** The arrow every call-to-action carries, matching the reference's buttons. */
function Arrow({ className = 'w-4 h-4' }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor"
         strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 12h14m0 0l-6-6m6 6l-6 6" />
    </svg>
  )
}

/** Everything the header offers, in one list so the bar and the drawer cannot
 *  drift apart. `to` is a route, `href` an anchor on this page. */
const NAV_LINKS = [
  { label: 'Services', href: '#services' },
  { label: 'Who it serves', href: '#who' },
  { label: 'Register a Care Point', to: '/register' },
  { label: 'Become a responder', to: '/apply' },
  { label: 'Get the app', href: '#get' },
  { label: 'Testing guide', to: '/guide' },
  { label: 'Care Point portal', to: '/login' },
  { label: 'Admin login', to: '/login' },
]

/**
 * Site header.
 *
 * Below md the links collapse into a drawer behind a hamburger, with Download
 * sitting immediately after it. Until now those links simply vanished on a
 * phone — `hidden md:flex` with nothing standing in for them — so half the
 * site, including both application forms, was unreachable from a handset.
 */
function Nav() {
  const [open, setOpen] = useState(false)

  // Any navigation closes the drawer: an in-page anchor does not remount
  // anything, so nothing else would.
  const close = () => setOpen(false)

  return (
    <header className="sticky top-0 z-40 bg-cream/85 backdrop-blur-xl border-b border-ink/[0.06]">
      <div className="max-w-7xl mx-auto px-6 h-20 flex items-center justify-between gap-4">
        <a href="#top" onClick={close} className="flex items-center gap-2.5 flex-shrink-0">
          {/* The purple mark stands on its own against cream — the old purple
              tile existed only to make the white artwork visible here. */}
          <img src="/assets/logo-purple.png" alt="" className="w-9 h-9 object-contain" decoding="async" />
          <span className="font-bold text-xl tracking-tight">eKonnect</span>
        </a>

        <nav className="hidden md:flex items-center gap-7 text-sm font-medium text-ink-soft">
          {NAV_LINKS.filter(l => !l.to || l.to !== '/login').map(l => (
            <NavItem key={l.label} link={l} onClick={close} />
          ))}
        </nav>

        <div className="flex items-center gap-2 sm:gap-3 flex-shrink-0">
          <Link
            to="/login"
            className="text-sm font-semibold text-ink-soft hover:text-ink px-3 py-2 hidden md:block transition-colors whitespace-nowrap"
          >
            Portal sign in
          </Link>

          {/* On phones the bar carries only the hamburger. Download moves down
              into the drawer, where it gets full width instead of competing
              with the toggle for a 360px row. */}
          {/* The only control in the bar on a phone, so it is drawn as one:
              a bordered tile with a heavy mark, rather than three hairlines
              floating in the corner. */}
          <button
            onClick={() => setOpen(v => !v)}
            aria-label={open ? 'Close menu' : 'Open menu'}
            aria-expanded={open}
            className="md:hidden w-12 h-12 rounded-xl flex items-center justify-center
                       border border-ink/[0.12] bg-cream-card text-ink
                       hover:bg-ink hover:text-cream hover:border-ink
                       active:scale-95 transition-all duration-200"
          >
            <svg className="w-7 h-7" viewBox="0 0 24 24" fill="none" stroke="currentColor"
                 strokeWidth="2.75" strokeLinecap="round">
              {open
                ? <path d="M6 6l12 12M18 6L6 18" />
                : <><path d="M3.5 7h17" /><path d="M3.5 12h17" /><path d="M3.5 17h17" /></>}
            </svg>
          </button>

          <a href="#get" className="lp-btn !px-5 !py-2.5 hidden md:inline-flex">
            Download <Arrow />
          </a>
        </div>
      </div>

      {/* Drawer. Height-animated rather than mounted and unmounted, so it opens
          and closes rather than appearing. */}
      <div
        className={`md:hidden overflow-hidden border-t border-ink/[0.06] transition-[max-height,opacity] duration-300 ${
          open ? 'max-h-[28rem] opacity-100' : 'max-h-0 opacity-0'
        }`}
      >
        <nav className="px-6 pt-2 pb-6 flex flex-col bg-cream">
          {NAV_LINKS.map(l => (
            <NavItem
              key={l.label}
              link={l}
              onClick={close}
              className="py-3.5 text-base font-medium text-ink-soft hover:text-ink border-b border-ink/[0.05]"
            />
          ))}
          <a href="#get" onClick={close} className="lp-btn mt-5 justify-center">
            Download the app <Arrow />
          </a>
        </nav>
      </div>
    </header>
  )
}

function NavItem({ link, onClick, className = 'hover:text-ink transition-colors' }) {
  return link.to
    ? <Link to={link.to} onClick={onClick} className={className}>{link.label}</Link>
    : <a href={link.href} onClick={onClick} className={className}>{link.label}</a>
}

/** Section header: heading left, action right — the reference's default rhythm. */
function SectionHead({ eyebrow, title, body, action }) {
  return (
    <div className="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-6 mb-14">
      <div className="max-w-2xl">
        {eyebrow && (
          <span className="block text-xs font-semibold tracking-[0.14em] uppercase text-primary mb-4">
            {eyebrow}
          </span>
        )}
        <h2 className="lp-display text-4xl sm:text-5xl">{title}</h2>
        {body && <p className="mt-4 text-ink-soft leading-relaxed">{body}</p>}
      </div>
      {action}
    </div>
  )
}

export default function Landing() {
  return (
    // Warm cream ground rather than white or a purple-tinted grey. A warm
    // neutral makes the purple read richer; a cool grey muddies into it.
    <div className="min-h-screen bg-cream text-ink antialiased font-sans overflow-x-hidden">
      {/* Points first-time visitors at the tester's guide, once. */}
      <GuidePrompt />

      {/* ── Nav ─────────────────────────────────────────────────────────── */}
      <Nav />

      {/* ── Hero ────────────────────────────────────────────────────────── */}
      <section id="top" className="relative text-white overflow-hidden bg-ink">
        {/* Real crews, real ambulance — a photograph earns trust here in a way
            an illustration cannot. */}
        <img
          src="/assets/photos/hero-ambulance.jpg"
          alt="An ambulance crew loading a patient on a stretcher"
          fetchPriority="high"
          decoding="async"
          className="absolute inset-0 w-full h-full object-cover object-center"
        />
        {/* Two scrims, doing different jobs: a brand wash to tie the photo to
            the palette, and a left-weighted darkening so the headline keeps
            contrast over a bright, busy daytime image. */}
        <div className="absolute inset-0 bg-primary/70 mix-blend-multiply" />
        <div className="absolute inset-0 bg-gradient-to-r from-ink/90 via-ink/70 to-ink/20" />
        <div className="absolute inset-0 bg-gradient-to-t from-ink/80 via-transparent to-ink/40" />

        <div className="relative max-w-7xl mx-auto px-6 py-32 sm:py-44">
          <div className="max-w-3xl">
            <h1 className="text-5xl sm:text-7xl font-bold tracking-tightest leading-[1.04]">
              Emergency response,<br />coordinated.
            </h1>
            <p className="mt-6 text-lg sm:text-xl text-white/70 max-w-xl leading-relaxed">
              One platform connecting people in an emergency, the crews who answer
              them, and the administrators who keep the network accountable.
            </p>
            <div className="mt-10 flex flex-col sm:flex-row gap-3">
              <a href="#get" className="lp-btn-light">
                Download the app <Arrow />
              </a>
              <Link
                to="/login"
                className="inline-flex items-center gap-2 border border-white/25 text-white px-6 py-3.5 rounded-xl text-sm font-semibold tracking-tight hover:border-white/60 hover:gap-3 transition-all duration-300"
              >
                Admin login <Arrow />
              </Link>
            </div>
          </div>
        </div>
      </section>

      {/* ── Stats strip ─────────────────────────────────────────────────── */}
      {/* On lg the cells are a fixed h-48, so the row is exactly 192px and the
          -mt-24 lift puts half of it above the hero edge and half below — the
          strip sits centred on the line rather than nudged over it.
          Below lg that fixed height is dropped for a minimum plus real padding:
          narrow columns wrap "<20 min" and "an emergency department" onto extra
          lines, and a hard 192px left the source credit jammed against the
          bottom edge. */}
      <section className="relative -mt-16 sm:-mt-20 lg:-mt-24 px-4 sm:px-6 z-10">
        <div className="max-w-7xl mx-auto bg-cream-card rounded-3xl grid grid-cols-2 lg:grid-cols-4 divide-x divide-ink/[0.07] shadow-[0_24px_60px_-24px_rgba(28,10,38,0.22)]">
          {STATS.map(([value, label, source]) => (
            <div
              key={label}
              className="min-h-[11rem] py-9 lg:py-0 lg:h-48 lg:min-h-0 px-4 sm:px-6 lg:px-8
                         flex flex-col items-center justify-center text-center"
            >
              <p className="text-4xl sm:text-5xl font-bold text-ink tracking-tightest leading-none">{value}</p>
              <p className="text-sm sm:text-base text-ink-soft mt-3 leading-snug max-w-[16rem]">{label}</p>
              <p className="text-xs text-ink-mute mt-2 font-semibold tracking-wide">{source}</p>
            </div>
          ))}
        </div>
      </section>

      {/* ── Partners ────────────────────────────────────────────────────── */}
      <section className="bg-cream pt-20 pb-4">
        <div className="max-w-7xl mx-auto px-6">
          <p className="text-center text-xs font-semibold tracking-[0.18em] uppercase text-ink-mute">
            In partnership with
          </p>
          <div className="mt-10 flex flex-wrap items-center justify-center gap-6 sm:gap-10">
            {PARTNERS.map(p => (
              <div
                key={p.name}
                className="group flex items-center gap-4 bg-cream-card border border-ink/[0.07] rounded-2xl px-6 py-4
                           hover:border-ink/20 hover:-translate-y-0.5 transition-all duration-300"
              >
                {/* Logos arrive at three different sizes and two different
                    background treatments; a fixed box with object-contain is
                    what makes them sit on one optical line. */}
                <img
                  src={p.logo}
                  alt={`${p.name} logo`}
                  loading="lazy"
            decoding="async"
                  className="w-12 h-12 object-contain flex-shrink-0 grayscale opacity-70
                             group-hover:grayscale-0 group-hover:opacity-100 transition-all duration-500"
                />
                <span className="text-sm font-semibold tracking-tight text-ink leading-snug max-w-[11rem]">
                  {p.name}
                </span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── Coverage cards ─────────────────────────────────────────────── */}
      <CoverageGrid />

      {/* ── Story player ────────────────────────────────────────────────── */}
      <StoryPlayer />

      {/* ── Capabilities ────────────────────────────────────────────────── */}
      {/* Bento grid: mixed card sizes and colour-blocked fills, the reference's
          signature layout. Weighting the cards differently lets the two claims
          that matter most carry the section instead of six equal tiles. */}
      <section className="bg-cream py-24">
        <div className="max-w-7xl mx-auto px-6">
          <SectionHead
            eyebrow="Capabilities"
            title={<>Built for the minutes<br />that decide the outcome</>}
            body="Every feature exists to shave seconds off the time between an emergency and a qualified responder reaching it."
            action={<a href="#get" className="lp-btn flex-shrink-0">Get the app <Arrow /></a>}
          />

          <div className="grid lg:grid-cols-3 gap-5">
            {/* Lead card — the product's whole premise. */}
            <div className="lp-card bg-block-night text-white lg:row-span-2 min-h-[560px] relative overflow-hidden">
              <div className="relative z-10">
                <span className="text-xs font-semibold tracking-[0.14em] uppercase text-white/40">01</span>
                <h3 className="text-2xl font-bold tracking-tight mt-4">One-tap SOS</h3>
                <p className="text-white/60 mt-3 leading-relaxed">
                  Hold for a second to confirm. Long enough to prevent an accident,
                  short enough never to slow a real emergency.
                </p>
              </div>
              <CardShot src="/assets/app/home.jpg" className="left-10 right-10 -bottom-10 h-[380px]" />
            </div>

            {/* Voice triage has no screenshot worth cropping — the interesting
                part is the listening state, so it is drawn rather than shot. */}
            <div className="lp-card bg-block-plum text-white min-h-[300px] relative overflow-hidden">
              <div className="relative z-10">
                <span className="text-xs font-semibold tracking-[0.14em] uppercase text-white/40">02</span>
                <h3 className="text-2xl font-bold tracking-tight mt-4">AI voice triage</h3>
                <p className="text-white/60 mt-3 leading-relaxed">
                  Describe what is happening out loud. Type, severity and key facts
                  are drafted for the responder before they arrive.
                </p>
              </div>
              <VoiceMock />
            </div>

            {/* Photo card: on-scene care, which is what "live tracking" is
                actually counting down to. */}
            <div className="lp-card bg-block-steel text-white min-h-[300px] relative overflow-hidden">
              <img
                src="/assets/photos/on-scene-care.jpg"
                alt=""
                loading="lazy"
            decoding="async"
                className="absolute inset-0 w-full h-full object-cover opacity-25"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-block-steel via-block-steel/85 to-block-steel/40" />
              <div className="relative z-10 max-w-[62%]">
                <span className="text-xs font-semibold tracking-[0.14em] uppercase text-white/50">03</span>
                <h3 className="text-2xl font-bold tracking-tight mt-4">Live tracking</h3>
                <p className="text-white/70 mt-3 leading-relaxed">
                  Watch the responder approach with real road distance, travel time
                  and the clock time they should arrive.
                </p>
              </div>
              <CardShot
                src="/assets/app/tracking.jpg"
                className="-right-8 -bottom-12 w-[46%] h-[260px]"
                tilt={-8}
              />
            </div>

            <div className="lp-card bg-cream-card min-h-[300px] relative overflow-hidden">
              <div className="relative z-10 max-w-[62%]">
                <span className="text-xs font-semibold tracking-[0.14em] uppercase text-ink-mute">04</span>
                <h3 className="text-xl font-bold tracking-tight mt-4">In-app navigation</h3>
                <p className="text-ink-soft mt-3 leading-relaxed text-sm">
                  Turn-by-turn guidance with spoken prompts, so a crew never leaves
                  the job to open another app.
                </p>
              </div>
              <CardShot
                src="/assets/app/navigation.png"
                className="-right-6 -bottom-12 w-[44%] h-[250px]"
                tilt={7}
              />
            </div>

            <div className="lp-card bg-cream-card min-h-[300px] relative overflow-hidden">
              <div className="relative z-10 max-w-[62%]">
                <span className="text-xs font-semibold tracking-[0.14em] uppercase text-ink-mute">05</span>
                <h3 className="text-xl font-bold tracking-tight mt-4">Verified responders</h3>
                <p className="text-ink-soft mt-3 leading-relaxed text-sm">
                  Nobody puts themselves on the network. Every crew is promoted and
                  verified by an administrator first.
                </p>
              </div>
              <CardShot
                src="/assets/app/responder.jpg"
                className="-right-6 -bottom-12 w-[44%] h-[250px]"
                tilt={-6}
              />
            </div>

            {/* Coral card: the one claim that is a safety promise, not a feature. */}
            <div className="lp-card bg-block-coral text-white lg:col-span-3 flex-row items-center justify-between gap-8">
              <div className="max-w-xl">
                <h3 className="text-2xl font-bold tracking-tight">999 is always one tap away</h3>
                <p className="text-white/80 mt-2 leading-relaxed">
                  The emergency line sits on every screen. eKonnect is a faster route
                  to help — never a replacement for one.
                </p>
              </div>
              <img src="/assets/call.svg" alt="" className="w-14 h-14 flex-shrink-0 hidden sm:block" decoding="async" />
            </div>
          </div>
        </div>
      </section>

      {/* ── Who it serves ───────────────────────────────────────────────── */}
      <section id="who" className="relative bg-primary text-white scroll-mt-16 overflow-hidden">
        {/* The photography has moved onto the cards, so the band itself just
            needs depth behind them — a wash rather than a picture. */}
        {/* Lighter than it was. With near-black cards the band had to be dark
            to sit behind them; with cream cards it can read as brand purple,
            which is what makes them lift off it. */}
        <div className="absolute inset-0 bg-gradient-to-b from-block-night/45 via-transparent to-block-night/35" />
        <div className="relative max-w-7xl mx-auto px-6 py-24">
          <div className="text-center max-w-3xl mx-auto">
            <span className="text-sm font-semibold tracking-wider uppercase text-purple-300">Audiences</span>
            <h2 className="text-4xl font-bold tracking-tight mt-3">Who it serves</h2>
            <p className="mt-4 text-purple-100/70 leading-relaxed">
              Three groups, one network — and a different promise to each.
            </p>
          </div>

          {/* Cream cards, not dark ones.
              These were block-night on a purple band: a near-black card on a
              dark ground has almost no edge, and the gradient needed to lift
              the tag off the photo dragged the bottom third of every
              photograph into mud. Light cards give the band something to frame,
              match the cards everywhere else on the page, and let the
              photography keep its own contrast. */}
          <div className="mt-16 grid sm:grid-cols-2 lg:grid-cols-3 gap-6">
            {AUDIENCES.map(a => (
              <article
                key={a.title}
                className="group bg-cream-card rounded-3xl overflow-hidden flex flex-col
                           shadow-[0_24px_50px_-24px_rgba(0,0,0,0.55)]
                           hover:shadow-[0_36px_70px_-28px_rgba(0,0,0,0.65)]
                           hover:-translate-y-1.5 transition-all duration-500"
              >
                <div className="relative aspect-[4/3] overflow-hidden bg-ink/10">
                  <img
                    src={a.photo}
                    alt=""
                    loading="lazy"
            decoding="async"
                    style={{ objectPosition: a.focus }}
                    className="w-full h-full object-cover transition-transform duration-[1200ms] group-hover:scale-105"
                  />
                  {/* A light brand wash still ties three differently-lit frames
                      into one set, but at 20% it tints rather than darkens. */}
                  <div className="absolute inset-0 bg-primary/20 mix-blend-multiply transition-opacity duration-500 group-hover:opacity-0" />
                  {/* The tag is a solid chip now. It used to be bare text that
                      needed a black gradient behind it to stay readable. */}
                  <span className="absolute left-4 top-4 bg-cream-card/95 backdrop-blur-sm text-primary
                                   text-[11px] font-bold tracking-[0.14em] uppercase px-3 py-1.5 rounded-full">
                    {a.tag}
                  </span>
                </div>

                <div className="p-7 flex flex-col flex-1">
                  <h3 className="font-bold text-2xl tracking-tightest text-ink">{a.title}</h3>
                  <p className="text-sm text-ink-soft mt-2.5 leading-relaxed">{a.body}</p>
                  <ul className="mt-6 space-y-3.5 border-t border-ink/[0.08] pt-6">
                    {a.facts.map(f => (
                      <li key={f} className="flex items-start gap-3 text-sm text-ink-soft">
                        <span className="mt-0.5 w-5 h-5 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
                          <svg className="w-3 h-3 text-primary" fill="currentColor" viewBox="0 0 20 20">
                            <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
                          </svg>
                        </span>
                        <span className="leading-relaxed">{f}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              </article>
            ))}
          </div>

          {/* Says what the pictures actually are. A drill presented as an
              incident is the fastest way to lose the trust the photos buy. */}
          <p className="mt-10 text-center text-xs text-purple-200/50">
            Photographed during a mass-casualty simulation exercise with Kenyan
            ambulance crews and practitioners.
          </p>
        </div>
      </section>

      {/* ── Care Point recruitment ──────────────────────────────────────── */}
      {/* Full-bleed on phones, same as the product deck: the page gutter plus
          a 40px corner radius put two frames around a card that is already the
          width of the screen. */}
      <section className="bg-cream py-16 sm:py-24">
        <div className="max-w-7xl mx-auto px-0 sm:px-6">
          <div className="bg-block-night text-white rounded-none sm:rounded-[40px] overflow-hidden grid lg:grid-cols-2">
            <div className="px-6 py-12 sm:p-14 flex flex-col justify-center">
              <span className="text-xs font-semibold tracking-[0.16em] uppercase text-purple-300">
                For facilities
              </span>
              <h2 className="text-3xl sm:text-4xl font-bold tracking-tightest mt-4 leading-[1.1]">
                Put your hospital<br />on the network
              </h2>
              <p className="mt-5 text-white/65 leading-relaxed max-w-md">
                Register once and your crews answer under your name — a patient
                waiting sees “Ben · Ambulance driver · Oasis Hospital”, not an
                anonymous responder. Other crews can refer patients to you, with
                every leg timestamped.
              </p>
              <ul className="mt-8 space-y-3">
                {[
                  'Attach as many responders as you employ',
                  'Verified before a single call reaches you',
                  'Public network, or private clients only — your choice',
                ].map(f => (
                  <li key={f} className="flex items-start gap-3 text-sm text-white/75">
                    <svg className="w-4 h-4 mt-0.5 flex-shrink-0 text-purple-300" fill="currentColor" viewBox="0 0 20 20">
                      <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
                    </svg>
                    <span className="leading-relaxed">{f}</span>
                  </li>
                ))}
              </ul>
              <div className="mt-10 flex flex-col sm:flex-row gap-3">
                <Link to="/register" className="lp-btn-light">
                  Register a Care Point <Arrow />
                </Link>
                <Link
                  to="/apply"
                  className="inline-flex items-center gap-2 border border-white/25 text-white px-6 py-3.5 rounded-xl
                             text-sm font-semibold tracking-tight hover:border-white/60 hover:gap-3 transition-all duration-300"
                >
                  I am a responder <Arrow />
                </Link>
              </div>
              <div className="mt-6">
                <Link
                  to="/login"
                  className="inline-flex items-center gap-2 text-sm font-semibold text-purple-200 hover:text-white hover:gap-3 transition-all duration-300"
                >
                  Already registered? Sign in to your Care Point portal <Arrow />
                </Link>
              </div>
            </div>
            <div className="relative min-h-[280px] lg:min-h-0 bg-block-night">
              <img
                src="/assets/photos/hero-ambulance.jpg"
                alt=""
                loading="lazy"
            decoding="async"
                className="absolute inset-0 w-full h-full object-cover"
                style={{ objectPosition: '35% center' }}
              />
              <div className="absolute inset-0 bg-primary/40 mix-blend-multiply" />
              <div className="absolute inset-0 bg-gradient-to-r from-block-night via-block-night/40 to-transparent" />
            </div>
          </div>
        </div>
      </section>

      {/* ── Trending events ────────────────────────────────────────────── */}
      <TrendingEvents />

      {/* ── Download ────────────────────────────────────────────────────── */}
      <section id="get" className="relative py-24 scroll-mt-16 bg-cream">
        <div className="max-w-7xl mx-auto px-6">
          <div className="grid lg:grid-cols-[minmax(0,340px)_1fr] gap-10 lg:gap-20 items-center">
            {/* The launcher icon at display size — what people will be looking
                for on their home screen once it is installed. */}
            <div className="min-w-0 flex justify-center lg:justify-start">
              <img
                src="/assets/app-icon.png"
                alt="The eKonnect app icon"
                loading="lazy"
                decoding="async"
                className="w-56 h-56 sm:w-72 sm:h-72 rounded-[22%] shadow-[0_40px_80px_-40px_rgba(28,10,38,0.6)]"
              />
            </div>

            <div className="min-w-0">
              {/* text-3xl on the narrowest screens: at 4xl "eKonnect" alone is
                  wider than a 360px phone once tracking-tightest is applied. */}
              <h2 className="lp-display text-3xl sm:text-4xl md:text-5xl">Download the eKonnect App</h2>
              <p className="mt-4 text-xl sm:text-2xl font-bold tracking-tight text-ink">
                Help, one tap away.
              </p>
              <p className="mt-3 text-sm font-semibold text-primary">
                Available on Android · iOS coming soon
              </p>

              <div className="mt-8 flex flex-col sm:flex-row items-stretch sm:items-center gap-3 max-w-md sm:max-w-none">
                <DownloadButton />
                <div className="store-badge opacity-40 cursor-not-allowed">
                  <svg className="w-7 h-7 flex-shrink-0" viewBox="0 0 24 24" fill="none"
                       stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                    <circle cx="12" cy="12" r="9" />
                    <path d="M12 7v5l3 2" />
                  </svg>
                  <span>
                    <span className="block text-[10px] leading-none opacity-70">Coming soon</span>
                    <span className="block text-base font-semibold leading-tight mt-1">iOS</span>
                  </span>
                </div>
              </div>

              <LinkToPhone />

              <p className="mt-6 text-xs text-ink-mute max-w-md leading-relaxed">
                The file saves to your Downloads — on a phone it appears in the
                notification tray while it copies, so nothing seems to happen on
                this page. Android will then ask you to allow installation from
                this source. If an older build is installed, uninstall it first.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* ── Footer ──────────────────────────────────────────────────────── */}
      <footer className="bg-ink text-white">
        <div className="max-w-7xl mx-auto px-6 py-16 grid sm:grid-cols-2 lg:grid-cols-4 gap-12">
          <div>
            <div className="flex items-center gap-3">
              {/* Dark footer — the white artwork reads directly here, so it
                  needs no tile either. Same silhouette as the nav, inverted. */}
              <img src="/assets/logo.png" alt="" className="w-10 h-10 object-contain" decoding="async" />
              <span className="font-bold text-xl tracking-tight">eKonnect</span>
            </div>
            <p className="text-sm text-ink-mute mt-4 leading-relaxed">
              Emergency response infrastructure for Kenya and East Africa.
            </p>
          </div>
          <FooterCol title="Product" links={[['Services', '#services'], ['Who it serves', '#who'], ['Download', '#get'], ['Register a Care Point', '/register'], ['Become a responder', '/apply']]} />
          <FooterCol title="Sign in" links={[['Care Point portal', '/login'], ['Admin console', '/login']]} routed />
          <div>
            <h4 className="font-semibold text-sm">Built by</h4>
            {/* External, so it opens away from the site and carries
                noopener — a target=_blank link without it hands the new tab a
                reference back to this window. */}
            <a
              href="https://tafitirnihub.co.ke"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-baseline gap-1.5 text-sm text-ink-mute hover:text-white mt-4 leading-relaxed transition-colors group"
            >
              Tafiti Research &amp; Innovation Hub
              <svg className="w-3 h-3 flex-shrink-0 opacity-60 group-hover:opacity-100 transition-opacity"
                   viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"
                   strokeLinecap="round" strokeLinejoin="round">
                <path d="M7 17L17 7M17 7H8M17 7v9" />
              </svg>
            </a>
            <p className="text-xs text-ink-mute/70 mt-2">tafitirnihub.co.ke</p>
          </div>
        </div>
        <div className="border-t border-white/10">
          <div className="max-w-7xl mx-auto px-6 py-6 flex flex-col sm:flex-row items-center justify-between gap-3 text-sm text-ink-soft">
            <span>© {new Date().getFullYear()} eKonnect. All rights reserved.</span>
            <span className="flex items-center gap-4">
              <Link to="/guide" className="hover:text-white transition-colors">Testing guide</Link>
              <Link to="/privacy" className="hover:text-white transition-colors">Terms &amp; Privacy</Link>
              <span>In an emergency, always call 999.</span>
            </span>
          </div>
        </div>
      </footer>

    </div>
  )
}

/**
 * Deck slides.
 *
 * Each carries its own `surface` treatment and its own `enter` transform, so
 * advancing through the deck does not feel like the same card reskinned three
 * times — the ground changes underfoot and the phone arrives from a different
 * direction each time.
 */
const SCENES = [
  {
    image: '/assets/app/home.jpg',
    eyebrow: 'For the caller',
    title: 'Help in one tap — or one sentence',
    body: 'Choose an emergency type and hold to send. If you are injured, panicked, or unsure what to call it, describe it out loud instead and the app works out the rest.',
    points: [
      'Four emergency types, colour-coded and triaged',
      'Voice reporting with AI-drafted notes for the responder',
      'Cancel with a reason, so false alarms are told apart from coverage gaps',
    ],
    // Light card, phone on the left, mark rising out of the floor.
    surface: 'bg-cream-card',
    tone: 'light',
    glow: 'from-primary/25 to-purple-400/10',
    reverse: false,
    enter: 'translateY(70px) rotateX(16deg) scale(.92)',
  },
  {
    image: '/assets/app/tracking.jpg',
    eyebrow: 'While you wait',
    title: 'See exactly who is coming, and when',
    body: 'The moment a crew accepts, you get their name, credentials and live position — with real road distance, travel time and the clock time they should arrive.',
    points: [
      'Live responder position on the map',
      'Distance, travel time and arrival time from live routing',
      'One-tap call and chat with the assigned crew',
    ],
    // Night card, phone swings in from the right on its own axis.
    surface: 'bg-block-night',
    tone: 'dark',
    glow: 'from-block-coral/30 to-primary/20',
    reverse: true,
    enter: 'translateX(120px) rotateY(-32deg) scale(.94)',
  },
  {
    image: '/assets/app/navigation.png',
    eyebrow: 'For the crew',
    title: 'Navigation that never leaves the job',
    body: 'Marking en route starts turn-by-turn guidance inside the app, with spoken prompts. The patient\'s details, notes and status controls stay on screen the whole drive.',
    points: [
      'Voice-guided turn-by-turn to the patient',
      'Refer onward to a hospital or clinic when needed',
      'Every step timestamped for the record',
    ],
    // Brand purple, phone drops in from depth.
    surface: 'bg-primary',
    tone: 'dark',
    glow: 'from-white/25 to-block-steel/20',
    reverse: false,
    enter: 'translateZ(-260px) translateY(-40px) rotate(-8deg) scale(1.06)',
  },
]

/**
 * Trending events, published from the admin console.
 */
function TrendingEvents() {
  const [events, setEvents] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const q = query(
      collection(db, 'events'),
      where('published', '==', true),
      orderBy('date', 'desc'),
      limit(6),
    )
    const unsub = onSnapshot(
      q,
      snap => {
        setEvents(snap.docs.map(d => ({ id: d.id, ...d.data() })))
        setLoading(false)
      },
      () => setLoading(false),
    )
    return unsub
  }, [])

  if (loading || events.length === 0) return null

  return (
    <section id="events" className="relative py-24 scroll-mt-16 bg-cream">
      <div className="max-w-7xl mx-auto px-6">
        <div className="flex items-end justify-between gap-6 mb-16">
          <div>
            <span className="text-sm font-semibold tracking-wider uppercase text-primary">Network</span>
            <h2 className="text-4xl font-bold tracking-tight mt-2">Trending events</h2>
            <p className="mt-3 text-ink-soft max-w-lg leading-relaxed">
              Updates, incidents and announcements from the eKonnect network.
            </p>
          </div>
        </div>

        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-8">
          {events.map((e) => (
            <EventCard key={e.id} event={e} />
          ))}
        </div>
      </div>
    </section>
  )
}

function EventCard({ event }) {
  const Wrapper = event.link ? 'a' : 'div'
  const props = event.link
    ? { href: event.link, target: '_blank', rel: 'noopener noreferrer' }
    : {}

  const date = event.date?.toDate
    ? event.date.toDate()
    : event.date
      ? new Date(event.date)
      : null

  return (
    <Wrapper
      {...props}
      className="group block bg-cream-card rounded-3xl overflow-hidden border border-ink/[0.07] hover:shadow-[0_20px_50px_-24px_rgba(28,10,38,0.25)] transition-all duration-500 hover:-translate-y-2"
    >
      {event.image && (
        <div className="aspect-[4/3] overflow-hidden bg-ink/10">
          <img
            src={event.image}
            alt=""
            loading="lazy"
            decoding="async"
            className="w-full h-full object-cover transition-transform duration-700 group-hover:scale-110"
          />
        </div>
      )}
      <div className="p-6">
        <div className="flex items-center justify-between text-sm text-ink-soft">
          <span>
            {date
              ? date.toLocaleDateString('en-GB', {
                  day: '2-digit',
                  month: 'short',
                  year: 'numeric',
                })
              : ''}
          </span>
          {event.readTime && <span>{event.readTime} mins read</span>}
        </div>
        <div className="h-px bg-ink/10 my-4" />
        <h3 className="font-bold text-lg tracking-tight leading-snug group-hover:text-primary transition-colors">
          {event.title}
        </h3>
      </div>
    </Wrapper>
  )
}

const SCENE_MS = 8000

/**
 * The product deck.
 *
 * Slides sit side by side on one track and the track slides, so the next and
 * previous cards stay visible at the edges — the viewer can see there is more
 * before they interact. Only the centred card animates its contents in;
 * neighbours are dimmed and pushed back so nothing competes with it.
 */
function StoryPlayer() {
  const wrap = useRef(null)
  const [index, setIndex] = useState(0)
  const [shown, setShown] = useState(false)
  const [playing, setPlaying] = useState(false)
  const [paused, setPaused] = useState(false)
  // Autoplay is a hint, not a cage: the first deliberate click hands control
  // over for good rather than yanking the deck away mid-read.
  const [tookOver, setTookOver] = useState(false)

  const reduced =
    typeof window !== 'undefined' &&
    window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

  useEffect(() => {
    if (reduced) return
    const el = wrap.current
    if (!el) return

    const io = new IntersectionObserver(
      ([entry]) => {
        setPlaying(entry.isIntersecting)
        if (entry.isIntersecting) setShown(true)
      },
      { threshold: 0.35 },
    )
    io.observe(el)
    return () => io.disconnect()
  }, [reduced])

  useEffect(() => {
    if (reduced || !playing || paused || tookOver) return
    const hold = setTimeout(() => goTo((index + 1) % SCENES.length), SCENE_MS)
    return () => clearTimeout(hold)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [index, playing, paused, reduced, tookOver])

  // The track slides regardless; only the contents of the arriving card
  // re-animate, which is why `shown` drops for one frame and comes back.
  function goTo(i) {
    const next = (i + SCENES.length) % SCENES.length
    if (next === index) return
    setShown(false)
    setIndex(next)
    requestAnimationFrame(() => requestAnimationFrame(() => setShown(true)))
  }

  function advance(delta) {
    setTookOver(true)
    goTo(index + delta)
  }

  if (reduced) {
    return (
      <div className="py-24">
        {SCENES.map((s, i) => (
          <Band key={s.title} {...s} reverse={i % 2 === 1} />
        ))}
      </div>
    )
  }

  return (
    <section
      ref={wrap}
      className="relative py-24 scroll-mt-16 bg-cream overflow-hidden"
      onMouseEnter={() => setPaused(true)}
      onMouseLeave={() => setPaused(false)}
      aria-roledescription="carousel"
    >
      {/* Track. Percentage padding resolves against this container, so the
          active card lands dead centre without measuring anything in JS —
          the transform below only ever has to count whole cards.

          `--slide` and `--gap` live in index.css under `.ek-deck` rather than
          here, because they change at the sm breakpoint and an inline style
          cannot carry a media query. */}
      <div
        className="ek-deck flex items-stretch"
        style={{
          paddingLeft: 'calc(50% - var(--slide) / 2)',
          paddingRight: 'calc(50% - var(--slide) / 2)',
          gap: 'var(--gap)',
          transform: `translateX(calc((var(--slide) + var(--gap)) * ${-index}))`,
          transition: 'transform 900ms cubic-bezier(.16,.84,.34,1)',
          perspective: '1600px',
        }}
      >
        {SCENES.map((s, i) => (
          <DeckCard
            key={s.title}
            scene={s}
            active={i === index}
            // Which edge of an off-centre card is the one poking into view —
            // the label has to sit on the side the viewer can actually see.
            before={i < index}
            shown={shown && i === index}
            onSelect={() => { setTookOver(true); goTo(i) }}
          />
        ))}
      </div>

      {/* Pager: dots for the deck, a wide pill for where you are. */}
      <div className="mt-12 flex items-center justify-center gap-4">
        <DeckArrow label="Previous" onClick={() => advance(-1)} flip />
        <div className="flex items-center gap-2.5">
          {SCENES.map((s, i) => (
            <button
              key={s.title}
              onClick={() => { setTookOver(true); goTo(i) }}
              aria-label={s.eyebrow}
              aria-current={i === index}
              className={`h-2.5 rounded-full overflow-hidden transition-all duration-500 ${
                i === index ? 'w-14 bg-ink/15' : 'w-2.5 bg-ink/20 hover:bg-ink/40'
              }`}
            >
              {i === index && (
                <span
                  key={`${index}-${tookOver}`}
                  className="block h-full bg-primary rounded-full"
                  style={
                    tookOver
                      ? { width: '100%' }
                      : {
                          animation: `ek-fill ${SCENE_MS}ms linear forwards`,
                          animationPlayState: playing && !paused ? 'running' : 'paused',
                        }
                  }
                />
              )}
            </button>
          ))}
        </div>
        <DeckArrow label="Next" onClick={() => advance(1)} />
      </div>
    </section>
  )
}

function DeckArrow({ label, onClick, flip = false }) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      className="w-11 h-11 rounded-full border border-ink/15 text-ink flex items-center justify-center
                 hover:bg-ink hover:text-cream hover:border-ink active:scale-90
                 transition-all duration-300"
    >
      <svg
        className={`w-4 h-4 ${flip ? 'rotate-180' : ''}`}
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 7l5 5m0 0l-5 5m5-5H6" />
      </svg>
    </button>
  )
}

/**
 * One card in the deck.
 *
 * `active` controls how the card sits in space (centred and forward, or pushed
 * back and dimmed). `shown` controls the contents animating in, and only ever
 * goes true after the card is centred — so the reveal is never spent off-screen.
 */
function DeckCard({ scene, active, before, shown, onSelect }) {
  const dark = scene.tone === 'dark'
  const [hover, setHover] = useState(false)

  // Contents rise, sharpen and settle, one beat after the other.
  const step = (order) => ({
    opacity: shown ? 1 : 0,
    filter: shown ? 'blur(0)' : 'blur(8px)',
    transform: shown ? 'translateY(0)' : 'translateY(26px)',
    transition: `opacity 700ms cubic-bezier(.22,.61,.36,1) ${180 + order * 95}ms,
                 filter 700ms cubic-bezier(.22,.61,.36,1) ${180 + order * 95}ms,
                 transform 700ms cubic-bezier(.22,.61,.36,1) ${180 + order * 95}ms`,
  })

  return (
    <article
      onClick={active ? undefined : onSelect}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      aria-hidden={!active}
      // Scale and shadow are classes rather than inline style so they can be
      // dropped below sm. A full-bleed slide has no neighbours to sit behind,
      // so shrinking it there would only leave a gap at the screen edge.
      className={`${scene.surface} relative flex-none overflow-hidden
                  rounded-none sm:rounded-[40px] scale-100
                  ${active
                    ? 'sm:shadow-[0_50px_90px_-50px_rgba(28,10,38,0.55)]'
                    : 'sm:scale-90 sm:hover:scale-[0.93] sm:shadow-[0_30px_60px_-35px_rgba(28,10,38,0.65)] cursor-pointer'}`}
      style={{
        width: 'var(--slide)',
        // Off-centre cards stay fully opaque and are pushed back with a dark
        // scrim instead. Fading them towards the cream ground made the pale
        // card vanish at the edge — a dark slab reads as "there is more here"
        // whatever colour the card underneath happens to be.
        transition: `transform 900ms cubic-bezier(.16,.84,.34,1), box-shadow 700ms ease`,
      }}
    >
      {/* The scrim. Lifts a little on hover so the card answers the cursor
          before it has been clicked. */}
      <div
        className="absolute inset-0 z-20 bg-ink pointer-events-none"
        style={{
          opacity: active ? 0 : hover ? 0.62 : 0.84,
          transition: 'opacity 600ms ease',
        }}
      />
      {/* Which slide is waiting there, set along the visible edge like the
          spine of a book on a shelf. */}
      <div
        className="absolute inset-y-0 z-30 flex items-center pointer-events-none"
        style={{
          ...(before ? { right: '1.6rem' } : { left: '1.6rem' }),
          opacity: active ? 0 : 1,
          transition: 'opacity 500ms ease',
        }}
      >
        <span
          className="text-cream/80 text-[11px] font-semibold tracking-[0.38em] uppercase whitespace-nowrap"
          style={{ writingMode: 'vertical-rl', transform: before ? 'rotate(180deg)' : 'none' }}
        >
          {scene.eyebrow}
        </span>
      </div>
      <div className="grid lg:grid-cols-2 gap-10 lg:gap-16 items-center px-5 py-10 sm:p-14">
        {/* Phone */}
        <div
          className={`relative flex justify-center ${scene.reverse ? 'lg:order-2' : ''}`}
          style={{ perspective: '1200px' }}
        >
          {/* Glow blooms open behind the handset as it lands. */}
          <div
            className={`absolute inset-0 m-auto w-[70%] h-[70%] rounded-full blur-3xl bg-gradient-to-br ${scene.glow}`}
            style={{
              opacity: shown ? 1 : 0,
              transform: shown ? 'scale(1)' : 'scale(.4)',
              transition: 'opacity 900ms ease 120ms, transform 1100ms cubic-bezier(.16,.84,.34,1) 120ms',
            }}
          />
          <div
            className="relative w-[230px] sm:w-[280px] aspect-[9/19] rounded-[38px] border-[8px] border-ink overflow-hidden bg-ink"
            style={{
              opacity: shown ? 1 : 0,
              transform: shown ? 'none' : scene.enter,
              transformStyle: 'preserve-3d',
              boxShadow: '0 40px 70px -40px rgba(0,0,0,.7)',
              transition: `opacity 700ms ease,
                           transform 1100ms cubic-bezier(.16,.84,.34,1)`,
            }}
          >
            <img src={scene.image} alt="" className="absolute inset-0 w-full h-full object-cover" decoding="async" />
            {/* Screen sheen sweeps across once the handset is in place. */}
            <div
              className="absolute inset-0 bg-gradient-to-tr from-transparent via-white/25 to-transparent"
              style={{
                opacity: shown ? 0 : 0.9,
                transform: shown ? 'translateX(120%)' : 'translateX(-120%)',
                transition: 'transform 1400ms cubic-bezier(.16,.84,.34,1) 500ms, opacity 900ms ease 900ms',
              }}
            />
          </div>
        </div>

        {/* Copy */}
        <div className={`${dark ? 'text-white' : 'text-ink'} ${scene.reverse ? 'lg:order-1' : ''}`}>
          <span
            className={`text-sm font-semibold tracking-wider uppercase ${
              dark ? 'text-white/70' : 'text-primary'
            }`}
            style={step(0)}
          >
            {scene.eyebrow}
          </span>
          <h2
            className="text-3xl sm:text-4xl font-bold tracking-tightest mt-3 leading-[1.1]"
            style={step(1)}
          >
            {scene.title}
          </h2>
          <p
            className={`mt-5 leading-relaxed ${dark ? 'text-white/70' : 'text-ink-soft'}`}
            style={step(2)}
          >
            {scene.body}
          </p>
          <ul className="mt-8 space-y-4">
            {scene.points.map((pt, i) => (
              <li key={pt} className="flex items-start gap-4" style={step(3 + i)}>
                <div
                  className={`mt-0.5 w-6 h-6 rounded-full flex items-center justify-center flex-shrink-0 ${
                    dark ? 'bg-white/15' : 'bg-primary/10'
                  }`}
                  style={{
                    // Overshoot easing gives the tick a small pop as it lands.
                    transform: shown ? 'scale(1)' : 'scale(0)',
                    transition: `transform 600ms cubic-bezier(.34,1.56,.64,1) ${420 + i * 95}ms`,
                  }}
                >
                  <svg
                    className={`w-3.5 h-3.5 ${dark ? 'text-white' : 'text-primary'}`}
                    fill="currentColor"
                    viewBox="0 0 20 20"
                  >
                    <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
                  </svg>
                </div>
                <span className={dark ? 'text-white/75 leading-relaxed' : 'text-ink-soft leading-relaxed'}>
                  {pt}
                </span>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </article>
  )
}

/**
 * Coverage cards as a 3-column grid with hover effects.
 */
function CoverageGrid() {
  return (
    <section
      id="services"
      className="relative py-24 scroll-mt-16 bg-cream"
    >
      {/* A faint brand-tinted glow behind the heading keeps the white section
          from reading as an empty gap between the coloured bands. */}
      <div
        className="absolute inset-0 pointer-events-none opacity-[0.55]"
        style={{
          background:
            'radial-gradient(60% 45% at 50% 0%, rgba(61,17,82,0.09) 0%, transparent 70%)',
        }}
      />
      <div className="relative max-w-7xl mx-auto px-6">
        <div className="text-center max-w-3xl mx-auto">
          <span className="text-sm font-semibold tracking-wider uppercase text-primary">Services</span>
          <h2 className="text-4xl font-bold tracking-tight mt-3">
            What eKonnect covers
          </h2>
          <p className="mt-4 text-ink-soft leading-relaxed">
            Not an ambulance app. General emergency infrastructure any county,
            hospital or organisation can put its own crews behind.
          </p>
        </div>
        <div className="mt-16 grid sm:grid-cols-2 lg:grid-cols-3 gap-6">
          {PILLARS.map((p) => (
            <div
              key={p.title}
              className="group relative bg-cream-card rounded-3xl p-8 border border-ink/[0.07] hover:shadow-[0_20px_50px_-24px_rgba(28,10,38,0.22)] transition-all duration-500 hover:-translate-y-2"
            >
              <div className="absolute inset-0 rounded-3xl bg-gradient-to-br from-primary/0 to-primary/0 group-hover:from-primary/5 group-hover:to-purple-500/5 transition-all duration-500" />
              <div className="relative">
                <div className="w-14 h-14 rounded-2xl bg-primary/10 group-hover:bg-primary transition-colors duration-300 flex items-center justify-center">
                  <img
                    src={p.icon}
                    alt=""
                    loading="lazy"
                    decoding="async"
                    className="w-8 h-8 object-contain group-hover:brightness-0 group-hover:invert transition-all duration-300"
                  />
                </div>
                <h3 className="font-bold text-xl mt-6">{p.title}</h3>
                <p className="mt-3 text-ink-soft leading-relaxed">{p.body}</p>
                <div className="mt-6 pt-6 border-t border-ink/10">
                  <span className="text-xs font-semibold tracking-wide uppercase text-ink-mute">
                    {p.meta}
                  </span>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}

/**
 * The Android download, with feedback.
 *
 * A browser gives almost nothing away when a file starts downloading — on
 * Android it lands silently in the notification tray — so a 57MB build looks
 * for all the world like a button that did nothing. People then tap it again,
 * and again, each tap starting another copy.
 *
 * So the button says what happened, names the size up front, and stops
 * accepting taps for a few seconds. The anchor is never intercepted: the
 * browser still handles the download, this only narrates it.
 */
function DownloadButton() {
  const [state, setState] = useState('idle') // idle | starting | started
  const timers = useRef([])

  // Clear on unmount, or a timer fires against a component that is gone.
  useEffect(() => () => timers.current.forEach(clearTimeout), [])

  function begin() {
    if (state !== 'idle') return
    setState('starting')
    timers.current.push(setTimeout(() => setState('started'), 1400))
    // Back to idle eventually, so someone who genuinely needs it twice can.
    timers.current.push(setTimeout(() => setState('idle'), 15000))
  }

  const busy = state !== 'idle'

  return (
    <div className="flex-1 sm:flex-none">
      <a
        href="/downloads/ekonnect.apk"
        download
        onClick={begin}
        aria-disabled={busy}
        className={`store-badge w-full sm:w-auto ${
          busy ? 'pointer-events-none opacity-90' : ''
        }`}
      >
        <span className="w-7 h-7 flex-shrink-0 flex items-center justify-center">
          {state === 'starting' ? (
            <span className="w-5 h-5 rounded-full border-2 border-cream/30 border-t-cream animate-spin" />
          ) : state === 'started' ? (
            <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
            </svg>
          ) : (
            <svg className="w-7 h-7" viewBox="0 0 24 24" fill="none" stroke="currentColor"
                 strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 3v12m0 0l-4-4m4 4l4-4M4 17v2a2 2 0 002 2h12a2 2 0 002-2v-2" />
            </svg>
          )}
        </span>
        <span>
          <span className="block text-[10px] leading-none opacity-70">
            {state === 'idle' ? 'Direct download · 57 MB' : 'Android APK'}
          </span>
          <span className="block text-base font-semibold leading-tight mt-1">
            {state === 'starting' ? 'Starting…' : state === 'started' ? 'Download started' : 'Android APK'}
          </span>
        </span>
      </a>

      {/* Announced, not just drawn: the whole point is telling someone
          something happened when the screen otherwise looks unchanged. */}
      <p role="status" aria-live="polite" className="sr-only">
        {state === 'starting' ? 'Download starting' : state === 'started' ? 'Download started' : ''}
      </p>
    </div>
  )
}

/**
 * "Text me a link".
 *
 * No SMS provider is wired to this project yet, so this records the request
 * against `appLinkRequests` for an administrator to action rather than
 * pretending a message went out. The confirmation copy says exactly that —
 * a button that reports success for a message nobody sent is worse than no
 * button. Swap the write for a provider call when one is connected.
 */
function LinkToPhone() {
  const [digits, setDigits] = useState('')
  const [state, setState] = useState('idle') // idle | sending | done | error

  // Kenyan subscriber numbers are 9 digits after +254; people type them with a
  // leading 0 out of habit, so drop it rather than rejecting the input.
  const clean = digits.replace(/\D/g, '').replace(/^0+/, '').slice(0, 9)
  const valid = clean.length === 9

  async function submit(e) {
    e.preventDefault()
    if (!valid || state === 'sending') return
    setState('sending')
    try {
      await addDoc(collection(db, 'appLinkRequests'), {
        phone: `+254${clean}`,
        createdAt: serverTimestamp(),
        source: 'landing',
        sent: false,
      })
      setState('done')
    } catch {
      setState('error')
    }
  }

  return (
    <form onSubmit={submit} className="mt-10 max-w-md">
      <label
        htmlFor="link-phone"
        className="block text-xs font-semibold tracking-[0.14em] uppercase text-ink-mute mb-3"
      >
        Text me a link
      </label>
      <div className="flex items-stretch rounded-xl border border-ink/15 bg-cream-card overflow-hidden focus-within:border-primary transition-colors">
        <span className="flex items-center gap-2 pl-4 pr-3 text-sm font-medium text-ink-soft border-r border-ink/10">
          <span aria-hidden="true">🇰🇪</span> +254
        </span>
        <input
          id="link-phone"
          type="tel"
          inputMode="numeric"
          autoComplete="tel-national"
          value={digits}
          onChange={e => { setDigits(e.target.value); setState('idle') }}
          placeholder="712 123456"
          className="flex-1 min-w-0 px-4 py-3 bg-transparent text-sm outline-none placeholder:text-ink-mute"
        />
        <button
          type="submit"
          disabled={!valid || state === 'sending'}
          className="px-6 bg-ink text-cream text-sm font-semibold hover:bg-block-plum
                     disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
        >
          {state === 'sending' ? '…' : 'Send'}
        </button>
      </div>
      {state === 'done' && (
        <p className="mt-3 text-sm text-primary font-medium">
          Got it — we&apos;ll send the download link to +254 {clean} shortly.
        </p>
      )}
      {state === 'error' && (
        <p className="mt-3 text-sm text-emergency font-medium">
          Could not save that just now. Use the Android button above instead.
        </p>
      )}
    </form>
  )
}

/**
 * A device-framed screenshot cropped by the edge of its card.
 *
 * The reference never shows a screenshot floating whole inside a tile — it
 * runs the artwork off the card and lets the card clip it, which reads as a
 * window onto a bigger product rather than a picture pasted in. Positioning
 * and size come in through `className` so each card can place its own; the
 * card supplies `relative overflow-hidden` and does the clipping.
 */
function CardShot({ src, className = '', tilt = 0 }) {
  return (
    <div
      className={`pointer-events-none select-none absolute ${className}`}
      style={{ transform: `rotate(${tilt}deg)` }}
      aria-hidden="true"
    >
      <div className="h-full rounded-[26px] border-[7px] border-ink bg-ink overflow-hidden shadow-[0_30px_60px_-30px_rgba(0,0,0,0.75)]">
        {/* object-top: these are tall phone captures, and the useful part is
            always the top of the screen — better to crop the footer away than
            to squash the whole thing. */}
        <img src={src} alt="" loading="lazy" decoding="async" className="w-full h-full object-cover object-top" />
      </div>
    </div>
  )
}

/** Bar heights for the triage waveform — irregular on purpose, so it reads as
 *  speech rather than an equaliser test pattern. */
const WAVE = [30, 62, 44, 88, 56, 100, 40, 74, 34, 92, 50, 68, 28, 80, 46]

/**
 * Voice triage has no screenshot worth cropping — the moment that sells it is
 * the app listening — so this draws the listening state instead of shooting it.
 */
function VoiceMock() {
  return (
    <div className="relative z-10 mt-8 rounded-2xl bg-black/25 border border-white/10 p-4">
      <div className="flex items-center gap-3">
        <span className="w-10 h-10 rounded-full bg-block-coral flex items-center justify-center flex-shrink-0">
          <img src="/assets/mic.svg" alt="" className="w-4 h-4 brightness-0 invert" decoding="async" />
        </span>
        <div className="flex items-end gap-[3px] h-9 flex-1">
          {WAVE.map((h, i) => (
            <span
              key={i}
              className="flex-1 rounded-full bg-white/45"
              style={{
                height: `${h}%`,
                // Bars are bottom-aligned, so they must grow upward — the
                // default centre origin would shrink them from both ends.
                transformOrigin: 'bottom',
                animation: `ek-wave 1.1s ease-in-out ${i * 70}ms infinite alternate`,
              }}
            />
          ))}
        </div>
      </div>
      <div className="mt-4 flex items-center gap-2 text-[11px] font-semibold tracking-wider uppercase text-white/40">
        <span className="w-1.5 h-1.5 rounded-full bg-block-coral animate-pulse" />
        Drafting report
      </div>
      <div className="mt-3 space-y-2">
        <div className="h-2 rounded-full bg-white/15 w-full" />
        <div className="h-2 rounded-full bg-white/15 w-4/5" />
        <div className="h-2 rounded-full bg-white/15 w-2/3" />
      </div>
    </div>
  )
}

function Band({ image, eyebrow, title, body, points, reverse = false }) {
  return (
    <section className="max-w-7xl mx-auto px-6 py-16">
      <div className={`grid lg:grid-cols-2 gap-16 items-center ${reverse ? 'lg:[&>*:first-child]:order-2' : ''}`}>
        <div className="flex justify-center">
          <div className="rounded-[28px] border-[7px] border-ink overflow-hidden shadow-xl max-w-[280px]">
            <img
              src={image}
              alt=""
              loading="lazy"
            decoding="async"
              className="w-full block aspect-[9/19] object-cover object-top"
            />
          </div>
        </div>
        <div>
          <span className="text-sm font-semibold tracking-wider uppercase text-primary">
            {eyebrow}
          </span>
          <h2 className="text-4xl font-bold tracking-tight mt-3 leading-tight">{title}</h2>
          <p className="mt-4 text-ink-soft leading-relaxed">{body}</p>
          <ul className="mt-6 space-y-4">
            {points.map(p => (
              <li key={p} className="flex items-start gap-4">
                <div className="mt-1 w-5 h-5 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
                  <svg className="w-3 h-3 text-primary" fill="currentColor" viewBox="0 0 20 20">
                    <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
                  </svg>
                </div>
                <span className="text-ink-soft leading-relaxed">{p}</span>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </section>
  )
}

function FooterCol({ title, links, routed = false }) {
  return (
    <div>
      <h4 className="font-bold text-sm">{title}</h4>
      <ul className="mt-4 space-y-3">
        {links.map(([label, href]) => (
          <li key={label}>
            {routed ? (
              <Link to={href} className="text-sm text-ink-mute hover:text-white transition-colors">
                {label}
              </Link>
            ) : (
              <a href={href} className="text-sm text-ink-mute hover:text-white transition-colors">
                {label}
              </a>
            )}
          </li>
        ))}
      </ul>
    </div>
  )
}