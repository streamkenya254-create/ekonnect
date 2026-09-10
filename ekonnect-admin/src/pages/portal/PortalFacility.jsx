import { useState, useEffect } from 'react'
import { useOutletContext } from 'react-router-dom'
import { doc, updateDoc, serverTimestamp } from 'firebase/firestore'
import { db } from '../../firebase'
import { withTimeout } from '../../utils/withTimeout'
import { SERVICE_SUGGESTIONS, typeLabel } from '../../data/carePoints'

/**
 * The facility's own profile.
 *
 * Split deliberately down the middle. Operational facts — are we accepting
 * cases, what can we do today, who answers the phone — are the facility's to
 * change the moment they change, because a hospital knowing it is full at 2am
 * is time-critical and routing it through a review queue would make the data
 * worse, not safer.
 *
 * Identity — legal name, licence, type, coordinates — is locked. Those are
 * what the verified badge attests to, so changing them has to go back through
 * whoever verified them.
 */
const EDITABLE = [
  'acceptingCases', 'open24Hours', 'services', 'description',
  'contactName', 'contactRole', 'contactPhone', 'dispatchPhone', 'email',
  'bedCapacity', 'ambulanceCount',
  'coverPrice', 'coverDays', 'payBill', 'payAccount', 'visibility',
]

