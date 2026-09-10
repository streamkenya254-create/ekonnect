import { useState } from 'react'
import {
  CARE_POINT_TYPES, INCIDENT_TYPES, SERVICE_SUGGESTIONS,
  VISIBILITY, ASSIGNMENT_MODES, COLORS, COUNTIES,
} from '../data/carePoints'
import ImagePicker from './ImagePicker'

/**
 * The Care Point registration fields, one step at a time.
 *
 * Deliberately headless about chrome: it renders fields and nothing else, so
 * the admin console can host it in a modal and the public site can host it on
 * a full page without either copy drifting from the other. The parent owns the
 * step number, the value, and the errors.
 *
 * `tone` switches the palette between the console's slate UI and the landing
 * page's cream — same fields, same validation, different room.
 */
export default function CarePointForm({ value, onChange, step, errors = {}, tone = 'admin', wide = false }) {
  const t = tone === 'landing' ? LANDING : ADMIN
  const set = patch => onChange({ ...value, ...patch })
  // Column counts are passed down rather than written into each step. Tailwind
  // breakpoints watch the viewport, not the container, so a bare "xl:" class
  // here would also fire inside the admin's narrow modal on a wide monitor and
  // squeeze four tiles into 600px.
  const cols = wide
    ? { two: 'sm:grid-cols-2 xl:grid-cols-4', three: 'sm:grid-cols-2 xl:grid-cols-3', tiles: 'sm:grid-cols-2 xl:grid-cols-4' }
    : { two: 'sm:grid-cols-2', three: 'sm:grid-cols-2', tiles: 'sm:grid-cols-2' }

  const p = { value, set, errors, t, cols, wide }

  return (
    <div className={wide ? 'space-y-8' : 'space-y-6'}>
      {step === 0 && <StepFacility {...p} />}
      {step === 1 && <StepContact {...p} />}
      {step === 2 && <StepLocation {...p} />}
      {step === 3 && <StepCapability {...p} />}
      {step === 4 && <StepNetwork {...p} />}
    </div>
  )
}

/* ── Palettes ────────────────────────────────────────────────────────────── */

const ADMIN = {
  label: 'block text-sm font-medium text-gray-700 mb-1.5',
  hint: 'text-xs text-gray-400 mt-1.5 leading-relaxed',
  input: 'w-full border border-gray-200 bg-white rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-all placeholder:text-gray-300',
  chipOn: 'bg-primary text-white border-primary',
  chipOff: 'bg-white text-gray-600 border-gray-200 hover:border-primary/40',
  tileOn: 'border-primary bg-primary/5 text-primary',
  tileOff: 'border-gray-200 text-gray-600 hover:border-primary/40',
  err: 'text-xs text-red-600 mt-1.5',
}

const LANDING = {
  label: 'block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2',
  hint: 'text-xs text-ink-mute mt-2 leading-relaxed',
  input: 'w-full bg-cream-card border border-ink/15 rounded-xl px-4 py-3 text-sm placeholder:text-ink-mute/60 focus:outline-none focus:border-primary focus:ring-4 focus:ring-primary/10 transition-all',
  chipOn: 'bg-ink text-cream border-ink',
  chipOff: 'bg-cream-card text-ink-soft border-ink/15 hover:border-ink/40',
  tileOn: 'border-primary bg-primary/5 text-primary',
  tileOff: 'border-ink/15 text-ink-soft hover:border-ink/40',
  err: 'text-xs text-emergency mt-1.5 font-medium',
}

/* ── Small shared pieces ─────────────────────────────────────────────────── */

function Field({ label, hint, error, t, children }) {
  return (
    <div>
      <label className={t.label}>{label}</label>
      {children}
      {error ? <p className={t.err}>{error}</p> : hint ? <p className={t.hint}>{hint}</p> : null}
    </div>
  )
}

