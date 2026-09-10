import { useState } from 'react'
import { Link } from 'react-router-dom'

/**
 * The tester's guide, at /guide.
 *
 * One page that answers "how do I try this" end to end: get the app, sign in
 * as either side of an emergency, run the network from the console, and see
 * how a responder's reach is decided. It carries the shared demo credentials,
 * so it is the page the landing prompt points people at.
 *
 * Order follows what someone actually does, not how the system is built.
 */

/** A credential pair. Mono so l/1 and O/0 survive being retyped. */
function Credential({ label, value }) {
  const [copied, setCopied] = useState(false)

  async function copy() {
    try {
      await navigator.clipboard.writeText(value)
      setCopied(true)
      setTimeout(() => setCopied(false), 1400)
    } catch {
      // Clipboard can be refused; the value is selectable either way.
    }
  }

  return (
    <div className="flex items-center gap-3 py-2 border-t border-ink/[0.07] first:border-t-0">
      <span className="text-[11px] font-semibold tracking-wider uppercase text-ink-mute w-[4.5rem] shrink-0">
        {label}
      </span>
      <code className="flex-1 min-w-0 font-mono text-[13px] text-ink overflow-x-auto whitespace-nowrap">
        {value}
      </code>
      <button
        onClick={copy}
        className={`shrink-0 text-[11px] font-semibold px-2.5 py-1 rounded-lg border transition-colors ${
          copied
            ? 'bg-ink text-cream border-ink'
            : 'border-ink/15 text-ink-soft hover:border-ink/40 hover:text-ink'
        }`}
      >
        {copied ? 'Copied' : 'Copy'}
      </button>
    </div>
  )
}

/** A bordered card carrying a title, a description and the route that reaches it. */
function Card({ title, children, route }) {
  return (
    <div className="rounded-2xl border border-ink/10 bg-cream-card p-6 flex flex-col gap-2">
      <h3 className="font-bold text-lg tracking-tight">{title}</h3>
      <p className="text-sm text-ink-soft leading-relaxed">{children}</p>
      {route && (
        <code className="mt-auto pt-2 font-mono text-xs text-ink-mute break-all">
          {route}
        </code>
      )}
    </div>
  )
}

/** The two or three things people get wrong, said plainly. */
function Note({ marker, children }) {
  return (
    <div className="rounded-2xl border border-block-coral/35 bg-block-coral/[0.06] p-5">
      <span className="block text-[11px] font-bold tracking-[0.14em] uppercase text-block-coral">
        {marker}
      </span>
      <p className="mt-1.5 text-sm text-ink leading-relaxed">{children}</p>
    </div>
  )
}

function Section({ eyebrow, title, children }) {
  return (
    <section className="pt-14 first:pt-0">
      <span className="block text-xs font-semibold tracking-[0.16em] uppercase text-primary">
        {eyebrow}
      </span>
      <h2 className="lp-display text-3xl sm:text-4xl mt-2.5">{title}</h2>
      <div className="mt-6 flex flex-col gap-5">{children}</div>
    </section>
  )
}

