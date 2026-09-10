import { useState, useEffect, useMemo } from 'react'
import { collection, onSnapshot, doc, updateDoc, serverTimestamp } from 'firebase/firestore'
import { db, auth } from '../firebase'
import { withTimeout, friendlyError } from '../utils/withTimeout'
import { useTeams } from '../hooks/useTeams'
import ResponderApplications from '../components/ResponderApplications'

const ROLE_META = {
  ambulance:        { label: 'Ambulance',        color: 'bg-blue-100 text-blue-700' },
  practitioner:     { label: 'Practitioner',     color: 'bg-violet-100 text-violet-700' },
  care_point_admin: { label: 'Care Point admin', color: 'bg-amber-100 text-amber-800' },
}

/** What each role can do, shown next to the choice rather than assumed. */
const ROLE_OPTIONS = [
  { value: 'ambulance',        label: 'Ambulance driver',   sub: 'Takes calls and transports' },
  { value: 'practitioner',     label: 'Practitioner',       sub: 'Clinical care on scene' },
  { value: 'care_point_admin', label: 'Care Point admin',   sub: 'Runs the facility portal — no dispatch' },
]

const STATUS_META = {
  verified:  { label: 'Verified',  color: 'bg-emerald-50 text-emerald-700 border-emerald-200' },
  pending:   { label: 'Pending',   color: 'bg-amber-50 text-amber-700 border-amber-200' },
  rejected:  { label: 'Rejected',  color: 'bg-red-50 text-red-700 border-red-200' },
  suspended: { label: 'Suspended', color: 'bg-red-50 text-red-700 border-red-200' },
}

const TABS = [
  { key: 'pending',    label: 'Awaiting review' },
  { key: 'responders', label: 'Responders' },
]

/**
 * Responder governance.
 *
 * Responders can no longer register themselves in the mobile app — anyone could
 * previously tick "Ambulance Driver" and start receiving real emergencies. They
 * apply at /apply, or are submitted by the Care Point that employs them. An
 * administrator checks the licence, and approving creates their login and
 * emails them a link to set a password. Nobody is promoted out of an ordinary
 * account any more — being a responder starts with a licence somebody checked.
 */
export default function Responders() {
  const [users, setUsers] = useState([])
  const [loading, setLoading] = useState(true)
  const [tab, setTab] = useState('pending')
  const [search, setSearch] = useState('')
  const [editing, setEditing] = useState(null)
  const { teams } = useTeams()

  useEffect(() => {
    // Read every user: promoting someone requires seeing the ordinary accounts,
    // not just those who are already responders.
    return onSnapshot(collection(db, 'users'), snap => {
      setUsers(snap.docs.map(d => ({ id: d.id, ...d.data() })))
      setLoading(false)
    })
  }, [])

  const responders = useMemo(
    () => users.filter(u => u.role === 'ambulance' || u.role === 'practitioner'),
    [users],
  )
  const pending = useMemo(
    () => responders.filter(r => (r.verificationStatus ?? 'pending') === 'pending'),
    [responders],
  )
  const _unusedCandidates = useMemo(
    () => users.filter(u => u.role === 'user'),
    [users],
  )

  const list = tab === 'pending' ? pending : responders
  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    if (!q) return list
    return list.filter(u =>
      [u.name, u.email, u.phone, u.organisation].some(v => (v ?? '').toLowerCase().includes(q)),
    )
  }, [list, search])

  const verified = responders.filter(r => r.verificationStatus === 'verified').length
  const online = responders.filter(r => r.isOnline).length

  return (
    <div className="px-4 sm:px-8 lg:px-12 py-8">
      <div className="page-header">
        <div>
          <span className="eyebrow block mb-2">People</span>
          <p className="page-subtitle max-w-xl">
            Promote app users to responders, then verify them before they can go
            on duty. Care Points submit their own crews for approval here too.
          </p>
        </div>
      </div>

      {/* One queue for both doors: people who applied at /apply and people
          their Care Point submitted on their behalf. */}
      <ResponderApplications />

      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 sm:gap-4 mb-6">
        <Stat value={responders.length} label="Responders" />
        <Stat value={verified} label="Verified" tone="text-emerald-600" />
        <Stat value={pending.length} label="Awaiting review" tone="text-amber-600" />
        <Stat value={online} label="Online" tone="text-blue-600" />
      </div>

      {pending.length > 0 && tab !== 'pending' && (
        <button
          onClick={() => setTab('pending')}
          className="w-full mb-5 text-left rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 hover:bg-amber-100 transition-colors"
        >
          <span className="text-sm font-semibold text-amber-800">
            {pending.length} responder{pending.length > 1 ? 's are' : ' is'} waiting to be verified
          </span>
          <span className="block text-xs text-amber-700 mt-0.5">
            They cannot go on duty or receive emergencies until you review them.
          </span>
        </button>
      )}

      <div className="flex flex-col sm:flex-row gap-3 mb-5">
        <div className="flex gap-1.5 bg-white border border-gray-200 rounded-xl shadow-sm p-1 w-fit">
          {TABS.map(t => (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className={`px-4 py-1.5 rounded-lg text-sm font-medium transition-all whitespace-nowrap ${
                tab === t.key
                  ? 'bg-primary text-white shadow-sm'
                  : 'text-gray-500 hover:text-gray-800 hover:bg-gray-50'
              }`}
            >
              {t.label}
              {t.key === 'pending' && pending.length > 0 && (
                <span className="ml-1.5 text-xs">({pending.length})</span>
              )}
            </button>
          ))}
        </div>
        <input
          value={search}
          onChange={e => setSearch(e.target.value)}
          placeholder="Search name, email, phone or organisation…"
          className="flex-1 px-4 py-2 rounded-xl border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
        />
      </div>

      {loading ? (
        <div className="flex justify-center py-20">
          <div className="animate-spin rounded-full h-9 w-9 border-b-2 border-primary" />
        </div>
      ) : filtered.length === 0 ? (
        <div className="card text-center py-16">
          <img src="/assets/doctor.svg" alt="" className="w-14 h-14 mx-auto mb-4 opacity-30" />
          <p className="text-gray-400">
            {tab === 'pending' ? 'Nothing waiting for review' : 'No one here'}
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {filtered.map(u => (
            <PersonCard key={u.id} person={u} teams={teams} onManage={() => setEditing(u)} />
          ))}
        </div>
      )}

      {editing && (
        <ManageDialog
          person={editing}
          teams={teams}
          onClose={() => setEditing(null)}
        />
      )}
    </div>
  )
}

