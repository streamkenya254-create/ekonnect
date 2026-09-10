import { Link } from 'react-router-dom'

/**
 * Terms and privacy, at /privacy.
 *
 * The app's sign-up tick links straight here, so this is the only place the
 * policy lives — it is not duplicated into a screen inside the app that would
 * then drift from it.
 *
 * Written plainly and specifically. A policy for an app that handles a
 * person's location during a medical emergency should say what happens to that
 * location, not hide it behind boilerplate.
 */
export default function Privacy() {
  const updated = 'August 2026'

  return (
    <div className="min-h-screen bg-cream text-ink font-sans antialiased">
      <header className="sticky top-0 z-40 bg-cream/85 backdrop-blur-xl border-b border-ink/[0.06]">
        <div className="px-4 sm:px-8 lg:px-12 h-20 flex items-center justify-between">
          <Link to="/" className="flex items-center gap-2.5">
            <img src="/assets/logo-purple.png" alt="" className="w-9 h-9 object-contain" />
            <span className="font-bold text-xl tracking-tight">eKonnect</span>
          </Link>
          <Link to="/" className="text-sm font-semibold text-ink-soft hover:text-ink transition-colors">
            Back to site
          </Link>
        </div>
      </header>

      <div className="px-4 sm:px-8 lg:px-12 pb-24 pt-12">
        <div className="max-w-3xl">
          <span className="block text-xs font-semibold tracking-[0.16em] uppercase text-primary">
            Legal
          </span>
          <h1 className="lp-display text-4xl sm:text-5xl mt-3">Terms &amp; Privacy</h1>
          <p className="mt-4 text-ink-soft leading-relaxed">
            Last updated {updated}. These terms cover the eKonnect app and the
            eKonnect console at ekonnectapp.web.app.
          </p>

          <Section title="What eKonnect is">
            <P>
              eKonnect connects a person in an emergency to verified responders —
              ambulance crews and medical practitioners — and to the facilities
              that employ them.
            </P>
            <Callout>
              eKonnect is a faster route to help, never a replacement for one.
              In a life-threatening emergency call 999 as well as sending an
              SOS. We cannot guarantee that a responder is available, or how
              quickly one will reach you.
            </Callout>
          </Section>

          <Section title="What we collect">
            <Bullets items={[
              ['Your name, phone number and email', 'so a responder can identify and reach you.'],
              ['Your location when you raise an SOS', 'this is the whole point — a responder cannot come to you without it.'],
              ['Your live location while an incident is active', 'shared with the responder assigned to you, and stopped when the incident closes.'],
              ['A profile photo, if you add one', 'shown to the responder who accepts your call.'],
              ['What you type or say when reporting', 'including a voice description, which is transcribed and summarised for the responder.'],
              ['Your incident history', 'the record of what happened, kept so you and the responding facility can refer back to it.'],
            ]} />
          </Section>

          <Section title="Who can see it">
            <Bullets items={[
              ['The responder who accepts your emergency', 'name, phone, location, and what you reported.'],
              ['Their Care Point', 'the facility they answer for sees the job in their record.'],
              ['eKonnect administrators', 'for verification, safety and resolving disputes.'],
              ['A facility you are referred to', 'when a crew transports you onward.'],
            ]} />
            <P>
              If you register with a private provider, your emergencies are
              routed to that provider first and are not visible to the public
              responder network during that period. You can leave a provider at
              any time from My Providers in the app.
            </P>
            <P>
              We do not sell your data, and we do not use it for advertising.
            </P>
          </Section>

          <Section title="Location, specifically">
            <P>
              Your location is read when you press SOS, and again while an
              incident is active so the responder can navigate to you and you
              can watch them approach. It stops when the incident is resolved or
              cancelled. eKonnect does not track your location in the
              background at any other time.
            </P>
          </Section>

          <Section title="Responders and facilities">
            <P>
              Nobody puts themselves on the network. Responders apply with a
              licence number and are verified by an administrator before they
              can answer a call. Care Points are checked against their
              registration before they are listed. A verified badge means
              somebody checked — it is not a guarantee of the care given.
            </P>
          </Section>

          <Section title="Your choices">
            <Bullets items={[
              ['Delete your account', 'email us and we will remove your profile. Incident records are kept where a facility is required to retain them.'],
              ['Turn off location', 'you may, but SOS cannot function without it.'],
              ['Leave a private provider', 'from My Providers, at any time.'],
            ]} />
          </Section>

          <Section title="Contact">
            <P>
              Questions, corrections or deletion requests:{' '}
              <a href="mailto:ekonnectapp@gmail.com"
                 className="font-semibold text-primary hover:underline">
                ekonnectapp@gmail.com
              </a>
            </P>
            <P>
              eKonnect is built by{' '}
              <a href="https://tafitirnihub.co.ke" target="_blank" rel="noopener noreferrer"
                 className="font-semibold text-primary hover:underline">
                Tafiti Research &amp; Innovation Hub
              </a>.
            </P>
          </Section>
        </div>
      </div>
    </div>
  )
}

function Section({ title, children }) {
  return (
    <section className="mt-12 pt-10 border-t border-ink/[0.08]">
      <h2 className="text-2xl font-bold tracking-tightest">{title}</h2>
      <div className="mt-4 space-y-4">{children}</div>
    </section>
  )
}

function P({ children }) {
  return <p className="text-ink-soft leading-relaxed">{children}</p>
}

function Bullets({ items }) {
  return (
    <ul className="space-y-3">
      {items.map(([term, detail]) => (
        <li key={term} className="flex gap-3">
          <span className="mt-2 w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0" />
          <span className="text-ink-soft leading-relaxed">
            <strong className="text-ink font-semibold">{term}</strong> — {detail}
          </span>
        </li>
      ))}
    </ul>
  )
}

/** The one thing on this page nobody should be able to skim past. */
function Callout({ children }) {
  return (
    <div className="rounded-2xl border border-emergency/25 bg-emergency/[0.06] px-5 py-4">
      <p className="text-sm text-ink-soft leading-relaxed">{children}</p>
    </div>
  )
}
