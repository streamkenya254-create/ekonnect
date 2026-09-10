import { useState } from 'react'
import { useOutletContext } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth'
import {
  CREW_ROLES, crewRoleLabel, emptyCrewApplication, validateCrewApplication,
} from '../../data/fleet'
import { withTimeout } from '../../utils/withTimeout'
import { applicationState } from '../../data/responders'
import { Empty } from './PortalOverview'
import { IconPlus, IconX } from '../../components/Icons'

/**
 * The Care Point's crew.
 *
 * A facility registers its own people, but cannot verify them — that stays
 * with the network, because a badge a facility can grant itself proves
 * nothing. So this page submits applications and shows exactly where each one
 * has got to.
 */
export default function PortalCrew() {
  const { crew, vehicles, crewApplications, submitCrewApplication } = useOutletContext()
  const { user } = useAuth()
  const [adding, setAdding] = useState(false)

  const responders = crew
    .filter(c => c.role === 'ambulance' || c.role === 'practitioner')
    .sort((a, b) => (a.name ?? '').localeCompare(b.name ?? ''))

  return (
    <div className="px-4 sm:px-8 lg:px-12 py-8">
      <div className="page-header">
        <div>
          <span className="eyebrow block mb-2">People</span>
          <p className="page-subtitle max-w-xl">
            Ambulance drivers and medical practitioners answering under your
            name. Every one is verified by eKonnect before taking a call.
          </p>
        </div>
        <button onClick={() => setAdding(true)} className="btn-primary">
          <IconPlus className="w-4 h-4" /> Register crew
        </button>
      </div>

      {/* Every submission and where it got to. A rejection used to disappear
          silently, leaving a facility to wonder whether it had been sent. */}
      {crewApplications.length > 0 && (
        <section className="panel mb-6">
          <span className="eyebrow">Your submissions</span>
          <h2 className="text-2xl font-bold tracking-tightest mt-2">Approval updates</h2>
          <p className="text-sm text-ink-soft mt-2 leading-relaxed max-w-2xl">
            eKonnect checks every licence. Approved crew appear below and are
            emailed a link to set their password.
          </p>
          <ul className="mt-6 space-y-2">
            {[...crewApplications]
              .sort((a, b) => (a.status === 'pending' ? -1 : 1) - (b.status === 'pending' ? -1 : 1))
              .map(a => {
                const st = applicationState(a)
                const tones = {
                  good: 'bg-success/10 text-success',
                  warn: 'bg-amber-100 text-amber-800',
                  bad:  'bg-emergency/10 text-emergency',
                }
                return (
                  <li key={a.id} className="flex items-start gap-3 rounded-xl bg-cream px-4 py-3">
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-semibold text-ink truncate">{a.name}</p>
                      <p className="text-xs text-ink-mute truncate">
                        {crewRoleLabel(a.role)}
                        {a.licenseNumber && ` · ${a.licenseNumber}`}
                        {a.email && ` · ${a.email}`}
                      </p>
                      <p className="text-xs text-ink-soft mt-1 leading-relaxed">{st.sub}</p>
                    </div>
                    <span className={`badge flex-shrink-0 ${tones[st.tone]}`}>{st.label}</span>
                  </li>
                )
              })}
          </ul>
        </section>
      )}

      {responders.length === 0 ? (
        <div className="panel text-center py-16">
          <img src="/assets/doctor.svg" alt="" className="w-14 h-14 mx-auto opacity-30" />
          <p className="font-semibold text-ink mt-5">No crew yet</p>
          <Empty>
            Register your drivers and practitioners. Each needs to have installed
            the eKonnect app and signed up with the email you give here.
          </Empty>
          <button onClick={() => setAdding(true)} className="btn-primary mx-auto mt-6">
            <IconPlus className="w-4 h-4" /> Register your first crew member
          </button>
        </div>
      ) : (
        <div className="grid sm:grid-cols-2 xl:grid-cols-3 gap-4">
          {responders.map(c => <CrewCard key={c.id} c={c} />)}
        </div>
      )}

      {adding && (
        <CrewDialog
          vehicles={vehicles}
          onCancel={() => setAdding(false)}
          onSave={async a => {
            await submitCrewApplication(a, user?.uid)
            setAdding(false)
          }}
        />
      )}
    </div>
  )
}