function Stat({ value, label, tone = 'text-gray-900' }) {
  return (
    <div className="card text-center">
      <p className={`text-2xl font-bold ${tone}`}>{value}</p>
      <p className="text-xs text-gray-500 mt-0.5">{label}</p>
    </div>
  )
}

function PersonCard({ person: p, teams, onManage }) {
  const isResponder = p.role === 'ambulance' || p.role === 'practitioner'
  const role = ROLE_META[p.role]
  const status = STATUS_META[p.verificationStatus ?? 'pending']
  const team = teams.find(t => t.id === p.teamId)
  const initials = p.name?.split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase() ?? '?'

  return (
    <div className="card hover:shadow-md transition-shadow flex flex-col">
      <div className="flex items-start gap-3 mb-3">
        <div className="relative flex-shrink-0">
          <div className="w-11 h-11 rounded-full bg-primary/10 flex items-center justify-center text-primary text-sm font-bold">
            {initials}
          </div>
          {isResponder && (
            <span className={`absolute -bottom-0.5 -right-0.5 w-3.5 h-3.5 rounded-full border-2 border-white ${
              p.isOnline ? 'bg-emerald-500' : 'bg-gray-300'
            }`} />
          )}
        </div>
        <div className="flex-1 min-w-0">
          <p className="font-semibold text-gray-900 truncate text-sm">{p.name || '(no name)'}</p>
          <p className="text-xs text-gray-400 truncate">{p.email || p.phone}</p>
        </div>
      </div>

      <div className="flex flex-wrap gap-1.5 mb-3">
        {isResponder ? (
          <>
            <span className={`text-xs font-medium px-2.5 py-0.5 rounded-full ${role.color}`}>
              {role.label}
            </span>
            <span className={`text-xs font-medium px-2.5 py-0.5 rounded-full border ${status.color}`}>
              {status.label}
            </span>
            <span className="text-xs font-medium px-2.5 py-0.5 rounded-full bg-gray-100 text-gray-600">
              {p.visibility === 'private' ? '🏢 Private' : '🌍 Public'}
            </span>
          </>
        ) : (
          <span className="text-xs font-medium px-2.5 py-0.5 rounded-full bg-gray-100 text-gray-600">
            👤 App user
          </span>
        )}
        {p.currentIncidentId && (
          <span className="text-xs font-medium px-2.5 py-0.5 rounded-full bg-orange-50 text-orange-600">
            On job
          </span>
        )}
      </div>

      <div className="border-t border-gray-50 pt-3 space-y-1 flex-1">
        {team && <Detail icon="🏢" text={team.name} />}
        {p.organisation && !team && <Detail icon="🏢" text={p.organisation} />}
        {p.specialization && <Detail icon="🏥" text={p.specialization} />}
        {p.licenseNumber && <Detail icon="🪪" text={p.licenseNumber} />}
        {p.vehicleNumber && <Detail icon="🚑" text={p.vehicleNumber} />}
      </div>

      <button
        onClick={onManage}
        className="mt-3 w-full py-2 rounded-lg text-sm font-medium bg-primary text-white hover:opacity-90 transition-opacity"
      >
        {isResponder ? 'Manage' : 'Make responder'}
      </button>
    </div>
  )
}

