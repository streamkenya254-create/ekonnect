import { useState } from 'react'
import { useTeams } from '../hooks/useTeams'
import { IconPlus, IconEdit, IconTrash, IconX } from '../components/Icons'

const INCIDENT_TYPES = ['medical', 'fire', 'flood', 'security']
const ASSIGNMENT_MODES = [
  { value: 'first_accept', label: '⚡ First to Accept', sub: 'Fastest responder wins' },
  { value: 'auto_nearest', label: '📍 Auto Nearest',    sub: 'System assigns closest' },
]
const COLORS = ['#3D1152', '#1B4080', '#E53935', '#2E7D32', '#FF8F00', '#7B1FA2', '#0097A7', '#37474F']

const empty = {
  name: '',
  color: '#3D1152',
  respondsTo: [],
  assignmentMode: 'first_accept',
  memberIds: [],
  // Public by default — an organisation only becomes private deliberately.
  visibility: 'public',
  contactPhone: '',
}

const VISIBILITY = [
  {
    value: 'public',
    label: '🌍 Public network',
    sub: 'Answers any nearby emergency',
  },
  {
    value: 'private',
    label: '🏢 Private clients',
    sub: 'Answers only registered clients',
  },
]

const TYPE_META = {
  medical:  { emoji: '🏥', label: 'Medical',  icon: '/assets/doctor.svg' },
  fire:     { emoji: '🔥', label: 'Fire',     icon: '/assets/fire.svg' },
  flood:    { emoji: '🌊', label: 'Flood',    icon: '/assets/flood.svg' },
  security: { emoji: '🛡️', label: 'Security', icon: '/assets/police.svg' },
}