function Chip({ on, onClick, t, children }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-sm font-medium border transition-all ${
        on ? t.chipOn : t.chipOff
      }`}
    >
      {children}
    </button>
  )
}

function Tile({ on, onClick, title, sub, t }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`text-left px-3.5 py-3 rounded-xl border-2 transition-all ${on ? t.tileOn : t.tileOff}`}
    >
      <span className="block text-sm font-semibold">{title}</span>
      {sub && <span className="block text-[11px] opacity-70 mt-0.5 leading-snug">{sub}</span>}
    </button>
  )
}

/* ── Step 0 · Facility ───────────────────────────────────────────────────── */

function StepFacility({ value, set, errors, t, cols, wide }) {
  return (
    <>
      {/* Cover first: it is the only field that changes how the Care Point
          feels rather than how it behaves, and putting it at the top makes the
          form read as a profile being built rather than a tax return. */}
      <ImagePicker
        t={t}
        label="Cover photo"
        aspect="wide"
        maxPx={1400}
        quality={0.72}
        value={value.coverImage}
        onChange={coverImage => set({ coverImage })}
        hint="The frontage or entrance. Crews use it to recognise the place on arrival."
      />

      <div className={wide ? 'grid xl:grid-cols-[auto_minmax(0,1fr)] gap-8 items-start' : 'space-y-6'}>
        <ImagePicker
          t={t}
          label="Logo"
          aspect="square"
          maxPx={512}
          value={value.logo}
          onChange={logo => set({ logo })}
          hint="Square works best. Shown beside your crews' names."
        />

        <Field label="Facility name" error={errors.name} t={t}
               hint="As it appears on your registration certificate.">
          <input
            className={t.input}
            value={value.name}
            onChange={e => set({ name: e.target.value })}
            placeholder="e.g. Oasis Specialist Hospital"
          />
        </Field>
      </div>

      <Field label="Facility type" error={errors.type} t={t}>
        <div className={`grid ${cols.tiles} gap-2`}>
          {CARE_POINT_TYPES.map(ct => (
            <Tile key={ct.value} t={t} title={ct.label} sub={ct.sub}
                  on={value.type === ct.value}
                  onClick={() => set({ type: ct.value })} />
          ))}
        </div>
      </Field>

      <Field label="Registration / licence number" t={t}
             hint="MoH facility code, KMPDC licence, or the equivalent for fire and rescue services. Left blank, the Care Point can still be created but stays unverified.">
        <input
          className={t.input}
          value={value.registrationNumber}
          onChange={e => set({ registrationNumber: e.target.value })}
          placeholder="e.g. MOH/KAK/0421"
        />
      </Field>

      <Field label="Description" error={errors.description} t={t}
             hint="What you treat, what you are equipped for, anything a crew should know before referring a patient. Referral matching reads this text, so specifics beat adjectives.">
        <textarea
          rows={4}
          className={t.input}
          value={value.description}
          onChange={e => set({ description: e.target.value })}
          placeholder="24-hour A&E with two theatres, an eight-bed ICU and a blood bank. Trauma and maternity are our strongest units; we do not have a burns unit."
        />
        <p className={t.hint}>{(value.description ?? '').trim().length} characters</p>
      </Field>
    </>
  )
}

/* ── Step 1 · Contact ────────────────────────────────────────────────────── */

function StepContact({ value, set, errors, t, cols }) {
  return (
    <>
      <div className={`grid ${cols.two} gap-4`}>
        <Field label="Contact person" t={t}>
          <input className={t.input} value={value.contactName}
                 onChange={e => set({ contactName: e.target.value })}
                 placeholder="Full name" />
        </Field>
        <Field label="Their role" t={t}>
          <input className={t.input} value={value.contactRole}
                 onChange={e => set({ contactRole: e.target.value })}
                 placeholder="e.g. Hospital administrator" />
        </Field>
      </div>

      <Field label="Main phone" error={errors.contactPhone} t={t}>
        <input className={t.input} value={value.contactPhone} type="tel"
               onChange={e => set({ contactPhone: e.target.value })}
               placeholder="+254 7…" />
      </Field>

      <Field label="24-hour dispatch line" t={t}
             hint="The number a crew rings at 3am. If it is the same as above, leave it blank.">
        <input className={t.input} value={value.dispatchPhone} type="tel"
               onChange={e => set({ dispatchPhone: e.target.value })}
               placeholder="+254 7…" />
      </Field>

      <Field label="Email" error={errors.email} t={t}>
        <input className={t.input} value={value.email} type="email"
               onChange={e => set({ email: e.target.value })}
               placeholder="admin@facility.co.ke" />
      </Field>
    </>
  )
}

/* ── Step 2 · Location ───────────────────────────────────────────────────── */

function StepLocation({ value, set, errors, t, cols }) {
  const [locating, setLocating] = useState(false)
  const [locateError, setLocateError] = useState('')

  function useMyLocation() {
    if (!navigator.geolocation) {
      setLocateError('This browser cannot share a location.')
      return
    }
    setLocating(true)
    setLocateError('')
    navigator.geolocation.getCurrentPosition(
      pos => {
        set({
          lat: pos.coords.latitude.toFixed(6),
          lng: pos.coords.longitude.toFixed(6),
        })
        setLocating(false)
      },
      () => {
        // Denied or unavailable — the manual fields are still there, so this
        // is a convenience failing, not a dead end.
        setLocateError('Could not read your location. Enter the coordinates below.')
        setLocating(false)
      },
      { enableHighAccuracy: true, timeout: 10000 },
    )
  }

  return (
    <>
      <div className={`grid ${cols.three} gap-4`}>
        <Field label="County" error={errors.county} t={t}>
          <select className={t.input} value={value.county}
                  onChange={e => set({ county: e.target.value })}>
            <option value="">Select a county…</option>
            {COUNTIES.map(c => <option key={c} value={c}>{c}</option>)}
          </select>
        </Field>
        <Field label="Town or ward" error={errors.town} t={t}>
          <input className={t.input} value={value.town}
                 onChange={e => set({ town: e.target.value })}
                 placeholder="e.g. Lurambi" />
        </Field>
      </div>

      <Field label="Physical address" t={t}>
        <input className={t.input} value={value.address}
               onChange={e => set({ address: e.target.value })}
               placeholder="Street, building, landmark" />
      </Field>

      <Field
        label="Coordinates"
        error={errors.coords}
        t={t}
        hint="This is the exact point a crew navigates to — the gate, not the town centre. Stand at the entrance and press Use my location for the most accurate result."
      >
        <div className="grid grid-cols-2 gap-3">
          <input className={t.input} value={value.lat} inputMode="decimal"
                 onChange={e => set({ lat: e.target.value })} placeholder="Latitude · 0.2827" />
          <input className={t.input} value={value.lng} inputMode="decimal"
                 onChange={e => set({ lng: e.target.value })} placeholder="Longitude · 34.7519" />
        </div>
      </Field>

      <div className="flex flex-wrap items-center gap-3">
        <button
          type="button"
          onClick={useMyLocation}
          disabled={locating}
          className={`inline-flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm font-semibold border transition-all ${t.chipOff} disabled:opacity-50`}
        >
          {locating ? 'Reading location…' : 'Use my location'}
        </button>
        {value.lat && value.lng && (
          <a
            href={`https://www.google.com/maps?q=${value.lat},${value.lng}`}
            target="_blank"
            rel="noopener noreferrer"
            className="text-sm font-semibold text-primary hover:underline"
          >
            Check this pin on a map ↗
          </a>
        )}
      </div>
      {locateError && <p className={t.err}>{locateError}</p>}
    </>
  )
}