function Detail({ icon, text }) {
  return (
    <p className="text-xs text-gray-500 flex items-center gap-1.5 truncate">
      <span>{icon}</span> {text}
    </p>
  )
}

function ManageDialog({ person: p, teams, onClose }) {
  const wasResponder = p.role === 'ambulance' || p.role === 'practitioner'
  const [role, setRole] = useState(wasResponder ? p.role : 'ambulance')
  const [teamId, setTeamId] = useState(p.teamId ?? '')
  const [visibility, setVisibility] = useState(p.visibility ?? 'public')
  const [licenseNumber, setLicense] = useState(p.licenseNumber ?? '')
  const [vehicleNumber, setVehicle] = useState(p.vehicleNumber ?? '')
  const [specialization, setSpec] = useState(p.specialization ?? '')
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')

  const team = teams.find(t => t.id === teamId)

  // Keep responder visibility in step with the organisation they belong to —
  // a private company's crew must not sit on the public network.
  useEffect(() => {
    if (team?.visibility) setVisibility(team.visibility)
  }, [team?.visibility])

  async function apply(verificationStatus) {
    setBusy(true)
    setErr('')
    try {
      await withTimeout(updateDoc(doc(db, 'users', p.id), {
        role,
        teamId: teamId || null,
        visibility,
        organisation: team?.name ?? p.organisation ?? null,
        licenseNumber: licenseNumber || null,
        vehicleNumber: vehicleNumber || null,
        specialization: specialization || null,
        verificationStatus,
        verificationNote: note || null,
        verifiedBy: auth.currentUser?.uid ?? null,
        verifiedAt: serverTimestamp(),
        // Anyone not currently approved must come off the live network at once.
        ...(verificationStatus === 'verified' ? {} : { isAvailable: false }),
      }), 15000, 'Saving responder')
      onClose()
    } catch (e) {
      setErr(friendlyError(e))
    } finally {
      setBusy(false)
    }
  }

  async function demote() {
    setBusy(true)
    setErr('')
    try {
      await withTimeout(updateDoc(doc(db, 'users', p.id), {
        role: 'user',
        activeMode: null,
        teamId: null,
        visibility: null,
        verificationStatus: null,
        verificationNote: note || null,
        isAvailable: false,
        verifiedBy: auth.currentUser?.uid ?? null,
        verifiedAt: serverTimestamp(),
      }), 15000, 'Removing responder status')
      onClose()
    } catch (e) {
      setErr(friendlyError(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 p-0 sm:p-6">
      <div className="bg-white w-full sm:max-w-lg rounded-t-2xl sm:rounded-2xl max-h-[92vh] overflow-y-auto">
        <div className="sticky top-0 bg-white border-b border-gray-100 px-5 py-4 flex items-center justify-between">
          <div>
            <h2 className="font-bold text-gray-900">{p.name || p.email}</h2>
            <p className="text-xs text-gray-400">{p.email || p.phone}</p>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-700 text-xl leading-none">×</button>
        </div>

        <div className="p-5 space-y-4">
          <Field label="Role">
            <div className="grid sm:grid-cols-3 gap-2">
              {ROLE_OPTIONS.map(r => (
                <button
                  key={r.value}
                  onClick={() => setRole(r.value)}
                  className={`tile !p-3 ${role === r.value ? 'tile-on' : 'tile-off'}`}
                >
                  <span className="block text-sm font-semibold">{r.label}</span>
                  <span className="block text-[11px] opacity-70 mt-0.5 leading-snug">{r.sub}</span>
                </button>
              ))}
            </div>
            {role === 'care_point_admin' && (
              <p className="text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2 mt-2 leading-relaxed">
                Signs in to the Care Point portal for the facility selected
                below and manages its fleet and crew. They are never dispatched,
                and see nothing outside that facility — so a Care Point must be
                chosen for this role to work.
              </p>
            )}
          </Field>

          <Field label="Organisation">
            <select
              value={teamId}
              onChange={e => setTeamId(e.target.value)}
              className="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm"
            >
              <option value="">— none —</option>
              {teams.map(t => (
                <option key={t.id} value={t.id}>
                  {t.name}{t.visibility === 'private' ? ' (private)' : ''}
                </option>
              ))}
            </select>
          </Field>

          <Field
            label="Who they serve"
            hint={
              visibility === 'private'
                ? 'Only answers calls from clients registered with this organisation.'
                : 'Answers any nearby emergency on the public network.'
            }
          >
            <div className="grid grid-cols-2 gap-2">
              {[
                { key: 'public',  label: '🌍 Public network' },
                { key: 'private', label: '🏢 Private clients' },
              ].map(v => (
                <button
                  key={v.key}
                  onClick={() => setVisibility(v.key)}
                  className={`py-2 rounded-lg text-sm font-medium border transition-colors ${
                    visibility === v.key
                      ? 'border-primary bg-primary/5 text-primary'
                      : 'border-gray-200 text-gray-600 hover:bg-gray-50'
                  }`}
                >
                  {v.label}
                </button>
              ))}
            </div>
          </Field>

          <div className="grid grid-cols-2 gap-3">
            <Field label="Licence no."><Input value={licenseNumber} onChange={setLicense} /></Field>
            <Field label="Vehicle no."><Input value={vehicleNumber} onChange={setVehicle} /></Field>
          </div>
          <Field label="Specialisation"><Input value={specialization} onChange={setSpec} /></Field>

          <Field label="Note to responder" hint="Shown to them in the app — required context if you reject or suspend.">
            <textarea
              value={note}
              onChange={e => setNote(e.target.value)}
              rows={2}
              className="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm resize-none"
              placeholder="e.g. Licence expires 12/2026 — re-verify before then"
            />
          </Field>
        </div>

        <div className="sticky bottom-0 bg-white border-t border-gray-100 p-4 space-y-2">
          {err && (
            <div
              role="alert"
              className="flex gap-2 text-xs text-red-700 bg-red-50 border border-red-200 rounded-lg px-3 py-2.5 mb-1"
            >
              <span aria-hidden>⚠</span>
              <span>{err}</span>
            </div>
          )}
          <button
            disabled={busy}
            onClick={() => apply('verified')}
            className="w-full py-2.5 rounded-lg text-sm font-semibold bg-emerald-600 text-white hover:bg-emerald-700 disabled:opacity-50"
          >
            {wasResponder ? 'Save & verify' : 'Promote & verify'}
          </button>
          <div className="grid grid-cols-2 gap-2">
            <button
              disabled={busy}
              onClick={() => apply('pending')}
              className="py-2.5 rounded-lg text-sm font-medium border border-gray-200 text-gray-700 hover:bg-gray-50 disabled:opacity-50"
            >
              Save, keep pending
            </button>
            <button
              disabled={busy}
              onClick={() => apply(wasResponder ? 'suspended' : 'rejected')}
              className="py-2.5 rounded-lg text-sm font-medium border border-red-200 text-red-600 hover:bg-red-50 disabled:opacity-50"
            >
              {wasResponder ? 'Suspend' : 'Reject'}
            </button>
          </div>
          {wasResponder && (
            <button
              disabled={busy}
              onClick={demote}
              className="w-full py-2 text-xs text-gray-400 hover:text-red-600 disabled:opacity-50"
            >
              Remove responder status entirely
            </button>
          )}
        </div>
      </div>
    </div>
  )
}

function Field({ label, hint, children }) {
  return (
    <div>
      <label className="block text-xs font-semibold text-gray-700 mb-1.5">{label}</label>
      {children}
      {hint && <p className="text-[11px] text-gray-400 mt-1">{hint}</p>}
    </div>
  )
}

function Input({ value, onChange }) {
  return (
    <input
      value={value}
      onChange={e => onChange(e.target.value)}
      className="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm"
    />
  )
}