function CrewCard({ c }) {
  const verified = c.verificationStatus === 'verified'
  const onCall = !!c.currentIncidentId
  const onDuty = verified && c.isAvailable

  return (
    <article className="panel !p-6">
      <div className="flex items-start gap-3">
        <div className="w-11 h-11 rounded-xl bg-primary/10 flex items-center justify-center text-primary font-bold flex-shrink-0">
          {(c.name ?? '?').slice(0, 1).toUpperCase()}
        </div>
        <div className="min-w-0 flex-1">
          <p className="font-semibold text-ink truncate">{c.name ?? 'Unnamed'}</p>
          <p className="text-xs text-ink-mute mt-0.5">{crewRoleLabel(c.role)}</p>
        </div>
      </div>

      <dl className="mt-5 space-y-1.5 text-xs">
        {c.licenseNumber && <Row k="Licence" v={c.licenseNumber} />}
        {c.vehicleNumber && <Row k="Vehicle" v={c.vehicleNumber} />}
        {c.specialization && <Row k="Speciality" v={c.specialization} />}
        {c.phone && <Row k="Phone" v={c.phone} />}
      </dl>

      <div className="mt-5 pt-4 border-t border-ink/[0.07] flex items-center gap-2 flex-wrap">
        {!verified && <span className="badge bg-amber-100 text-amber-800">Not verified</span>}
        {onCall && <span className="badge bg-primary/10 text-primary">On a call</span>}
        {!onCall && onDuty && <span className="badge bg-success/10 text-success">On duty</span>}
        {!onCall && verified && !c.isAvailable && <span className="badge bg-ink/[0.06] text-ink-mute">Off duty</span>}
      </div>
    </article>
  )
}

function Row({ k, v }) {
  return (
    <div className="flex gap-3">
      <dt className="w-20 flex-shrink-0 text-ink-mute">{k}</dt>
      <dd className="text-ink-soft truncate">{v}</dd>
    </div>
  )
}

/**
 * One text field.
 *
 * Module scope on purpose. Defined inside the dialog, React saw a brand-new
 * component type on every render and remounted the input mid-keystroke — the
 * "flicker" where a field seemed to save and reset itself as you typed.
 */
function Field({ label, value, onChange, error, hint, placeholder, type = 'text', className = '' }) {
  return (
    <div>
      <label className="block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2">{label}</label>
      <input
        className={`input ${className}`}
        type={type}
        value={value}
        onChange={onChange}
        placeholder={placeholder}
      />
      {error
        ? <p className="text-xs text-emergency mt-1.5 font-medium">{error}</p>
        : hint && <p className="text-xs text-ink-mute mt-1.5 leading-relaxed">{hint}</p>}
    </div>
  )
}