export default function PortalFacility() {
  const { carePoint } = useOutletContext()
  const [draft, setDraft] = useState(null)
  const [saving, setSaving] = useState(false)
  const [justSaved, setJustSaved] = useState(false)
  const [error, setError] = useState('')
  const [custom, setCustom] = useState('')

  useEffect(() => {
    if (carePoint && !draft) setDraft(pick(carePoint))
  }, [carePoint, draft])

  if (!carePoint || !draft) return null

  const dirty = JSON.stringify(draft) !== JSON.stringify(pick(carePoint))
  const services = draft.services ?? []

  function set(patch) { setDraft(d => ({ ...d, ...patch })) }

  function toggleService(s) {
    set({ services: services.includes(s) ? services.filter(x => x !== s) : [...services, s] })
  }

  async function save() {
    setSaving(true)
    setError('')
    try {
      await withTimeout(
        updateDoc(doc(db, 'teams', carePoint.id), { ...draft, updatedAt: serverTimestamp() }),
        15000,
        'Saving facility',
      )
      setJustSaved(true)
      setTimeout(() => setJustSaved(false), 2600)
    } catch (e) {
      setError(e.message ?? 'Could not save.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="px-4 sm:px-8 lg:px-12 py-8 pb-32">
      <div className="page-header">
        <div>
          <span className="eyebrow">Your facility</span>
          <h1 className="page-title mt-2">{carePoint.name}</h1>
          <p className="page-subtitle">
            {typeLabel(carePoint.type)}
            {carePoint.county && ` · ${carePoint.town ? `${carePoint.town}, ` : ''}${carePoint.county}`}
          </p>
        </div>
      </div>

      {error && (
        <div className="mb-6 rounded-2xl border border-emergency/25 bg-emergency/[0.06] px-4 py-3.5 text-sm text-ink-soft">
          {error}
        </div>
      )}

      <div className="grid xl:grid-cols-2 gap-5">
        <section className="panel">
          <span className="eyebrow">Availability</span>
          <h2 className="text-2xl font-bold tracking-tightest mt-2">Can you take cases?</h2>
          <p className="text-sm text-ink-soft mt-2 leading-relaxed max-w-lg">
            This is the switch crews see when deciding where to bring someone.
            Turn it off the moment you are full — an accurate no is far more
            useful than an optimistic yes.
          </p>

          <div className="grid sm:grid-cols-2 gap-2 mt-6">
            <button
              onClick={() => set({ acceptingCases: !draft.acceptingCases })}
              className={`tile ${draft.acceptingCases ? 'tile-on' : 'tile-off'}`}
            >
              <span className="block text-sm font-semibold">
                {draft.acceptingCases ? 'Accepting cases' : 'Not accepting cases'}
              </span>
              <span className="block text-xs opacity-70 mt-1 leading-relaxed">
                {draft.acceptingCases
                  ? 'Crews may refer patients to you.'
                  : 'You are hidden from referral suggestions.'}
              </span>
            </button>
            <button
              onClick={() => set({ open24Hours: !draft.open24Hours })}
              className={`tile ${draft.open24Hours ? 'tile-on' : 'tile-off'}`}
            >
              <span className="block text-sm font-semibold">
                {draft.open24Hours ? 'Open 24 hours' : 'Limited hours'}
              </span>
              <span className="block text-xs opacity-70 mt-1 leading-relaxed">
                {draft.open24Hours ? 'Someone always answers.' : 'Not staffed around the clock.'}
              </span>
            </button>
          </div>

          <div className="grid sm:grid-cols-2 gap-4 mt-6">
            <Field label="Inpatient beds">
              <input className="input" inputMode="numeric" value={draft.bedCapacity ?? ''}
                     onChange={e => set({ bedCapacity: e.target.value })} />
            </Field>
            <Field label="Ambulances operated">
              <input className="input" inputMode="numeric" value={draft.ambulanceCount ?? ''}
                     onChange={e => set({ ambulanceCount: e.target.value })} />
            </Field>
          </div>
        </section>

        <section className="panel">
          <span className="eyebrow">Contact</span>
          <h2 className="text-2xl font-bold tracking-tightest mt-2">Who answers</h2>
          <p className="text-sm text-ink-soft mt-2 leading-relaxed max-w-lg">
            The dispatch line is what a crew rings at 3am on the way to you.
          </p>

          <div className="grid sm:grid-cols-2 gap-4 mt-6">
            <Field label="Contact person">
              <input className="input" value={draft.contactName ?? ''} onChange={e => set({ contactName: e.target.value })} />
            </Field>
            <Field label="Their role">
              <input className="input" value={draft.contactRole ?? ''} onChange={e => set({ contactRole: e.target.value })} />
            </Field>
            <Field label="Main phone">
              <input className="input" type="tel" value={draft.contactPhone ?? ''} onChange={e => set({ contactPhone: e.target.value })} />
            </Field>
            <Field label="24-hour dispatch line">
              <input className="input" type="tel" value={draft.dispatchPhone ?? ''} onChange={e => set({ dispatchPhone: e.target.value })} />
            </Field>
            <div className="sm:col-span-2">
              <Field label="Email">
                <input className="input" type="email" value={draft.email ?? ''} onChange={e => set({ email: e.target.value })} />
              </Field>
            </div>
          </div>
        </section>

        {/* Whether the public network can reach them at all. Theirs to
            decide: it only ever narrows who they hear from. */}
        <section className="panel xl:col-span-2">
          <span className="eyebrow">Network</span>
          <h2 className="text-2xl font-bold tracking-tightest mt-2">Who you answer for</h2>
          <p className="text-sm text-ink-soft mt-2 leading-relaxed max-w-2xl">
            Going private stops the public network reaching you. Your crews will
            no longer see nearby emergencies from the general public — only
            calls from clients registered with you.
          </p>
          <div className="grid sm:grid-cols-2 gap-2 mt-6">
            <button
              onClick={() => set({ visibility: 'public' })}
              className={`tile ${(draft.visibility ?? 'public') !== 'private' ? 'tile-on' : 'tile-off'}`}
            >
              <span className="block text-sm font-semibold">Public network</span>
              <span className="block text-xs opacity-70 mt-1 leading-relaxed">
                Receives any nearby emergency.
              </span>
            </button>
            <button
              onClick={() => set({ visibility: 'private' })}
              className={`tile ${draft.visibility === 'private' ? 'tile-on' : 'tile-off'}`}
            >
              <span className="block text-sm font-semibold">Private clients</span>
              <span className="block text-xs opacity-70 mt-1 leading-relaxed">
                Only clients registered with you.
              </span>
            </button>
          </div>
        </section>

        {/* Only a private facility carries its own paying clients. */}
        {draft.visibility === 'private' && (
          <section className="panel xl:col-span-2">
            <span className="eyebrow">Cover</span>
            <h2 className="text-2xl font-bold tracking-tightest mt-2">What clients pay you</h2>
            <p className="text-sm text-ink-soft mt-2 leading-relaxed max-w-2xl">
              Shown in the app to anyone registering with you, so they can pay
              you directly. eKonnect never collects or processes this money —
              once a client has paid, set their cover dates on the Subscribers
              page and the app starts counting down from there.
            </p>

            <div className="grid sm:grid-cols-2 xl:grid-cols-4 gap-4 mt-6">
              <Field label="Price (KSh)">
                <input className="input" inputMode="numeric" value={draft.coverPrice ?? ''}
                       placeholder="500"
                       onChange={e => set({ coverPrice: e.target.value })} />
              </Field>
              <Field label="Cover lasts (days)">
                <input className="input" inputMode="numeric" value={draft.coverDays ?? ''}
                       placeholder="30"
                       onChange={e => set({ coverDays: e.target.value })} />
              </Field>
              <Field label="Paybill or till">
                <input className="input" value={draft.payBill ?? ''}
                       placeholder="400200"
                       onChange={e => set({ payBill: e.target.value })} />
              </Field>
              <Field label="Account / reference">
                <input className="input" value={draft.payAccount ?? ''}
                       placeholder="Client's phone number"
                       onChange={e => set({ payAccount: e.target.value })} />
              </Field>
            </div>
          </section>
        )}

        <section className="panel xl:col-span-2">
          <span className="eyebrow">Capability</span>
          <h2 className="text-2xl font-bold tracking-tightest mt-2">Services you can provide</h2>
          <p className="text-sm text-ink-soft mt-2 leading-relaxed max-w-2xl">
            A crew mid-incident is choosing between you and the next facility on
            the list. Tick only what you can genuinely provide right now.
          </p>

          <div className="flex flex-wrap gap-2 mt-6">
            {[...new Set([...SERVICE_SUGGESTIONS, ...services])].map(s => (
              <button
                key={s}
                onClick={() => toggleService(s)}
                className={`px-3 py-1.5 rounded-xl text-sm font-medium border transition-all ${
                  services.includes(s)
                    ? 'bg-ink text-cream border-ink'
                    : 'bg-cream-card text-ink-soft border-ink/15 hover:border-ink/40'
                }`}
              >
                {s}
              </button>
            ))}
          </div>

          <div className="flex gap-2 mt-4 max-w-md">
            <input
              className="input"
              value={custom}
              onChange={e => setCustom(e.target.value)}
              onKeyDown={e => {
                if (e.key !== 'Enter') return
                e.preventDefault()
                const s = custom.trim()
                if (s && !services.includes(s)) set({ services: [...services, s] })
                setCustom('')
              }}
              placeholder="Add another service…"
            />
          </div>

          <div className="mt-8">
            <Field label="Description">
              <textarea
                rows={4}
                className="input"
                value={draft.description ?? ''}
                onChange={e => set({ description: e.target.value })}
              />
            </Field>
            <p className="text-xs text-ink-mute mt-2 leading-relaxed max-w-2xl">
              Referral matching reads this text when a crew is looking for
              somewhere to take a patient, so specifics beat adjectives.
            </p>
          </div>
        </section>

        {/* Locked half. Shown rather than hidden — a facility should be able to
            check what is on record about it, and see who to ask to change it. */}
        <section className="panel xl:col-span-2 bg-cream">
          <span className="eyebrow">Verified details</span>
          <h2 className="text-2xl font-bold tracking-tightest mt-2">Locked</h2>
          <p className="text-sm text-ink-soft mt-2 leading-relaxed max-w-2xl">
            These are what your verification attests to, so they can only be
            changed by the eKonnect team. Contact them if any is wrong.
          </p>
          <dl className="grid sm:grid-cols-2 xl:grid-cols-4 gap-x-8 gap-y-4 mt-6">
            <Locked k="Registered name" v={carePoint.name} />
            <Locked k="Facility type" v={typeLabel(carePoint.type)} />
            <Locked k="Licence number" v={carePoint.registrationNumber || 'Not on record'} />
            <Locked k="County" v={carePoint.county} />
            <Locked k="Town or ward" v={carePoint.town} />
            <Locked k="Address" v={carePoint.address || '—'} />
            <Locked k="Coordinates" v={`${carePoint.lat ?? '—'}, ${carePoint.lng ?? '—'}`} />
          </dl>
        </section>
      </div>

      <div className={`fixed bottom-0 left-0 right-0 lg:left-64 z-20 transition-all duration-300 ${
        dirty || justSaved ? 'translate-y-0 opacity-100' : 'translate-y-full opacity-0 pointer-events-none'
      }`}>
        <div className="mx-4 sm:mx-8 lg:mx-12 mb-5 rounded-2xl bg-ink text-cream px-5 py-4
                        shadow-[0_20px_50px_-20px_rgba(28,10,38,0.6)] flex items-center gap-4">
          {justSaved && !dirty ? (
            <p className="text-sm font-medium">Saved — crews see this now.</p>
          ) : (
            <>
              <p className="text-sm text-cream/70 flex-1">You have unsaved changes.</p>
              <button onClick={() => setDraft(pick(carePoint))}
                      className="text-sm font-semibold text-cream/60 hover:text-cream transition-colors px-3 py-2">
                Discard
              </button>
              <button onClick={save} disabled={saving}
                      className="inline-flex items-center gap-2 bg-cream text-ink px-5 py-2.5 rounded-xl text-sm font-semibold
                                 hover:bg-white active:scale-[0.98] transition-all disabled:opacity-50">
                {saving && <span className="w-3.5 h-3.5 rounded-full border-2 border-ink/25 border-t-ink animate-spin" />}
                {saving ? 'Saving…' : 'Save changes'}
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  )
}

/** Only the fields a facility is allowed to change ever enter the draft. */
function pick(cp) {
  const out = {}
  for (const k of EDITABLE) out[k] = cp[k] ?? (k === 'services' ? [] : '')
  return out
}

function Field({ label, children }) {
  return (
    <div>
      <label className="block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2">{label}</label>
      {children}
    </div>
  )
}

function Locked({ k, v }) {
  return (
    <div className="min-w-0">
      <dt className="text-[11px] font-semibold tracking-wider uppercase text-ink-mute">{k}</dt>
      <dd className="text-sm text-ink-soft mt-1 break-words">{v || '—'}</dd>
    </div>
  )
}