/* ── Step 3 · Capability ─────────────────────────────────────────────────── */

function StepCapability({ value, set, errors, t, cols }) {
  const [custom, setCustom] = useState('')
  const services = value.services ?? []

  function toggleService(s) {
    set({
      services: services.includes(s) ? services.filter(x => x !== s) : [...services, s],
    })
  }

  function addCustom() {
    const s = custom.trim()
    if (!s || services.includes(s)) return
    set({ services: [...services, s] })
    setCustom('')
  }

  return (
    <>
      <Field label="Emergencies you answer" error={errors.respondsTo} t={t}
             hint="A Care Point that answers nothing is never dispatched.">
        <div className="flex flex-wrap gap-2">
          {INCIDENT_TYPES.map(it => {
            const on = (value.respondsTo ?? []).includes(it.value)
            return (
              <Chip key={it.value} t={t} on={on}
                    onClick={() => set({
                      respondsTo: on
                        ? value.respondsTo.filter(x => x !== it.value)
                        : [...(value.respondsTo ?? []), it.value],
                    })}>
                <img src={it.icon} alt="" className={`w-4 h-4 object-contain ${on ? 'brightness-0 invert' : ''}`} />
                {it.label}
              </Chip>
            )
          })}
        </div>
      </Field>

      <Field label="Services offered" t={t}
             hint="Tick everything you can genuinely provide right now. A crew mid-incident is choosing between you and the next facility on this list.">
        <div className="flex flex-wrap gap-2">
          {SERVICE_SUGGESTIONS.map(s => (
            <Chip key={s} t={t} on={services.includes(s)} onClick={() => toggleService(s)}>
              {s}
            </Chip>
          ))}
        </div>
        <div className="flex gap-2 mt-3">
          <input
            className={t.input}
            value={custom}
            onChange={e => setCustom(e.target.value)}
            onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); addCustom() } }}
            placeholder="Add another service…"
          />
          <button type="button" onClick={addCustom}
                  className={`px-4 rounded-xl text-sm font-semibold border ${t.chipOff}`}>
            Add
          </button>
        </div>
        {services.filter(s => !SERVICE_SUGGESTIONS.includes(s)).length > 0 && (
          <div className="flex flex-wrap gap-2 mt-3">
            {services.filter(s => !SERVICE_SUGGESTIONS.includes(s)).map(s => (
              <Chip key={s} t={t} on onClick={() => toggleService(s)}>{s} ×</Chip>
            ))}
          </div>
        )}
      </Field>

      <div className={`grid ${cols.two} gap-4`}>
        <Field label="Inpatient beds" t={t}>
          <input className={t.input} value={value.bedCapacity} inputMode="numeric"
                 onChange={e => set({ bedCapacity: e.target.value })} placeholder="e.g. 60" />
        </Field>
        <Field label="Ambulances operated" t={t}>
          <input className={t.input} value={value.ambulanceCount} inputMode="numeric"
                 onChange={e => set({ ambulanceCount: e.target.value })} placeholder="e.g. 3" />
        </Field>
      </div>

      <div className={`grid ${cols.two} gap-2`}>
        <Tile t={t} title="Open 24 hours" sub="Someone always answers"
              on={!!value.open24Hours}
              onClick={() => set({ open24Hours: !value.open24Hours })} />
        <Tile t={t} title="Accepting cases" sub="Turn off when at capacity"
              on={!!value.acceptingCases}
              onClick={() => set({ acceptingCases: !value.acceptingCases })} />
      </div>
    </>
  )
}