function CrewDialog({ vehicles = [], onCancel, onSave }) {
  const [a, setA] = useState({ ...emptyCrewApplication })
  const [show, setShow] = useState(false)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const errors = validateCrewApplication(a)

  async function submit() {
    if (Object.keys(errors).length) { setShow(true); return }
    setBusy(true)
    setErr('')
    try {
      await withTimeout(onSave(a), 15000, 'Submitting application')
    } catch (e) {
      setErr(e.message ?? 'Could not submit.')
    } finally {
      setBusy(false)
    }
  }


  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-cream-card rounded-3xl shadow-2xl w-full max-w-lg max-h-[92vh] flex flex-col overflow-hidden">
        <div className="px-6 py-4 border-b border-ink/[0.07] flex items-center justify-between">
          <div>
            <h2 className="font-bold tracking-tight text-ink">Register a crew member</h2>
            <p className="text-xs text-ink-mute mt-0.5">Submitted to eKonnect for verification</p>
          </div>
          <button onClick={onCancel} className="p-1.5 rounded-lg text-ink-mute hover:text-ink hover:bg-ink/[0.05] transition-colors">
            <IconX className="w-4 h-4" />
          </button>
        </div>

        <div className="px-6 py-5 space-y-5 overflow-y-auto">
          <div className="rounded-xl bg-cream border border-ink/[0.07] px-4 py-3">
            <p className="text-xs text-ink-soft leading-relaxed">
              They must already have the eKonnect app installed and have signed
              up with the email below — that is how an approved application is
              matched to a real account.
            </p>
          </div>

          <Field
            label="Full name" placeholder="Ben Odhiambo"
            value={a.name} error={show && errors.name}
            onChange={e => setA(p => ({ ...p, name: e.target.value }))}
          />
          <Field
            label="Email" type="email" placeholder="ben@example.com"
            hint="The address they used to sign up in the app."
            value={a.email} error={show && errors.email}
            onChange={e => setA(p => ({ ...p, email: e.target.value }))}
          />
          <Field
            label="Phone" type="tel" placeholder="+254 7…"
            value={a.phone} error={show && errors.phone}
            onChange={e => setA(p => ({ ...p, phone: e.target.value }))}
          />

          <div>
            <label className="block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2">Role</label>
            <div className="grid sm:grid-cols-2 gap-2">
              {CREW_ROLES.map(r => (
                <button
                  key={r.value}
                  onClick={() => setA(p => ({ ...p, role: r.value }))}
                  className={`tile !p-3 ${a.role === r.value ? 'tile-on' : 'tile-off'}`}
                >
                  <span className="block text-sm font-semibold">{r.label}</span>
                  <span className="block text-[11px] opacity-70 mt-0.5">{r.sub}</span>
                </button>
              ))}
            </div>
          </div>

          <Field
            label="Licence number" placeholder="Practitioner or driving licence"
            hint="Required for practitioners. This is what the reviewer checks."
            value={a.licenseNumber} error={show && errors.licenseNumber}
            onChange={e => setA(p => ({ ...p, licenseNumber: e.target.value }))}
          />

          <PlatePicker
            vehicles={vehicles}
            value={a.vehicleNumber}
            onChange={vehicleNumber => setA(p => ({ ...p, vehicleNumber }))}
          />

          <Field
            label="Speciality" placeholder="Paramedic, EMT, nurse…"
            value={a.specialization}
            onChange={e => setA(p => ({ ...p, specialization: e.target.value }))}
          />
        </div>

        <div className="flex items-center gap-3 px-6 py-4 bg-cream border-t border-ink/[0.07]">
          {err && <p className="text-xs text-emergency flex-1">{err}</p>}
          {!err && <div className="flex-1" />}
          <button onClick={onCancel} className="btn-outline">Cancel</button>
          <button onClick={submit} disabled={busy} className="btn-primary">
            {busy ? 'Submitting…' : 'Submit for approval'}
          </button>
        </div>
      </div>
    </div>
  )
}

/**
 * Which vehicle this person drives.
 *
 * Picked from the fleet rather than typed, because the plate is what links a
 * responder to a vehicle — one transposed character and the vehicle shows as
 * unstaffed forever while the driver shows as having no vehicle. A plate that
 * is genuinely new can still be entered, and the fleet page will pick it up
 * once the vehicle itself is registered.
 */
function PlatePicker({ vehicles, value, onChange }) {
  const known = vehicles.map(v => v.plate).filter(Boolean).sort()
  const isNew = value !== '' && !known.includes(value)
  const [manual, setManual] = useState(isNew)

  return (
    <div>
      <label className="block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2">
        Vehicle plate
      </label>

      {!manual ? (
        <select
          className="input"
          value={known.includes(value) ? value : ''}
          onChange={e => {
            if (e.target.value === '__new') { onChange(''); setManual(true); return }
            onChange(e.target.value)
          }}
        >
          <option value="">Not assigned to a vehicle</option>
          {known.map(p => <option key={p} value={p}>{p}</option>)}
          <option value="__new">+ Add a plate not in the fleet…</option>
        </select>
      ) : (
        <div className="flex gap-2">
          <input
            className="input font-mono uppercase"
            value={value}
            onChange={e => onChange(e.target.value.toUpperCase())}
            placeholder="KBK 107A"
            autoFocus
          />
          {known.length > 0 && (
            <button
              type="button"
              onClick={() => { onChange(''); setManual(false) }}
              className="btn-outline !py-2 !text-xs flex-shrink-0"
            >
              Pick from fleet
            </button>
          )}
        </div>
      )}

      <p className="text-xs text-ink-mute mt-1.5 leading-relaxed">
        {known.length === 0
          ? 'No vehicles registered yet — type the plate here, then add the vehicle itself on the Fleet page.'
          : manual
            ? 'This plate is not in your fleet yet. Add the vehicle on the Fleet page so it shows duty state.'
            : 'Optional. Their vehicle shows as on duty whenever they are.'}
      </p>
    </div>
  )
}