export default function Teams() {
  const { teams, loading, saveTeam, deleteTeam } = useTeams()
  const [editing, setEditing] = useState(null)
  const [saving, setSaving] = useState(false)
  const [touched, setTouched] = useState(false)
  const [search, setSearch] = useState('')

  // A team that responds to nothing will never be dispatched, which is a
  // silent failure — surface it as a validation error instead.
  const nameError = touched && !editing?.name?.trim() ? 'Give the team a name.' : ''
  const typesError =
    touched && (editing?.respondsTo ?? []).length === 0
      ? 'Choose at least one emergency type, or this team is never dispatched.'
      : ''
  const canSave = !!editing?.name?.trim() && (editing?.respondsTo ?? []).length > 0

  const visible = teams.filter(t =>
    (t.name ?? '').toLowerCase().includes(search.trim().toLowerCase()),
  )

  function startEdit(team) {
    setTouched(false)
    setEditing(team)
  }

  async function handleSave() {
    setTouched(true)
    if (!canSave) return
    setSaving(true)
    await saveTeam(editing)
    setSaving(false)
    setEditing(null)
  }

  async function handleDelete(id) {
    if (!window.confirm('Delete this team? This cannot be undone.')) return
    await deleteTeam(id)
  }

  return (
    <div className="p-4 sm:p-6 max-w-7xl mx-auto">
      {/* Header */}
      <div className="page-header">
        <div>
          <h1 className="page-title">Teams</h1>
          <p className="page-subtitle">Manage response teams and incident assignments</p>
        </div>
        <button onClick={() => startEdit(empty)} className="btn-primary">
          <IconPlus className="w-4 h-4" /> New Team
        </button>
      </div>

      {teams.length > 0 && (
        <div className="flex flex-col sm:flex-row gap-3 mb-5">
          <input
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder="Search teams…"
            className="flex-1 px-4 py-2 rounded-xl border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
          />
          <div className="flex gap-2 text-xs text-gray-500 items-center">
            <span className="px-2.5 py-1 rounded-lg bg-emerald-50 text-emerald-700 font-medium">
              {teams.filter(t => t.visibility !== 'private').length} public
            </span>
            <span className="px-2.5 py-1 rounded-lg bg-amber-50 text-amber-700 font-medium">
              {teams.filter(t => t.visibility === 'private').length} private
            </span>
          </div>
        </div>
      )}

      {/* Grid */}
      {loading ? (
        <div className="flex justify-center py-20">
          <div className="animate-spin rounded-full h-9 w-9 border-b-2 border-primary" />
        </div>
      ) : teams.length === 0 ? (
        <div className="card text-center py-20">
          <div className="text-5xl mb-3">🛡️</div>
          <p className="text-gray-500 font-medium mb-1">No teams yet</p>
          <p className="text-gray-400 text-sm mb-5">Create your first response team to get started.</p>
          <button onClick={() => startEdit(empty)} className="btn-primary mx-auto">
            <IconPlus className="w-4 h-4" /> Create Team
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-4">
          {visible.map(team => (
            <div key={team.id} className="card hover:shadow-md transition-shadow">
              {/* Header */}
              <div className="flex items-center justify-between mb-4">
                <div className="flex items-center gap-3">
                  <div
                    className="w-11 h-11 rounded-xl flex items-center justify-center text-white text-base font-bold shadow-sm"
                    style={{ backgroundColor: team.color }}
                  >
                    {team.name?.[0]?.toUpperCase() ?? '?'}
                  </div>
                  <div>
                    <div className="flex items-center gap-1.5">
                      <p className="font-semibold text-gray-900">{team.name}</p>
                      <span
                        className={`text-[10px] font-medium px-1.5 py-0.5 rounded-full ${
                          team.visibility === 'private'
                            ? 'bg-amber-50 text-amber-700'
                            : 'bg-emerald-50 text-emerald-700'
                        }`}
                      >
                        {team.visibility === 'private' ? '🏢 Private' : '🌍 Public'}
                      </span>
                    </div>
                    <p className="text-xs text-gray-400">{team.memberIds?.length ?? 0} members</p>
                  </div>
                </div>
                <div className="flex gap-1">
                  <button
                    onClick={() => startEdit(team)}
                    className="p-2 rounded-xl text-gray-400 hover:text-primary hover:bg-purple-50 transition-colors"
                  >
                    <IconEdit />
                  </button>
                  <button
                    onClick={() => handleDelete(team.id)}
                    className="p-2 rounded-xl text-gray-400 hover:text-red-500 hover:bg-red-50 transition-colors"
                  >
                    <IconTrash />
                  </button>
                </div>
              </div>

              {/* Responds to */}
              <div className="flex flex-wrap gap-1.5 mb-4">
                {(team.respondsTo ?? []).map(t => (
                  <span
                    key={t}
                    className="inline-flex items-center gap-1.5 text-xs bg-gray-100 text-gray-700 pl-1.5 pr-2.5 py-1 rounded-full font-medium"
                  >
                    <img src={TYPE_META[t]?.icon} alt="" className="w-4 h-4 object-contain" />
                    {TYPE_META[t]?.label ?? t}
                  </span>
                ))}
                {(team.respondsTo ?? []).length === 0 && (
                  <span className="text-xs text-gray-300">No incident types assigned</span>
                )}
              </div>

              {/* Assignment mode */}
              <div className="border-t border-gray-50 pt-3">
                <p className="text-xs text-gray-400">
                  Assignment:
                  <span className="text-gray-700 font-medium ml-1">
                    {team.assignmentMode === 'first_accept' ? '⚡ First to Accept' : '📍 Auto Nearest'}
                  </span>
                </p>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Modal */}
      {editing && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl shadow-2xl w-full max-w-md overflow-hidden max-h-[92vh] flex flex-col">
            {/* Modal header */}
            <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100 flex-shrink-0">
              <h2 className="text-base font-bold text-gray-900">
                {editing.id ? 'Edit Team' : 'New Team'}
              </h2>
              <button
                onClick={() => setEditing(null)}
                className="p-1.5 rounded-lg text-gray-400 hover:text-gray-600 hover:bg-gray-100 transition-colors"
              >
                <IconX className="w-4 h-4" />
              </button>
            </div>

            <div className="px-6 py-5 space-y-5 overflow-y-auto">
              {/* Name */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1.5">Team Name</label>
                <input
                  type="text"
                  value={editing.name}
                  onChange={e => setEditing(p => ({ ...p, name: e.target.value }))}
                  onBlur={() => setTouched(true)}
                  className={`input ${nameError ? 'border-red-300 focus:ring-red-200' : ''}`}
                  placeholder="e.g. Kakamega County Ambulance"
                  autoFocus
                />
                {nameError && <p className="text-xs text-red-600 mt-1">{nameError}</p>}
              </div>

              {/* Color */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1.5">Team Color</label>
                <div className="flex gap-2 flex-wrap">
                  {COLORS.map(c => (
                    <button
                      key={c}
                      onClick={() => setEditing(p => ({ ...p, color: c }))}
                      className={`w-8 h-8 rounded-full transition-all hover:scale-110 ${
                        editing.color === c ? 'ring-2 ring-offset-2 ring-gray-600 scale-110' : ''
                      }`}
                      style={{ backgroundColor: c }}
                    />
                  ))}
                </div>
              </div>

              {/* Who the organisation serves — drives incident routing */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1.5">Who they serve</label>
                <div className="grid grid-cols-2 gap-2">
                  {VISIBILITY.map(v => {
                    const active = (editing.visibility ?? 'public') === v.value
                    return (
                      <button
                        key={v.value}
                        onClick={() => setEditing(p => ({ ...p, visibility: v.value }))}
                        className={`text-left px-3 py-2.5 rounded-xl border transition-all ${
                          active
                            ? 'bg-primary/5 border-primary text-primary'
                            : 'bg-white border-gray-200 text-gray-600 hover:border-primary/40'
                        }`}
                      >
                        <span className="block text-sm font-medium">{v.label}</span>
                        <span className="block text-[11px] opacity-70 mt-0.5">{v.sub}</span>
                      </button>
                    )
                  })}
                </div>
                {editing.visibility === 'private' && (
                  <p className="text-[11px] text-amber-700 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2 mt-2">
                    Private organisations only receive calls from clients registered
                    with them. Their crews will not see public emergencies.
                  </p>
                )}
              </div>

              {/* Contact phone */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1.5">Contact phone</label>
                <input
                  value={editing.contactPhone ?? ''}
                  onChange={e => setEditing(p => ({ ...p, contactPhone: e.target.value }))}
                  placeholder="+254…"
                  className="w-full px-3 py-2 rounded-xl border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
              </div>

              {/* Responds to */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1.5">Responds To</label>
                <div className="flex flex-wrap gap-2">
                  {INCIDENT_TYPES.map(t => {
                    const active = editing.respondsTo?.includes(t)
                    return (
                      <button
                        key={t}
                        onClick={() =>
                          setEditing(p => ({
                            ...p,
                            respondsTo: active
                              ? p.respondsTo.filter(x => x !== t)
                              : [...(p.respondsTo ?? []), t],
                          }))
                        }
                        className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-sm font-medium border transition-all ${
                          active
                            ? 'bg-primary text-white border-primary shadow-sm'
                            : 'bg-white text-gray-600 border-gray-200 hover:border-primary/40 hover:bg-purple-50'
                        }`}
                      >
                        <img
                          src={TYPE_META[t]?.icon}
                          alt=""
                          className={`w-4 h-4 object-contain ${active ? 'brightness-0 invert' : ''}`}
                        />
                        {TYPE_META[t]?.label ?? t}
                      </button>
                    )
                  })}
                </div>
                {typesError && <p className="text-xs text-red-600 mt-1.5">{typesError}</p>}
              </div>

              {/* Assignment mode */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1.5">Assignment Mode</label>
                <div className="flex gap-2">
                  {ASSIGNMENT_MODES.map(m => (
                    <button
                      key={m.value}
                      onClick={() => setEditing(p => ({ ...p, assignmentMode: m.value }))}
                      className={`flex-1 p-3 rounded-xl border-2 text-left transition-all ${
                        editing.assignmentMode === m.value
                          ? 'border-primary bg-primary/5'
                          : 'border-gray-200 hover:border-gray-300'
                      }`}
                    >
                      <p className="text-sm font-semibold text-gray-800">{m.label}</p>
                      <p className="text-xs text-gray-400 mt-0.5">{m.sub}</p>
                    </button>
                  ))}
                </div>
              </div>
            </div>

            {/* Actions */}
            <div className="flex gap-3 px-6 py-4 bg-gray-50 border-t border-gray-100 flex-shrink-0">
              <button onClick={() => setEditing(null)} className="btn-outline flex-1 justify-center">
                Cancel
              </button>
              <button
                onClick={handleSave}
                disabled={saving || !canSave}
                className="btn-primary flex-1 justify-center"
              >
                {saving ? 'Saving…' : editing.id ? 'Save Changes' : 'Create Team'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
