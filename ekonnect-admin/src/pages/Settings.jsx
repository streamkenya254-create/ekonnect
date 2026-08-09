import { useState, useEffect } from 'react'
import { doc, getDoc, setDoc } from 'firebase/firestore'
import { db } from '../firebase'

const DEFAULT_SETTINGS = {
  assignmentMode: 'first_accept',
  maxResponseRadiusKm: 10,
  sosTypes: ['medical', 'fire', 'flood', 'security'],
}

const SOS_OPTIONS = [
  { key: 'medical',       label: 'Medical',       emoji: '🏥' },
  { key: 'fire',          label: 'Fire',           emoji: '🔥' },
  { key: 'flood',         label: 'Flood',          emoji: '🌊' },
  { key: 'security',      label: 'Security',       emoji: '🛡️' },
  { key: 'poison',        label: 'Poison',         emoji: '☠️' },
  { key: 'mental_health', label: 'Mental Health',  emoji: '🧠' },
]

export default function Settings() {
  const [settings, setSettings] = useState(DEFAULT_SETTINGS)
  const [loading, setLoading]   = useState(true)
  const [saving, setSaving]     = useState(false)
  const [saved, setSaved]       = useState(false)

  useEffect(() => {
    getDoc(doc(db, 'appConfig', 'settings')).then(snap => {
      if (snap.exists()) setSettings({ ...DEFAULT_SETTINGS, ...snap.data() })
      setLoading(false)
    })
  }, [])

  async function handleSave() {
    setSaving(true)
    await setDoc(doc(db, 'appConfig', 'settings'), settings)
    setSaving(false)
    setSaved(true)
    setTimeout(() => setSaved(false), 3000)
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
      <div className="flex justify-center py-20">
        <div className="animate-spin rounded-full h-9 w-9 border-b-2 border-primary" />
      </div>
    )
  }

  return (
    <div className="p-4 sm:p-6 max-w-2xl mx-auto">
      <div className="page-header">
        <div>
          <h1 className="page-title">Settings</h1>
          <p className="page-subtitle">Global app configuration</p>
        </div>
      </div>

      <div className="space-y-4">
        {/* Assignment mode */}
        <div className="card">
          <h2 className="font-semibold text-gray-800 mb-0.5">Default Assignment Mode</h2>
          <p className="text-sm text-gray-400 mb-4">
            Applies to teams that don't have their own setting.
          </p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            {[
              { value: 'first_accept', label: '⚡ First to Accept', sub: 'Uber style — fastest responder wins' },
              { value: 'auto_nearest', label: '📍 Auto Nearest',    sub: 'System assigns closest available' },
            ].map(opt => (
              <button
                key={opt.value}
                onClick={() => setSettings(p => ({ ...p, assignmentMode: opt.value }))}
                className={`p-4 rounded-xl border-2 text-left transition-all hover:shadow-sm ${
                  settings.assignmentMode === opt.value
                    ? 'border-primary bg-primary/5 shadow-sm'
                    : 'border-gray-200 hover:border-gray-300'
                }`}
              >
                <p className="font-semibold text-gray-800 text-sm">{opt.label}</p>
                <p className="text-xs text-gray-400 mt-0.5">{opt.sub}</p>
              </button>
            ))}
          </div>
        </div>

        {/* Radius */}
        <div className="card">
          <h2 className="font-semibold text-gray-800 mb-0.5">Max Response Radius</h2>
          <p className="text-sm text-gray-400 mb-4">
            Responders only notified if within this range.
          </p>
          <div className="flex items-center gap-4">
            <input
              type="range"
              min={1}
              max={50}
              value={settings.maxResponseRadiusKm}
              onChange={e => setSettings(p => ({ ...p, maxResponseRadiusKm: Number(e.target.value) }))}
              className="flex-1 accent-primary"
            />
            <div className="w-20 text-center">
              <span className="text-2xl font-bold text-primary">{settings.maxResponseRadiusKm}</span>
              <span className="text-sm text-gray-400 ml-1">km</span>
            </div>
          </div>
          <div className="flex justify-between text-xs text-gray-400 mt-1 px-0.5">
            <span>1 km</span>
            <span>50 km</span>
          </div>
        </div>

        {/* SOS types */}
        <div className="card">
          <div className="flex items-center justify-between mb-0.5">
            <h2 className="font-semibold text-gray-800">SOS Button Types</h2>
            <span className="text-xs bg-primary/10 text-primary px-2.5 py-0.5 rounded-full font-medium">
              {settings.sosTypes.length} enabled
            </span>
          </div>
          <p className="text-sm text-gray-400 mb-4">
            Controls which SOS buttons appear in the user app.
          </p>
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
            {SOS_OPTIONS.map(opt => {
              const active = settings.sosTypes.includes(opt.key)
              return (
                <button
                  key={opt.key}
                  onClick={() => toggleSosType(opt.key)}
                  className={`flex items-center gap-2 px-3.5 py-2.5 rounded-xl border-2 text-sm font-medium transition-all ${
                    active
                      ? 'border-primary bg-primary/5 text-primary shadow-sm'
                      : 'border-gray-200 text-gray-600 hover:border-gray-300 hover:bg-gray-50'
                  }`}
                >
                  <span>{opt.emoji}</span>
                  <span>{opt.label}</span>
                </button>
              )
            })}
          </div>
        </div>

        {/* Save */}
        <div className="flex items-center gap-4">
          <button
            onClick={handleSave}
            disabled={saving}
            className="btn-primary px-6"
          >
            {saving ? 'Saving…' : 'Save Settings'}
          </button>
          {saved && (
            <span className="flex items-center gap-1.5 text-sm text-emerald-600 font-medium">
              <span className="text-base">✅</span> Settings saved
            </span>
          )}
        </div>
      </div>
    </div>
  )
}
