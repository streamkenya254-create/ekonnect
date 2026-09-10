import { useState, useEffect } from 'react'
import { doc, getDoc, setDoc } from 'firebase/firestore'
import { db } from '../firebase'
import { withTimeout } from '../utils/withTimeout'

/**
 * Global app configuration.
 *
 * Every control here changes behaviour in the phones of people who are not in
 * the room — so each one states what it actually does and what it costs, and
 * the page will not let you leave a change unsaved without saying so.
 */

const DEFAULT_SETTINGS = {
  assignmentMode: 'first_accept',
  maxResponseRadiusKm: 10,
  sosTypes: ['medical', 'fire', 'flood', 'security'],
}

const ASSIGNMENT_MODES = [
  {
    value: 'first_accept',
    label: 'First to accept',
    sub: 'The call goes to every crew in range and the first to accept takes it.',
    note: 'Fastest in practice. A crew that is closer but slower to look at their phone loses the call.',
  },
  {
    value: 'auto_nearest',
    label: 'Auto nearest',
    sub: 'The system assigns the closest available crew without asking.',
    note: 'Not yet implemented — every dispatch currently behaves as first to accept.',
    unbuilt: true,
  },
]

const SOS_OPTIONS = [
  { key: 'medical',       label: 'Medical',       sub: 'Trauma, cardiac, maternal', icon: '/assets/doctor.svg' },
  { key: 'fire',          label: 'Fire',          sub: 'Fire and rescue',           icon: '/assets/fire.svg' },
  { key: 'flood',         label: 'Flood',         sub: 'Flooding and disaster',     icon: '/assets/flood.svg' },
  { key: 'security',      label: 'Security',      sub: 'Police and private',        icon: '/assets/police.svg' },
  { key: 'poison',        label: 'Poison',        sub: 'Ingestion and exposure',    icon: '/assets/ambulance.svg' },
  { key: 'mental_health', label: 'Mental health', sub: 'Crisis and self-harm',      icon: '/assets/user.svg' },
]