/* ── Step 4 · Network ────────────────────────────────────────────────────── */

function StepNetwork({ value, set, t, cols }) {
  return (
    <>
      <Field label="Who you answer for" t={t}>
        <div className={`grid ${cols.two} gap-2`}>
          {VISIBILITY.map(v => (
            <Tile key={v.value} t={t} title={v.label} sub={v.sub}
                  on={(value.visibility ?? 'public') === v.value}
                  onClick={() => set({ visibility: v.value })} />
          ))}
        </div>
        {value.visibility === 'private' && (
          <p className="text-[11px] text-amber-700 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2 mt-2 leading-relaxed">
            Private Care Points receive calls only from clients registered with
            them. Your crews will not see public emergencies, and public callers
            will not reach you.
          </p>
        )}
      </Field>

      {/* Only private Care Points take subscribers, so only they price cover. */}
      {value.visibility === 'private' && (
        <Field
          label="Cover and payment"
          t={t}
          hint="Shown to clients in the app so they can pay you directly. eKonnect does not collect or process any payment — you set a client's cover dates in your portal once they have paid you."
        >
          <div className={`grid ${cols.two} gap-4`}>
            <div>
              <span className="text-[11px] text-gray-500">Price (KSh)</span>
              <input className={t.input} value={value.coverPrice} inputMode="numeric"
                     onChange={e => set({ coverPrice: e.target.value })} placeholder="e.g. 500" />
            </div>
            <div>
              <span className="text-[11px] text-gray-500">Cover lasts (days)</span>
              <input className={t.input} value={value.coverDays} inputMode="numeric"
                     onChange={e => set({ coverDays: e.target.value })} placeholder="e.g. 30" />
            </div>
            <div>
              <span className="text-[11px] text-gray-500">Paybill or till</span>
              <input className={t.input} value={value.payBill}
                     onChange={e => set({ payBill: e.target.value })} placeholder="e.g. 400200" />
            </div>
            <div>
              <span className="text-[11px] text-gray-500">Account / reference</span>
              <input className={t.input} value={value.payAccount}
                     onChange={e => set({ payAccount: e.target.value })} placeholder="e.g. your phone number" />
            </div>
          </div>
        </Field>
      )}

      <Field label="How calls reach your crews" t={t}>
        <div className={`grid ${cols.two} gap-2`}>
          {ASSIGNMENT_MODES.map(m => (
            <Tile key={m.value} t={t} title={m.label} sub={m.sub}
                  on={value.assignmentMode === m.value}
                  onClick={() => set({ assignmentMode: m.value })} />
          ))}
        </div>
      </Field>

      <Field label="Map colour" t={t}
             hint="Your crews carry this colour on the live incident map.">
        <div className="flex gap-2 flex-wrap">
          {COLORS.map(c => (
            <button
              key={c}
              type="button"
              onClick={() => set({ color: c })}
              aria-label={`Colour ${c}`}
              className={`w-9 h-9 rounded-full transition-all hover:scale-110 ${
                value.color === c ? 'ring-2 ring-offset-2 ring-gray-600 scale-110' : ''
              }`}
              style={{ backgroundColor: c }}
            />
          ))}
        </div>
      </Field>
    </>
  )
}
