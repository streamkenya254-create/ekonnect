import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { collection, addDoc, getDocs, query, where, serverTimestamp } from 'firebase/firestore'
import { db } from '../firebase'
import {
  AFFILIATIONS, RESPONDER_ROLES, emptyResponderApplication,
  validateResponderApplication, APPLICATION_STEPS, APPLICATION_SOURCES,
} from '../data/responders'
import { COUNTIES } from '../data/carePoints'

/**
 * Public responder application at `/apply`.
 *
 * Responders are no longer promoted out of ordinary app accounts. Being a
 * responder means a licence somebody checked, so it starts with an application
 * carrying one — whether the person works for a Care Point or by themselves.
 */
export default function RegisterResponder() {
  const [a, setA] = useState({ ...emptyResponderApplication })
  const [step, setStep] = useState(0)
  const [showErrors, setShowErrors] = useState(false)
  const [state, setState] = useState('editing')
  const [refId, setRefId] = useState('')
  const [carePoints, setCarePoints] = useState([])

  // Only verified Care Points are offered. Letting someone claim to work for
  // an unverified facility would launder trust the facility has not earned.
  //
  // The filter is not just for correctness: the rules only permit a signed-out
  // reader to see verified facilities, and Firestore requires the query to
  // carry that same condition. Dropping the `where` breaks the whole listing.
  const [cpState, setCpState] = useState('loading') // loading | ready | error
  useEffect(() => {
    getDocs(query(collection(db, 'teams'), where('verificationStatus', '==', 'verified')))
      .then(snap => {
        setCarePoints(snap.docs.map(d => ({ id: d.id, ...d.data() })))
        setCpState('ready')
      })
      // Failing quietly here once told applicants there were no verified Care
      // Points when in fact the read had been denied — which is a different
      // problem with a different fix, and they had no way to tell.
      .catch(() => setCpState('error'))
  }, [])

  const stepErrors = validateResponderApplication(a, step)
  const allErrors = validateResponderApplication(a)
  const last = step === APPLICATION_STEPS.length - 1

  function next() {
    if (Object.keys(stepErrors).length) { setShowErrors(true); return }
    setShowErrors(false)
    setStep(s => s + 1)
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  async function submit() {
    if (Object.keys(allErrors).length) {
      setShowErrors(true)
      const bad = APPLICATION_STEPS.findIndex(
        (_, i) => Object.keys(validateResponderApplication(a, i)).length > 0,
      )
      if (bad >= 0) setStep(bad)
      return
    }
    setState('sending')
    try {
      const ref = await addDoc(collection(db, 'responderApplications'), {
        ...a,
        email: a.email.trim().toLowerCase(),
        teamId: a.affiliation === 'care_point' ? a.teamId : '',
        teamName: a.affiliation === 'care_point'
          ? (carePoints.find(c => c.id === a.teamId)?.name ?? '')
          : '',
        status: 'pending',
        source: APPLICATION_SOURCES.public,
        submittedAt: serverTimestamp(),
      })
      setRefId(ref.id.slice(-6).toUpperCase())
      setState('done')
      window.scrollTo({ top: 0, behavior: 'smooth' })
    } catch {
      setState('error')
    }
  }

  if (state === 'done') return <Submitted a={a} refId={refId} />

  return (
    <div className="min-h-screen bg-cream text-ink font-sans antialiased">
      <Header />
      <div className="px-4 sm:px-8 lg:px-12 pb-20">
        <div className="grid lg:grid-cols-[300px_minmax(0,1fr)] xl:grid-cols-[360px_minmax(0,1fr)] gap-8 xl:gap-14 pt-10 lg:pt-14">
          <aside className="lg:sticky lg:top-28 lg:self-start">
            <span className="block text-xs font-semibold tracking-[0.16em] uppercase text-primary">
              Join the network
            </span>
            <h1 className="lp-display text-3xl xl:text-4xl mt-3">Apply as a responder</h1>
            <p className="mt-4 text-sm text-ink-soft leading-relaxed">
              Ambulance drivers and medical practitioners. Whether you work for a
              hospital or on your own, every responder is verified before a
              single emergency reaches them.
            </p>

            <ol className="hidden lg:block mt-10 space-y-1">
              {APPLICATION_STEPS.map((s, i) => {
                const done = i < step
                const now = i === step
                return (
                  <li key={s.title}>
                    <button
                      onClick={() => done && setStep(i)}
                      disabled={!done && !now}
                      className={`w-full text-left flex items-start gap-3.5 rounded-xl px-3 py-2.5 transition-colors ${
                        now ? 'bg-cream-card' : done ? 'hover:bg-cream-card/60 cursor-pointer' : ''
                      }`}
                    >
                      <span className={`mt-0.5 w-6 h-6 rounded-full flex items-center justify-center text-[11px] font-bold flex-shrink-0 ${
                        now ? 'bg-primary text-white' : done ? 'bg-primary/15 text-primary' : 'bg-ink/[0.07] text-ink-mute'
                      }`}>
                        {done ? '✓' : i + 1}
                      </span>
                      <span className="min-w-0">
                        <span className={`block text-sm font-semibold ${now ? 'text-ink' : done ? 'text-ink-soft' : 'text-ink-mute'}`}>
                          {s.title}
                        </span>
                        <span className="block text-xs text-ink-mute mt-0.5">{s.sub}</span>
                      </span>
                    </button>
                  </li>
                )
              })}
            </ol>

            <p className="hidden lg:block mt-8 text-xs text-ink-mute leading-relaxed">
              You will need the eKonnect app to take calls. Approval emails you a
              link to set your password.
            </p>
          </aside>

          <div className="min-w-0">
            <div className="lg:hidden flex gap-1.5 mb-7">
              {APPLICATION_STEPS.map((s, i) => (
                <span key={s.title} className={`h-1.5 flex-1 rounded-full ${i <= step ? 'bg-primary' : 'bg-ink/10'}`} />
              ))}
            </div>

            <div className="bg-cream-card border border-ink/[0.07] rounded-3xl p-6 sm:p-9 xl:p-12 shadow-[0_20px_50px_-30px_rgba(28,10,38,0.25)]">
              <p className="text-xs font-semibold tracking-[0.16em] uppercase text-ink-mute">
                Step {step + 1} of {APPLICATION_STEPS.length}
              </p>
              <h2 className="text-2xl xl:text-3xl font-bold tracking-tight mt-1 mb-8">
                {APPLICATION_STEPS[step].title}
              </h2>

              {step === 0 && (
                <div className="space-y-6">
                  <div className="grid sm:grid-cols-2 gap-3">
                    {AFFILIATIONS.map(f => (
                      <button
                        key={f.value}
                        onClick={() => setA(p => ({ ...p, affiliation: f.value, teamId: '' }))}
                        className={`tile ${a.affiliation === f.value ? 'tile-on' : 'tile-off'}`}
                      >
                        <span className="block font-semibold">{f.label}</span>
                        <span className="block text-xs opacity-70 mt-1 leading-relaxed">{f.sub}</span>
                      </button>
                    ))}
                  </div>

                  {a.affiliation === 'care_point' && (
                    <Field label="Which Care Point" error={showErrors && stepErrors.teamId}
                           hint="Only verified facilities appear here. If yours is missing, ask them to register first.">
                      <select className="input" value={a.teamId} disabled={cpState === 'loading'}
                              onChange={e => setA(p => ({ ...p, teamId: e.target.value }))}>
                        <option value="">
                          {cpState === 'loading' ? 'Loading Care Points…' : 'Select a Care Point…'}
                        </option>
                        {carePoints.map(c => (
                          <option key={c.id} value={c.id}>
                            {c.name}{c.county ? ` — ${c.county}` : ''}
                          </option>
                        ))}
                      </select>

                      {cpState === 'error' && (
                        <p className="text-xs text-emergency bg-emergency/[0.06] border border-emergency/25 rounded-lg px-3 py-2 mt-2 leading-relaxed">
                          The list of Care Points could not be loaded. This is a
                          fault on our side, not a sign that your facility is
                          missing — try again, or choose “I work independently”
                          and mention your employer in the last step.
                        </p>
                      )}

                      {cpState === 'ready' && carePoints.length === 0 && (
                        <p className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2 mt-2 leading-relaxed">
                          No verified Care Points yet. Choose “I work independently”
                          for now — an administrator can attach you to a facility later.
                        </p>
                      )}
                    </Field>
                  )}

                  {a.affiliation === 'independent' && (
                    <p className="text-sm text-ink-soft bg-cream rounded-xl border border-ink/[0.07] px-4 py-3.5 leading-relaxed">
                      You will answer public emergencies in your area directly.
                      You can be attached to a Care Point later without
                      re-applying.
                    </p>
                  )}
                </div>
              )}

              {step === 1 && (
                <div className="space-y-6">
                  <Field label="Full name" error={showErrors && stepErrors.name}>
                    <input className="input" value={a.name} onChange={e => setA(p => ({ ...p, name: e.target.value }))} placeholder="Ben Odhiambo" />
                  </Field>
                  <div className="grid sm:grid-cols-2 gap-5">
                    <Field label="Email" error={showErrors && stepErrors.email}
                           hint="Use the address you will sign in with.">
                      <input className="input" type="email" value={a.email} onChange={e => setA(p => ({ ...p, email: e.target.value }))} placeholder="you@example.com" />
                    </Field>
                    <Field label="Phone" error={showErrors && stepErrors.phone}>
                      <input className="input" type="tel" value={a.phone} onChange={e => setA(p => ({ ...p, phone: e.target.value }))} placeholder="+254 7…" />
                    </Field>
                  </div>
                  <Field label="County you mostly work in" error={showErrors && stepErrors.county}>
                    <select className="input" value={a.county} onChange={e => setA(p => ({ ...p, county: e.target.value }))}>
                      <option value="">Select a county…</option>
                      {COUNTIES.map(c => <option key={c} value={c}>{c}</option>)}
                    </select>
                  </Field>
                </div>
              )}

              {step === 2 && (
                <div className="space-y-6">
                  <Field label="What you do" error={showErrors && stepErrors.role}>
                    <div className="grid sm:grid-cols-2 gap-3">
                      {RESPONDER_ROLES.map(r => (
                        <button key={r.value} onClick={() => setA(p => ({ ...p, role: r.value }))}
                                className={`tile ${a.role === r.value ? 'tile-on' : 'tile-off'}`}>
                          <span className="block font-semibold">{r.label}</span>
                          <span className="block text-xs opacity-70 mt-1">{r.sub}</span>
                        </button>
                      ))}
                    </div>
                  </Field>

                  <Field label="Licence number" error={showErrors && stepErrors.licenseNumber}
                         hint="Practising licence for a practitioner, driving licence for a driver. This is the thing an administrator checks.">
                    <input className="input" value={a.licenseNumber} onChange={e => setA(p => ({ ...p, licenseNumber: e.target.value }))} />
                  </Field>

                  {a.role === 'ambulance' && (
                    <Field label="Vehicle plate" error={showErrors && stepErrors.vehicleNumber}
                           hint="The vehicle you drive. It is how patients and your Care Point identify you.">
                      <input className="input font-mono uppercase" value={a.vehicleNumber}
                             onChange={e => setA(p => ({ ...p, vehicleNumber: e.target.value.toUpperCase() }))} placeholder="KBK 107A" />
                    </Field>
                  )}

                  <div className="grid sm:grid-cols-2 gap-5">
                    <Field label="Speciality">
                      <input className="input" value={a.specialization} onChange={e => setA(p => ({ ...p, specialization: e.target.value }))} placeholder="Paramedic, EMT, nurse…" />
                    </Field>
                    <Field label="Years of experience">
                      <input className="input" inputMode="numeric" value={a.yearsExperience} onChange={e => setA(p => ({ ...p, yearsExperience: e.target.value }))} />
                    </Field>
                  </div>

                  <Field label="Anything else">
                    <textarea rows={3} className="input" value={a.note} onChange={e => setA(p => ({ ...p, note: e.target.value }))} placeholder="Training, previous service, availability…" />
                  </Field>
                </div>
              )}

              {state === 'error' && (
                <p className="mt-6 text-sm text-emergency font-medium">
                  Could not send that. Check your connection and try again.
                </p>
              )}

              <div className="flex items-center gap-3 mt-10 pt-7 border-t border-ink/[0.07]">
                {step > 0 && <button onClick={() => setStep(s => s - 1)} className="lp-btn-ghost">Back</button>}
                <div className="flex-1" />
                {!last ? (
                  <button onClick={next} className="lp-btn">Continue</button>
                ) : (
                  <button onClick={submit} disabled={state === 'sending'} className="lp-btn disabled:opacity-40">
                    {state === 'sending' ? 'Sending…' : 'Submit application'}
                  </button>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

function Field({ label, hint, error, children }) {
  return (
    <div>
      <label className="block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2">{label}</label>
      {children}
      {error
        ? <p className="text-xs text-emergency mt-1.5 font-medium">{error}</p>
        : hint && <p className="text-xs text-ink-mute mt-2 leading-relaxed">{hint}</p>}
    </div>
  )
}

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

function Submitted({ a, refId }) {
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
          Thank you, {a.name.split(' ')[0]}. Your reference is{' '}
          <span className="font-mono font-semibold text-ink">{refId}</span>.
        </p>
        <div className="mt-10 bg-cream-card border border-ink/[0.07] rounded-3xl p-8 text-left">
          <h2 className="font-bold tracking-tight">What happens next</h2>
          <ol className="mt-5 space-y-4">
            {[
              'An administrator checks your licence number against the register.',
              `We email ${a.email} a link to set your password.`,
              'Install the eKonnect app, sign in, and switch yourself on duty.',
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
        <Link to="/" className="lp-btn mt-10">Back to eKonnect</Link>
      </div>
    </div>
  )
}