export default function Settings() {
  const [settings, setSettings] = useState(DEFAULT_SETTINGS)
  const [saved, setSaved] = useState(DEFAULT_SETTINGS)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [justSaved, setJustSaved] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    getDoc(doc(db, 'appConfig', 'settings'))
      .then(snap => {
        const next = snap.exists() ? { ...DEFAULT_SETTINGS, ...snap.data() } : DEFAULT_SETTINGS
        setSettings(next)
        setSaved(next)
      })
      .catch(() => setError('Could not load settings. Showing defaults.'))
      .finally(() => setLoading(false))
  }, [])

  // Compared against what was last written, so the save bar only appears when
  // something has genuinely changed rather than whenever the page is touched.
  const dirty = JSON.stringify(settings) !== JSON.stringify(saved)

  async function handleSave() {
    setSaving(true)
    setError('')
    try {
      await withTimeout(
        setDoc(doc(db, 'appConfig', 'settings'), settings),
        15000,
        'Saving settings',
      )
      setSaved(settings)
      setJustSaved(true)
      setTimeout(() => setJustSaved(false), 2600)
    } catch (e) {
      setError(e.message ?? 'Could not save.')
    } finally {
      setSaving(false)
    }
  }

  function toggleSosType(key) {
    setSettings(prev => ({
      ...prev,
      sosTypes: prev.sosTypes.includes(key)
        ? prev.sosTypes.filter(t => t !== key)
        : [...prev.sosTypes, key],
    }))
  }

  if (loading) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-9 h-9 rounded-full border-2 border-ink/10 border-t-primary animate-spin" />
      </div>
    )
  }

  const radius = settings.maxResponseRadiusKm
  const radiusPct = ((radius - 1) / 49) * 100

  return (
    <div className="px-4 sm:px-8 lg:px-12 py-8 pb-32">
      <div className="page-header">
        <div>
          <span className="eyebrow block mb-2">Configuration</span>
          <p className="page-subtitle max-w-xl">
            These apply to every phone on the network. A change here reaches the
            app immediately — there is no separate publish step.
          </p>
        </div>
      </div>

      {error && (
        <div className="mb-6 flex gap-3 rounded-2xl border border-emergency/25 bg-emergency/[0.06] px-4 py-3.5 text-sm">
          <span className="text-emergency font-bold">!</span>
          <span className="text-ink-soft">{error}</span>
        </div>
      )}

      {/* Wide two-column bento: the two heaviest decisions side by side, the
          SOS grid full width beneath them where it has room to breathe. */}
      <div className="grid xl:grid-cols-2 gap-5">
        <Section
          eyebrow="Dispatch"
          title="Default assignment mode"
          body="Applies to Care Points that have not set their own."
        >
          <div className="grid gap-3 mt-6">
            {ASSIGNMENT_MODES.map(m => {
              const on = settings.assignmentMode === m.value
              return (
                <button
                  key={m.value}
                  onClick={() => setSettings(p => ({ ...p, assignmentMode: m.value }))}
                  className={`tile ${on ? 'tile-on' : 'tile-off'}`}
                >
                  <div className="flex items-start gap-3">
                    <span className={`mt-0.5 w-5 h-5 rounded-full border-2 flex-shrink-0 flex items-center justify-center transition-colors ${
                      on ? 'border-primary' : 'border-ink/20'
                    }`}>
                      {on && <span className="w-2.5 h-2.5 rounded-full bg-primary" />}
                    </span>
                    <div className="min-w-0">
                      <p className="font-semibold text-ink flex items-center gap-2">
                        {m.label}
                        {m.unbuilt && (
                          <span className="badge bg-amber-100 text-amber-800">Not wired up</span>
                        )}
                      </p>
                      <p className="text-sm text-ink-soft mt-1 leading-relaxed">{m.sub}</p>
                      <p className="text-xs text-ink-mute mt-2 leading-relaxed">{m.note}</p>
                    </div>
                  </div>
                </button>
              )
            })}
          </div>
        </Section>

        <Section
          eyebrow="Coverage"
          title="Maximum response radius"
          body="A crew further than this from the emergency is never notified about it."
        >
          <div className="mt-8">
            <div className="flex items-end gap-3">
              <span className="text-6xl font-bold tracking-tightest text-ink leading-none tabular-nums">
                {radius}
              </span>
              <span className="text-lg font-semibold text-ink-mute pb-1.5">km</span>
            </div>

            <div className="relative mt-7">
              {/* Painted track, so the filled portion carries brand colour on
                  every browser rather than relying on accent-color. */}
              <div className="h-2 rounded-full bg-ink/10 overflow-hidden">
                <div
                  className="h-full rounded-full bg-primary transition-[width] duration-150"
                  style={{ width: `${radiusPct}%` }}
                />
              </div>
              <input
                type="range"
                min={1}
                max={50}
                value={radius}
                onChange={e => setSettings(p => ({ ...p, maxResponseRadiusKm: Number(e.target.value) }))}
                aria-label="Maximum response radius in kilometres"
                className="absolute inset-0 w-full h-2 opacity-0 cursor-pointer"
              />
              <div
                className="pointer-events-none absolute top-1/2 -translate-y-1/2 -translate-x-1/2 w-5 h-5 rounded-full bg-primary
                           ring-4 ring-cream-card shadow-[0_2px_8px_rgba(28,10,38,0.3)] transition-[left] duration-150"
                style={{ left: `${radiusPct}%` }}
              />
            </div>

            <div className="flex justify-between text-xs text-ink-mute mt-3 font-medium">
              <span>1 km</span>
              <span>50 km</span>
            </div>

            <p className="text-xs text-ink-mute mt-6 leading-relaxed">
              Wider reaches more crews and risks sending someone on a long
              drive. Narrower keeps responses local and risks an SOS that
              nobody hears.
            </p>
          </div>
        </Section>

        <Section
          className="xl:col-span-2"
          eyebrow="The app"
          title="SOS button types"
          body="Which emergency buttons appear on the home screen of every user's app."
          aside={
            <span className="badge bg-primary/10 text-primary">
              {settings.sosTypes.length} of {SOS_OPTIONS.length} enabled
            </span>
          }
        >
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-3 mt-6">
            {SOS_OPTIONS.map(opt => {
              const on = settings.sosTypes.includes(opt.key)
              return (
                <button
                  key={opt.key}
                  onClick={() => toggleSosType(opt.key)}
                  aria-pressed={on}
                  className={`tile ${on ? 'tile-on' : 'tile-off'} flex items-center gap-4`}
                >
                  <span className={`w-11 h-11 rounded-xl flex items-center justify-center flex-shrink-0 transition-colors ${
                    on ? 'bg-primary/10' : 'bg-ink/[0.05]'
                  }`}>
                    <img
                      src={opt.icon}
                      alt=""
                      className={`w-6 h-6 object-contain transition-opacity ${on ? '' : 'opacity-40'}`}
                    />
                  </span>
                  <span className="min-w-0 flex-1 text-left">
                    <span className="block font-semibold text-ink">{opt.label}</span>
                    <span className="block text-xs text-ink-mute mt-0.5">{opt.sub}</span>
                  </span>
                  <Switch on={on} />
                </button>
              )
            })}
          </div>

          {settings.sosTypes.length === 0 && (
            <p className="mt-5 text-sm text-emergency font-medium">
              With none enabled the app has no way to raise an emergency at all.
            </p>
          )}
        </Section>
      </div>

      {/* Save bar. Docked rather than sitting at the end of the page, because
          on a wide screen the controls and the button were far enough apart
          that a change could be made and left unsaved without noticing. */}
      <div
        className={`fixed bottom-0 left-0 right-0 lg:left-64 z-20 transition-all duration-300 ${
          dirty || justSaved ? 'translate-y-0 opacity-100' : 'translate-y-full opacity-0 pointer-events-none'
        }`}
      >
        <div className="mx-4 sm:mx-8 lg:mx-12 mb-5 rounded-2xl bg-ink text-cream px-5 py-4
                        shadow-[0_20px_50px_-20px_rgba(28,10,38,0.6)] flex items-center gap-4">
          {justSaved && !dirty ? (
            <p className="text-sm font-medium flex items-center gap-2.5">
              <span className="w-5 h-5 rounded-full bg-success/20 flex items-center justify-center">
                <svg className="w-3 h-3 text-success" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
                </svg>
              </span>
              Saved — live on every phone now.
            </p>
          ) : (
            <>
              <p className="text-sm text-cream/70 flex-1">You have unsaved changes.</p>
              <button
                onClick={() => setSettings(saved)}
                className="text-sm font-semibold text-cream/60 hover:text-cream transition-colors px-3 py-2"
              >
                Discard
              </button>
              <button
                onClick={handleSave}
                disabled={saving}
                className="inline-flex items-center gap-2 bg-cream text-ink px-5 py-2.5 rounded-xl text-sm font-semibold
                           hover:bg-white active:scale-[0.98] transition-all disabled:opacity-50"
              >
                {saving && <span className="w-3.5 h-3.5 rounded-full border-2 border-ink/25 border-t-ink animate-spin" />}
                {saving ? 'Saving…' : 'Save settings'}
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  )
}

function Section({ eyebrow, title, body, aside, className = '', children }) {
  return (
    <section className={`panel ${className}`}>
      <div className="flex items-start justify-between gap-4">
        <div>
          <span className="eyebrow">{eyebrow}</span>
          <h2 className="text-2xl font-bold tracking-tightest text-ink mt-2">{title}</h2>
          {body && <p className="text-sm text-ink-soft mt-2 leading-relaxed max-w-lg">{body}</p>}
        </div>
        {aside}
      </div>
      {children}
    </section>
  )
}

/** Purely decorative — the whole tile is the button, so this never gets focus. */
function Switch({ on }) {
  return (
    <span
      aria-hidden="true"
      className={`w-10 h-6 rounded-full p-0.5 flex-shrink-0 transition-colors duration-300 ${
        on ? 'bg-primary' : 'bg-ink/15'
      }`}
    >
      <span
        className={`block w-5 h-5 rounded-full bg-white shadow-sm transition-transform duration-300 ${
          on ? 'translate-x-4' : 'translate-x-0'
        }`}
      />
    </span>
  )
}