export default function Guide() {
  return (
    <div className="min-h-screen bg-cream text-ink font-sans antialiased">
      <header className="sticky top-0 z-40 bg-cream/85 backdrop-blur-xl border-b border-ink/[0.06]">
        <div className="px-4 sm:px-8 lg:px-12 h-20 flex items-center justify-between">
          <Link to="/" className="flex items-center gap-2.5">
            <img src="/assets/logo-purple.png" alt="" className="w-9 h-9 object-contain" />
            <span className="font-bold text-xl tracking-tight">eKonnect</span>
          </Link>
          <Link
            to="/"
            className="text-sm font-semibold text-ink-soft hover:text-ink transition-colors"
          >
            Back to site
          </Link>
        </div>
      </header>

      <div className="px-4 sm:px-8 lg:px-12 pb-24 pt-12">
        <div className="max-w-3xl">
          <span className="block text-xs font-semibold tracking-[0.16em] uppercase text-primary">
            Test access
          </span>
          <h1 className="lp-display text-4xl sm:text-5xl mt-3">How to try eKonnect</h1>
          <p className="mt-4 text-ink-soft leading-relaxed max-w-2xl">
            eKonnect runs in two places: the Android app people carry, and the web
            console the network is run from. Both start here, and they share one
            set of test accounts.
          </p>

          {/* ── 1. Get the app ─────────────────────────────── */}
          <Section eyebrow="Step one" title="Get the app">
            <p className="text-ink-soft leading-relaxed">
              Download it from{' '}
              <a href="/#get" className="text-ink font-semibold underline underline-offset-2">
                the download section
              </a>{' '}
              on the home page, and allow the prompts as they come.
            </p>
            <Note marker="Before you install">
              It is not on the Play Store yet, so Android will warn you against
              installing it. Choose <strong className="font-semibold">Install anyway</strong> —
              the warning is about the source, not the app.
            </Note>
          </Section>

          {/* ── 2. Try the app ─────────────────────────────── */}
          <Section eyebrow="Step two" title="Try both sides of an emergency">
            <p className="text-ink-soft leading-relaxed">
              The same app serves the person in trouble and the crew answering.
              Sign in as either — or as both, on two phones, to watch one call
              from end to end.
            </p>

            <div className="grid sm:grid-cols-2 gap-5">
              <div className="rounded-2xl border border-ink/10 bg-cream-card p-6">
                <h3 className="font-bold text-lg tracking-tight">As a user</h3>
                <p className="text-sm text-ink-mute mb-3">raising an emergency</p>
                <Credential label="Email" value="phabianbenard2019@gmail.com" />
                <Credential label="Password" value="Phabby@254" />
                <ol className="mt-4 space-y-2 text-sm text-ink-soft leading-relaxed list-decimal pl-4 marker:text-primary marker:font-bold">
                  <li>Sign in with Google in one tap, or with the details above.</li>
                  <li>
                    Pick an emergency type, then <strong className="font-semibold text-ink">hold</strong>{' '}
                    the SOS button for a second — the hold is the confirmation.
                  </li>
                  <li>Watch the map: your face and the responder&rsquo;s are the two pins.</li>
                  <li>Drag the sheet down for the map, up for the crew&rsquo;s details.</li>
                </ol>
              </div>

              <div className="rounded-2xl border border-ink/10 bg-cream-card p-6">
                <h3 className="font-bold text-lg tracking-tight">As a responder</h3>
                <p className="text-sm text-ink-mute mb-3">answering one</p>
                <Credential label="Email" value="tafitiinnovationhub@gmail.com" />
                <Credential label="Password" value="Phabby@254" />
                <ol className="mt-4 space-y-2 text-sm text-ink-soft leading-relaxed list-decimal pl-4 marker:text-primary marker:font-bold">
                  <li>Sign in, then switch to responder mode.</li>
                  <li>
                    Turn <strong className="font-semibold text-ink">Accepting emergency calls</strong>{' '}
                    on — until that switch is on, nothing reaches you.
                  </li>
                  <li>Accept the incoming call, then work it through to resolved.</li>
                  <li>This account is already verified, so it can go on duty straight away.</li>
                </ol>
              </div>
            </div>

            <Note marker="Live">
              An SOS raised here reaches real responder accounts. Cancel anything
              you start, and use <strong className="font-semibold">Call 999</strong> only
              in a genuine emergency.
            </Note>
          </Section>

          {/* ── 3. The console ─────────────────────────────── */}
          <Section eyebrow="Step three" title="Run it from the console">
            <p className="text-ink-soft leading-relaxed">
              One sign-in page for both roles —{' '}
              <Link to="/login" className="text-ink font-semibold underline underline-offset-2">
                ekonnectapp.web.app/login
              </Link>
              . Where you land is decided by the account, not by the link.
            </p>

            <div className="grid sm:grid-cols-2 gap-5">
              <div className="rounded-2xl border border-ink/10 bg-cream-card p-6">
                <h3 className="font-bold text-lg tracking-tight">Care Point</h3>
                <p className="text-sm text-ink-mute mb-3">Oasis hospital &middot; lands on /portal</p>
                <Credential label="Email" value="phabianbenard2019@gmail.com" />
                <Credential label="Password" value="Phabby@254" />
                <p className="mt-4 text-sm text-ink-soft leading-relaxed">
                  One facility&rsquo;s own view: its fleet, crew, jobs, subscribers
                  and settings — nobody else&rsquo;s data.
                </p>
              </div>

              <div className="rounded-2xl border border-ink/10 bg-cream-card p-6">
                <h3 className="font-bold text-lg tracking-tight">Network administrator</h3>
                <p className="text-sm text-ink-mute mb-3">lands on /dashboard</p>
                <Credential label="Email" value="ekonnectadmin@gmail.com" />
                <Credential label="Password" value="Ekonnect@2026" />
                <p className="mt-4 text-sm text-ink-soft leading-relaxed">
                  Every incident, responder and Care Point across the network — and
                  where responder applications are approved or declined.
                </p>
              </div>
            </div>
          </Section>

          {/* ── 4. Registering ─────────────────────────────── */}
          <Section eyebrow="Step four" title="Register a facility or a responder">
            <p className="text-ink-soft leading-relaxed">
              <strong className="font-semibold text-ink">A Care Point</strong> — a hospital,
              clinic or ambulance service — registers itself:
            </p>
            <Card title="Register a Care Point" route="ekonnectapp.web.app/register">
              Fills in the facility, its location, the emergencies it answers and
              its fleet. Choose &ldquo;Who you answer for&rdquo; here: Public or Private.
            </Card>

            <p className="text-ink-soft leading-relaxed pt-1">
              <strong className="font-semibold text-ink">A responder</strong> — a driver or
              practitioner — can be registered two ways:
            </p>
            <div className="grid sm:grid-cols-2 gap-5">
              <Card title="By their Care Point" route="ekonnectapp.web.app/login → /portal">
                From the portal: Crew → Register crew. The facility submits someone
                it employs, and they inherit that facility&rsquo;s reach.
              </Card>
              <Card title="On their own" route="ekonnectapp.web.app/apply">
                They apply themselves and either tag one of the verified Care
                Points, or choose &ldquo;I work independently&rdquo;.
              </Card>
            </div>

            <p className="text-sm text-ink-soft leading-relaxed">
              Either way an administrator verifies the licence before that account
              can go on duty. Until then the duty switch stays locked.
            </p>
          </Section>

          {/* ── 5. Reach ───────────────────────────────────── */}
          <Section eyebrow="Step five" title="Who a responder reaches">
            <p className="text-ink-soft leading-relaxed">
              Reach follows the facility, not the person. An independent responder
              is on the open network; one attached to a Care Point inherits that
              facility&rsquo;s setting.
            </p>
            <div className="grid sm:grid-cols-2 gap-5">
              <Card title="Public" route="the open network">
                Answers any nearby emergency, whoever raised it. Independent
                responders are always public.
              </Card>
              <Card title="Private" route="one Care Point’s clients">
                Answers only clients registered with that facility — the
                subscribers on its books.
              </Card>
            </div>
            <Note marker="Trade-off">
              A private Care Point{' '}
              <strong className="font-semibold">stops receiving public emergencies entirely</strong>.
              Its crews will not see a passing road accident — only calls from its
              own subscribers. That exclusivity is what clients pay for.
            </Note>
          </Section>

          {/* ── Footer ─────────────────────────────────────── */}
          <div className="mt-16 pt-8 border-t border-ink/10 text-sm text-ink-mute flex flex-col gap-2">
            <p>
              These are shared demo accounts. Please don&rsquo;t enter real personal
              or medical details into them.
            </p>
            <p>
              <Link to="/privacy" className="text-ink underline underline-offset-2">
                Terms &amp; privacy
              </Link>
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}
