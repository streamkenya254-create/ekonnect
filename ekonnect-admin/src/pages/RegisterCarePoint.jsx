import { useState } from 'react'
import { Link } from 'react-router-dom'
import { collection, addDoc, serverTimestamp } from 'firebase/firestore'
import { db } from '../firebase'
import CarePointForm from '../components/CarePointForm'
import { emptyCarePoint, validateCarePoint, STEPS, typeLabel } from '../data/carePoints'

/**
 * Public Care Point registration at `/register`.
 *
 * A hospital cannot put itself on the live network — that is the whole basis
 * of a verified system — so this writes an application to `carePointApplications`
 * for an administrator to review. Nothing here creates a dispatchable record.
 *
 * Uses the same field definitions and validation as the console
 * (`components/CarePointForm`), so an application cannot be accepted through
 * this door in a shape the console would reject.
 */
export default function RegisterCarePoint() {
  const [cp, setCp] = useState({ ...emptyCarePoint })
  const [step, setStep] = useState(0)
  const [showErrors, setShowErrors] = useState(false)
  const [state, setState] = useState('editing') // editing | sending | done | error
  const [refId, setRefId] = useState('')

  const stepErrors = validateCarePoint(cp, step)
  const allErrors = validateCarePoint(cp)
  const last = step === STEPS.length - 1

  function next() {
    if (Object.keys(stepErrors).length > 0) { setShowErrors(true); return }
    setShowErrors(false)
    setStep(s => s + 1)
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  function back() {
    setShowErrors(false)
    setStep(s => s - 1)
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  async function submit() {
    if (Object.keys(allErrors).length > 0) {
      setShowErrors(true)
      const bad = STEPS.findIndex((_, i) => Object.keys(validateCarePoint(cp, i)).length > 0)
      if (bad >= 0) setStep(bad)
      return
    }
    setState('sending')
    try {
      const ref = await addDoc(collection(db, 'carePointApplications'), {
        ...cp,
        lat: parseFloat(cp.lat),
        lng: parseFloat(cp.lng),
        bedCapacity: cp.bedCapacity === '' ? null : Number(cp.bedCapacity),
        ambulanceCount: cp.ambulanceCount === '' ? null : Number(cp.ambulanceCount),
        // Applications are never dispatchable. An administrator promotes one
        // into the `teams` collection after checking the licence.
        status: 'pending',
        submittedAt: serverTimestamp(),
        source: 'public-registration',
      })
      setRefId(ref.id.slice(-6).toUpperCase())
      setState('done')
      window.scrollTo({ top: 0, behavior: 'smooth' })
    } catch {
      setState('error')
    }
  }

  if (state === 'done') return <Submitted cp={cp} refId={refId} />

  return (
    <div className="min-h-screen bg-cream text-ink font-sans antialiased">
      <Header />

      {/* Full-bleed with a small gutter. The form has five steps and a lot of
          fields; a narrow centred column made every step scroll when the
          viewport had room to show it whole. */}
      <div className="px-4 sm:px-8 lg:px-12 pb-20">
        <div className="grid lg:grid-cols-[300px_minmax(0,1fr)] xl:grid-cols-[360px_minmax(0,1fr)] gap-8 xl:gap-14 pt-10 lg:pt-14">

          {/* ── Rail: what this is, and where you are in it ───────────────── */}
          <aside className="lg:sticky lg:top-28 lg:self-start">
            <span className="block text-xs font-semibold tracking-[0.16em] uppercase text-primary">
              Join the network
            </span>
            <h1 className="lp-display text-3xl xl:text-4xl mt-3">
              Register a Care Point
            </h1>
            <p className="mt-4 text-sm text-ink-soft leading-relaxed">
              Hospitals, clinics, fire stations and rescue services. Once
              verified, your crews answer emergencies under your name and other
              crews can refer patients to you — every leg timestamped.
            </p>

            {/* Vertical on wide screens, a horizontal bar on phones where a
                five-item list would push the fields off the first screen. */}
            <ol className="hidden lg:block mt-10 space-y-1">
              {STEPS.map((s, i) => {
                const done = i < step
                const now = i === step
                return (
                  <li key={s.title}>
                    <button
                      onClick={() => done && setStep(i)}
                      disabled={!done && !now}
                      className={`w-full text-left flex items-start gap-3.5 rounded-xl px-3 py-2.5 transition-colors ${
                        now ? 'bg-cream-card' : done ? 'hover:bg-cream-card/60' : ''
                      } ${done ? 'cursor-pointer' : 'cursor-default'}`}
                    >
                      <span className={`mt-0.5 w-6 h-6 rounded-full flex items-center justify-center text-[11px] font-bold flex-shrink-0 transition-colors ${
                        now ? 'bg-primary text-white'
                          : done ? 'bg-primary/15 text-primary'
                          : 'bg-ink/[0.07] text-ink-mute'
                      }`}>
                        {done ? '✓' : i + 1}
                      </span>
                      <span className="min-w-0">
                        <span className={`block text-sm font-semibold ${now ? 'text-ink' : done ? 'text-ink-soft' : 'text-ink-mute'}`}>
                          {s.title}
                        </span>
                        <span className="block text-xs text-ink-mute mt-0.5 leading-snug">{s.sub}</span>
                      </span>
                    </button>
                  </li>
                )
              })}
            </ol>

            <p className="hidden lg:block mt-8 text-xs text-ink-mute leading-relaxed">
              Submitting does not put you on the live network. An administrator
              checks your registration details first — no facility can add
              itself, which is what makes the verified badge worth anything.
            </p>
          </aside>

          {/* ── Form ─────────────────────────────────────────────────────── */}
          <div className="min-w-0">
            {/* Phone stepper: the rail's list collapses to this. */}
            <div className="lg:hidden flex gap-1.5 mb-7">
              {STEPS.map((s, i) => (
                <span
                  key={s.title}
                  className={`h-1.5 flex-1 rounded-full transition-colors duration-500 ${
                    i <= step ? 'bg-primary' : 'bg-ink/10'
                  }`}
                />
              ))}
            </div>

            <div className="bg-cream-card border border-ink/[0.07] rounded-3xl p-6 sm:p-9 xl:p-12 shadow-[0_20px_50px_-30px_rgba(28,10,38,0.25)]">
              <div className="flex items-baseline justify-between gap-4 mb-8">
                <div>
                  <p className="text-xs font-semibold tracking-[0.16em] uppercase text-ink-mute">
                    Step {step + 1} of {STEPS.length}
                  </p>
                  <h2 className="text-2xl xl:text-3xl font-bold tracking-tight mt-1">
                    {STEPS[step].sub}
                  </h2>
                </div>
                <span className="hidden sm:block text-sm font-semibold text-ink-mute flex-shrink-0">
                  {STEPS[step].title}
                </span>
              </div>

              <CarePointForm
                value={cp}
                onChange={setCp}
                step={step}
                errors={showErrors ? stepErrors : {}}
                tone="landing"
                wide
              />

              {last && <ReviewSummary cp={cp} />}

              {state === 'error' && (
                <p className="mt-6 text-sm text-emergency font-medium">
                  Could not send that. Check your connection and try again — or
                  email the details to us and we will register you by hand.
                </p>
              )}

              <div className="flex items-center gap-3 mt-10 pt-7 border-t border-ink/[0.07]">
                {step > 0 && <button onClick={back} className="lp-btn-ghost">Back</button>}
                <div className="flex-1" />
                {!last ? (
                  <button onClick={next} className="lp-btn">
                    Continue
                    <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor"
                         strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M5 12h14m0 0l-6-6m6 6l-6 6" />
                    </svg>
                  </button>
                ) : (
                  <button onClick={submit} disabled={state === 'sending'} className="lp-btn disabled:opacity-40">
                    {state === 'sending' ? 'Sending…' : 'Submit application'}
                  </button>
                )}
              </div>
            </div>

            <p className="lg:hidden mt-6 text-xs text-ink-mute leading-relaxed">
              Submitting does not put you on the live network. An administrator
              checks your registration details first.
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}

/* ── Chrome ──────────────────────────────────────────────────────────────── */

function Header() {
  return (
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
  )
}

/**
 * Last-step recap. Everything entered, in one place, before it is sent —
 * a facility is committing to what a crew will rely on at 3am, and scrolling
 * back through five steps to check is not a review.
 */
function ReviewSummary({ cp }) {
  const rows = [
    ['Facility', `${cp.name} · ${typeLabel(cp.type)}`],
    ['Licence', cp.registrationNumber || 'Not provided'],
    ['Contact', [cp.contactName, cp.contactPhone].filter(Boolean).join(' · ')],
    ['Dispatch line', cp.dispatchPhone || 'Same as main phone'],
    ['Location', [cp.town, cp.county].filter(Boolean).join(', ')],
    ['Coordinates', `${cp.lat}, ${cp.lng}`],
    ['Answers', (cp.respondsTo ?? []).join(', ') || '—'],
    ['Services', (cp.services ?? []).length ? `${cp.services.length} listed` : 'None listed'],
    ['Network', cp.visibility === 'private' ? 'Private clients only' : 'Public network'],
  ]
  return (
    <div className="mt-9 pt-7 border-t border-ink/[0.07]">
      <h3 className="text-sm font-semibold tracking-tight mb-5">Check before sending</h3>

      {(cp.coverImage || cp.logo) && (
        <div className="relative rounded-2xl overflow-hidden mb-7 border border-ink/[0.07]">
          {cp.coverImage
            ? <img src={cp.coverImage} alt="" className="w-full h-40 object-cover" />
            : <div className="w-full h-40 bg-cream-deep" />}
          <div className="absolute inset-0 bg-gradient-to-t from-ink/80 to-transparent" />
          <div className="absolute bottom-4 left-4 flex items-center gap-3">
            {cp.logo && (
              <img src={cp.logo} alt="" className="w-12 h-12 rounded-xl object-contain bg-white p-1" />
            )}
            <div>
              <p className="text-white font-bold tracking-tight">{cp.name}</p>
              <p className="text-white/70 text-xs">{typeLabel(cp.type)}</p>
            </div>
          </div>
        </div>
      )}

      <dl className="grid sm:grid-cols-2 xl:grid-cols-3 gap-x-10 gap-y-4">
        {rows.map(([k, v]) => (
          <div key={k} className="min-w-0">
            <dt className="text-[11px] font-semibold tracking-wider uppercase text-ink-mute">{k}</dt>
            <dd className="text-sm text-ink-soft break-words mt-1">{v || '—'}</dd>
          </div>
        ))}
      </dl>
    </div>
  )
}

function Submitted({ cp, refId }) {
  return (
    <div className="min-h-screen bg-cream text-ink font-sans antialiased">
      <Header />
      <div className="max-w-2xl mx-auto px-6 py-24 text-center">
        <div className="w-20 h-20 rounded-full bg-primary/10 flex items-center justify-center mx-auto">
          <svg className="w-9 h-9 text-primary" fill="currentColor" viewBox="0 0 20 20">
            <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
          </svg>
        </div>
        <h1 className="lp-display text-4xl mt-8">Application received</h1>
        <p className="mt-4 text-ink-soft leading-relaxed">
          {cp.name} is in the queue for verification. Your reference is{' '}
          <span className="font-mono font-semibold text-ink">{refId}</span> — quote
          it if you need to chase this up.
        </p>
        <div className="mt-10 bg-cream-card border border-ink/[0.07] rounded-3xl p-8 text-left">
          <h2 className="font-bold tracking-tight">What happens next</h2>
          <ol className="mt-5 space-y-4">
            {[
              'An administrator checks your registration or licence number against the facility register.',
              'We call the contact number you gave to confirm someone there is expecting us.',
              'Once verified, your Care Point goes live and you can attach responders to it.',
            ].map((s, i) => (
              <li key={s} className="flex gap-4 text-sm">
                <span className="w-6 h-6 rounded-full bg-primary/10 text-primary font-bold text-xs flex items-center justify-center flex-shrink-0">
                  {i + 1}
                </span>
                <span className="text-ink-soft leading-relaxed">{s}</span>
              </li>
            ))}
          </ol>
        </div>
        <Link to="/" className="lp-btn mt-10">
          Back to eKonnect
          <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor"
               strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M5 12h14m0 0l-6-6m6 6l-6 6" />
          </svg>
        </Link>
      </div>
    </div>
  )
}
