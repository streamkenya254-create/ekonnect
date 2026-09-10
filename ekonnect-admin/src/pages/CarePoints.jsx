import { useState, useEffect, useMemo } from 'react'
import { collection, onSnapshot, doc, updateDoc, serverTimestamp } from 'firebase/firestore'
import { db, auth } from '../firebase'
import { useTeams } from '../hooks/useTeams'
import { withTimeout } from '../utils/withTimeout'
import { provisionAccount } from '../services/accounts'
import InviteMessage from '../components/InviteMessage'
import { buildCarePointInvite } from '../data/invites'
import CarePointForm from '../components/CarePointForm'
import {
  emptyCarePoint, validateCarePoint, typeLabel,
  STEPS, INCIDENT_TYPES,
} from '../data/carePoints'
import { IconPlus, IconEdit, IconTrash, IconX } from '../components/Icons'

/**
 * Care Points — the facilities on the network.
 *
 * Hospitals, clinics, fire stations and rescue services. Each employs
 * responders (a patient sees "Ben · Ambulance driver · Oasis Hospital") and
 * each can receive a referral when a crew cannot finish the job on scene.
 *
 * Records live in the `teams` collection. The name changed, the collection did
 * not — responder routing already keys off `teamId`, and renaming it would
 * orphan every responder already attached to one.
 */
export default function CarePoints() {
  const { teams, loading, saveTeam, deleteTeam } = useTeams()
  const [editing, setEditing] = useState(null)
  const [search, setSearch] = useState('')
  const [filter, setFilter] = useState('all')
  const [inviting, setInviting] = useState('')
  const [inviteResult, setInviteResult] = useState(null)

  // Applications submitted through the public form at /register. They are held
  // in a separate collection so nothing self-registers onto the live network.
  const [applications, setApplications] = useState([])
  useEffect(() => {
    return onSnapshot(collection(db, 'carePointApplications'), snap => {
      setApplications(
        snap.docs
          .map(d => ({ id: d.id, ...d.data() }))
          .filter(a => a.status === 'pending'),
      )
    }, () => setApplications([]))
  }, [])

  // Responder headcount per Care Point, counted from the users collection —
  // membership lives on the responder's `teamId`, so counting from the other
  // direction is the only figure that cannot go stale.
  const [crewCounts, setCrewCounts] = useState({})
  useEffect(() => {
    return onSnapshot(collection(db, 'users'), snap => {
      const counts = {}
      snap.docs.forEach(d => {
        const u = d.data()
        if (!u.teamId) return
        if (u.role !== 'ambulance' && u.role !== 'practitioner') return
        counts[u.teamId] = (counts[u.teamId] ?? 0) + 1
      })
      setCrewCounts(counts)
    })
  }, [])

  const visible = useMemo(() => {
    const q = search.trim().toLowerCase()
    return teams.filter(cp => {
      if (filter === 'public' && cp.visibility === 'private') return false
      if (filter === 'private' && cp.visibility !== 'private') return false
      if (filter === 'unverified' && cp.verificationStatus === 'verified') return false
      if (!q) return true
      return [cp.name, cp.county, cp.town, typeLabel(cp.type)]
        .filter(Boolean).join(' ').toLowerCase().includes(q)
    })
  }, [teams, search, filter])

  async function handleDelete(cp) {
    if (crewCounts[cp.id]) {
      window.alert(
        `${cp.name} still has ${crewCounts[cp.id]} responder(s) attached. ` +
        'Move them to another Care Point first, or they will be left unroutable.',
      )
      return
    }
    if (!window.confirm(`Delete ${cp.name}? This cannot be undone.`)) return
    await deleteTeam(cp.id)
  }

  async function setVerification(cp, status) {
    await withTimeout(updateDoc(doc(db, 'teams', cp.id), {
      verificationStatus: status,
      verifiedBy: auth.currentUser?.uid ?? null,
      verifiedAt: serverTimestamp(),
    }), 15000, 'Updating verification')
  }

  /**
   * Creates the portal login for a Care Point and emails them the way in.
   *
   * Until this existed, verifying a facility changed a badge and nothing else —
   * somebody then had to remember to create an account by hand and tell them.
   */
  async function inviteCarePoint(cp) {
    setInviting(cp.id)
    setInviteResult(null)
    try {
      const email = (cp.email ?? '').trim()
      if (!email) throw new Error('This Care Point has no email address on record.')

      const { created, emailed } = await withTimeout(provisionAccount({
        email,
        continueUrl: `${window.location.origin}/portal`,
        profile: {
          name: cp.contactName || cp.name,
          phone: cp.contactPhone ?? null,
          role: 'care_point_admin',
          teamId: cp.id,
          organisation: cp.name,
          verificationStatus: 'verified',
        },
      }), 25000, 'Creating the portal login')

      setInviteResult({
        name: cp.name,
        email,
        phone: cp.contactPhone ?? cp.dispatchPhone ?? '',
        created,
        emailed,
        invite: buildCarePointInvite({
          name: cp.contactName || cp.name,
          email,
          facility: cp.name,
        }),
      })
    } catch (e) {
      setInviteResult({ error: e.message ?? 'Could not send the invite.' })
    } finally {
      setInviting('')
    }
  }

  return (
    <div className="p-4 sm:p-6 max-w-7xl mx-auto">
      <div className="page-header">
        <div>
          <p className="page-subtitle">
            Hospitals, clinics and stations on the network — and the crews who answer for them
          </p>
        </div>
        <button onClick={() => setEditing({ ...emptyCarePoint })} className="btn-primary">
          <IconPlus className="w-4 h-4" /> New Care Point
        </button>
      </div>

      {inviteResult && (
        <div className={`mb-6 rounded-2xl border p-5 ${
          inviteResult.error
            ? 'border-emergency/25 bg-emergency/[0.06]'
            : 'border-success/25 bg-success/[0.07]'
        }`}>
          {inviteResult.error ? (
            <p className="text-sm text-ink-soft">{inviteResult.error}</p>
          ) : (
            <>
              <p className="text-sm font-bold text-ink">{inviteResult.name} has portal access</p>
              <p className="text-sm text-ink-soft mt-1.5 leading-relaxed">
                {inviteResult.created ? 'A login was created for ' : 'Their existing account now runs the portal — '}
                <strong className="text-ink">{inviteResult.email}</strong>
                {inviteResult.emailed
                  ? '. They have been emailed a link to set their password and reach the portal.'
                  : '. The email could not be sent — ask them to use “Forgot password” at the sign-in page.'}
              </p>
            </>
          )}
          {inviteResult.invite && (
            <InviteMessage
              email={inviteResult.email}
              phone={inviteResult.phone}
              invite={inviteResult.invite}
            />
          )}
          <button onClick={() => setInviteResult(null)} className="btn-ghost !py-1.5 !text-xs mt-3">Dismiss</button>
        </div>
      )}

      {applications.length > 0 && (
        <div className="mb-6 rounded-2xl border border-amber-200 bg-amber-50/60 p-5">
          <div className="flex items-center gap-2 mb-3">
            <span className="w-2 h-2 rounded-full bg-amber-500 animate-pulse" />
            <h2 className="text-sm font-bold text-amber-900">
              {applications.length} pending application{applications.length > 1 ? 's' : ''}
            </h2>
          </div>
          <p className="text-xs text-amber-800/80 mb-4 leading-relaxed max-w-2xl">
            Submitted from the public form. Check the licence number against the
            facility register and ring the contact before approving — approving
            creates a live, dispatchable Care Point.
          </p>
          <div className="space-y-2">
            {applications.map(a => (
              <ApplicationRow
                key={a.id}
                app={a}
                onOpen={() => {
                  // The application's own id must not travel into the Care
                  // Point record — a new one is minted on save. Drop the key
                  // rather than blanking it; Firestore rejects `undefined`.
                  const { id: _applicationDocId, ...fields } = a
                  setEditing({ ...fields, applicationId: a.id })
                }}
                onReject={() => updateDoc(doc(db, 'carePointApplications', a.id), {
                  status: 'rejected',
                  reviewedBy: auth.currentUser?.uid ?? null,
                  reviewedAt: serverTimestamp(),
                })}
              />
            ))}
          </div>
        </div>
      )}

      {teams.length > 0 && (
        <div className="flex flex-col sm:flex-row gap-3 mb-5">
          <input
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder="Search by name, county or type…"
            className="input flex-1"
          />
          <div className="flex gap-1.5 flex-wrap">
            {[
              ['all', `All ${teams.length}`],
              ['public', `${teams.filter(t => t.visibility !== 'private').length} public`],
              ['private', `${teams.filter(t => t.visibility === 'private').length} private`],
              ['unverified', `${teams.filter(t => t.verificationStatus !== 'verified').length} unverified`],
            ].map(([key, label]) => (
              <button
                key={key}
                onClick={() => setFilter(key)}
                className={`px-3 py-2 rounded-xl text-xs font-semibold transition-all ${
                  filter === key
                    ? 'bg-primary text-white'
                    : 'bg-white border border-gray-200 text-gray-500 hover:border-primary/40'
                }`}
              >
                {label}
              </button>
            ))}
          </div>
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-20">
          <div className="animate-spin rounded-full h-9 w-9 border-b-2 border-primary" />
        </div>
      ) : teams.length === 0 ? (
        <div className="card text-center py-20">
          <img src="/assets/doctor.svg" alt="" className="w-14 h-14 mx-auto mb-4 opacity-40" />
          <p className="text-gray-500 font-medium mb-1">No Care Points yet</p>
          <p className="text-gray-400 text-sm mb-5 max-w-sm mx-auto">
            Register the first hospital, clinic or station. Responders are then
            attached to it from the Responders tab.
          </p>
          <button onClick={() => setEditing({ ...emptyCarePoint })} className="btn-primary mx-auto">
            <IconPlus className="w-4 h-4" /> Register a Care Point
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {visible.map(cp => (
            <CarePointCard
              key={cp.id}
              cp={cp}
              crew={crewCounts[cp.id] ?? 0}
              onEdit={() => setEditing(cp)}
              onDelete={() => handleDelete(cp)}
              onVerify={status => setVerification(cp, status)}
              onInvite={() => inviteCarePoint(cp)}
              inviting={inviting === cp.id}
            />
          ))}
          {visible.length === 0 && (
            <p className="text-sm text-gray-400 col-span-full py-10 text-center">
              Nothing matches that filter.
            </p>
          )}
        </div>
      )}

      {editing && (
        <CarePointWizard
          initial={editing}
          onCancel={() => setEditing(null)}
          onSave={async cp => {
            const { applicationId, ...record } = cp
            await saveTeam(record)
            // Approving an application means the record now lives in `teams`;
            // mark the application so it stops showing as pending.
            if (applicationId) {
              await updateDoc(doc(db, 'carePointApplications', applicationId), {
                status: 'approved',
                reviewedBy: auth.currentUser?.uid ?? null,
                reviewedAt: serverTimestamp(),
              })
            }
            setEditing(null)
          }}
        />
      )}
    </div>
  )
}

/* ── Card ────────────────────────────────────────────────────────────────── */

function CarePointCard({ cp, crew, onEdit, onDelete, onVerify, onInvite, inviting }) {
  const verified = cp.verificationStatus === 'verified'
  const services = cp.services ?? []

  return (
    <div className="card !p-0 overflow-hidden hover:shadow-md transition-shadow">
      {cp.coverImage && (
        <div className="h-28 -mb-6 relative">
          <img src={cp.coverImage} alt="" className="w-full h-full object-cover" />
          <div className="absolute inset-0 bg-gradient-to-t from-white via-white/20 to-transparent" />
        </div>
      )}
      <div className="p-5">
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-start gap-3 min-w-0">
          {cp.logo ? (
            <img
              src={cp.logo}
              alt=""
              className="w-11 h-11 rounded-xl object-contain bg-white border border-gray-100 flex-shrink-0"
            />
          ) : (
            <div
              className="w-11 h-11 rounded-xl flex items-center justify-center text-white text-base font-bold flex-shrink-0"
              style={{ backgroundColor: cp.color ?? '#3D1152' }}
            >
              {cp.name?.[0]?.toUpperCase() ?? '?'}
            </div>
          )}
          <div className="min-w-0">
            <div className="flex items-center gap-1.5 flex-wrap">
              <p className="font-semibold text-gray-900 truncate">{cp.name}</p>
              <Badge tone={verified ? 'green' : 'amber'}>
                {verified ? 'Verified' : cp.verificationStatus === 'rejected' ? 'Rejected' : 'Unverified'}
              </Badge>
              <Badge tone={cp.visibility === 'private' ? 'amber' : 'slate'}>
                {cp.visibility === 'private' ? 'Private' : 'Public'}
              </Badge>
            </div>
            <p className="text-xs text-gray-400 mt-0.5 truncate">
              {typeLabel(cp.type)}
              {cp.county && ` · ${cp.town ? `${cp.town}, ` : ''}${cp.county}`}
            </p>
          </div>
        </div>
        <div className="flex gap-1 flex-shrink-0">
          <button onClick={onEdit} className="p-2 rounded-xl text-gray-400 hover:text-primary hover:bg-purple-50 transition-colors">
            <IconEdit />
          </button>
          <button onClick={onDelete} className="p-2 rounded-xl text-gray-400 hover:text-red-500 hover:bg-red-50 transition-colors">
            <IconTrash />
          </button>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-2 mt-4 text-center">
        <Metric value={crew} label={crew === 1 ? 'responder' : 'responders'} />
        <Metric value={cp.bedCapacity || '—'} label="beds" />
        <Metric value={cp.ambulanceCount || '—'} label="ambulances" />
      </div>

      <div className="flex flex-wrap gap-1.5 mt-4">
        {(cp.respondsTo ?? []).map(t => {
          const meta = INCIDENT_TYPES.find(i => i.value === t)
          return (
            <span key={t} className="inline-flex items-center gap-1.5 text-xs bg-gray-100 text-gray-700 pl-1.5 pr-2.5 py-1 rounded-full font-medium">
              <img src={meta?.icon} alt="" className="w-4 h-4 object-contain" />
              {meta?.label ?? t}
            </span>
          )
        })}
        {(cp.respondsTo ?? []).length === 0 && (
          <span className="text-xs text-red-500 font-medium">
            Answers nothing — never dispatched
          </span>
        )}
      </div>

      {services.length > 0 && (
        <p className="text-xs text-gray-400 mt-3 leading-relaxed">
          {services.slice(0, 5).join(' · ')}
          {services.length > 5 && ` · +${services.length - 5} more`}
        </p>
      )}

      <div className="flex items-center gap-2 mt-4 pt-3 border-t border-gray-50">
        {!verified ? (
          <button onClick={() => onVerify('verified')} className="btn-primary !py-1.5 !text-xs">
            Verify
          </button>
        ) : (
          <button
            onClick={() => onVerify('pending')}
            className="btn-outline !py-1.5 !text-xs"
          >
            Revoke verification
          </button>
        )}
        {verified && (
          <button onClick={onInvite} disabled={inviting} className="btn-outline !py-1.5 !text-xs">
            {inviting ? 'Sending…' : cp.portalInvitedAt ? 'Resend portal invite' : 'Send portal invite'}
          </button>
        )}
        {cp.contactPhone && (
          <a href={`tel:${cp.contactPhone}`} className="btn-ghost !py-1.5 !text-xs">
            {cp.contactPhone}
          </a>
        )}
      </div>
      </div>
    </div>
  )
}

function ApplicationRow({ app, onOpen, onReject }) {
  return (
    <div className="flex items-center gap-3 bg-white rounded-xl px-4 py-3 border border-amber-100">
      <div className="min-w-0 flex-1">
        <p className="text-sm font-semibold text-gray-900 truncate">{app.name}</p>
        <p className="text-xs text-gray-400 truncate">
          {typeLabel(app.type)}
          {app.county && ` · ${app.town ? `${app.town}, ` : ''}${app.county}`}
          {app.registrationNumber ? ` · ${app.registrationNumber}` : ' · no licence number'}
          {app.contactPhone && ` · ${app.contactPhone}`}
        </p>
      </div>
      <button onClick={onReject} className="btn-ghost !py-1.5 !text-xs flex-shrink-0">
        Reject
      </button>
      <button onClick={onOpen} className="btn-primary !py-1.5 !text-xs flex-shrink-0">
        Review
      </button>
    </div>
  )
}

function Metric({ value, label }) {
  return (
    <div className="bg-gray-50 rounded-xl py-2.5">
      <p className="text-lg font-bold text-gray-900 leading-none">{value}</p>
      <p className="text-[11px] text-gray-400 mt-1">{label}</p>
    </div>
  )
}

function Badge({ tone, children }) {
  const tones = {
    green: 'bg-emerald-50 text-emerald-700',
    amber: 'bg-amber-50 text-amber-700',
    slate: 'bg-slate-100 text-slate-600',
  }
  return (
    <span className={`text-[10px] font-semibold px-1.5 py-0.5 rounded-full ${tones[tone]}`}>
      {children}
    </span>
  )
}

/* ── Wizard ──────────────────────────────────────────────────────────────── */

function CarePointWizard({ initial, onCancel, onSave }) {
  const [cp, setCp] = useState(initial)
  const [step, setStep] = useState(0)
  const [showErrors, setShowErrors] = useState(false)
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState('')

  const stepErrors = validateCarePoint(cp, step)
  const allErrors = validateCarePoint(cp)
  const last = step === STEPS.length - 1

  function next() {
    if (Object.keys(stepErrors).length > 0) { setShowErrors(true); return }
    setShowErrors(false)
    setStep(s => s + 1)
  }

  async function save() {
    if (Object.keys(allErrors).length > 0) {
      // Jump back to the first step that is actually blocking, rather than
      // reporting an error about a field the operator cannot see.
      setShowErrors(true)
      const bad = STEPS.findIndex((_, i) => Object.keys(validateCarePoint(cp, i)).length > 0)
      if (bad >= 0) setStep(bad)
      return
    }
    setSaving(true)
    setErr('')
    try {
      await withTimeout(onSave({
        ...cp,
        lat: parseFloat(cp.lat),
        lng: parseFloat(cp.lng),
        bedCapacity: cp.bedCapacity === '' ? null : Number(cp.bedCapacity),
        ambulanceCount: cp.ambulanceCount === '' ? null : Number(cp.ambulanceCount),
        verificationStatus: cp.verificationStatus ?? 'pending',
      }), 15000, 'Saving Care Point')
    } catch (e) {
      setErr(e.message ?? 'Could not save.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-2xl max-h-[92vh] flex flex-col overflow-hidden">
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100 flex-shrink-0">
          <div>
            <h2 className="text-base font-bold text-gray-900">
              {initial.id ? `Edit ${initial.name}` : 'New Care Point'}
            </h2>
            <p className="text-xs text-gray-400 mt-0.5">
              Step {step + 1} of {STEPS.length} · {STEPS[step].sub}
            </p>
          </div>
          <button onClick={onCancel} className="p-1.5 rounded-lg text-gray-400 hover:text-gray-600 hover:bg-gray-100 transition-colors">
            <IconX className="w-4 h-4" />
          </button>
        </div>

        {/* Stepper. Steps already passed are clickable so corrections do not
            mean walking the whole wizard again. */}
        <div className="flex gap-1.5 px-6 py-3 border-b border-gray-50 flex-shrink-0">
          {STEPS.map((s, i) => (
            <button
              key={s.title}
              onClick={() => i <= step && setStep(i)}
              disabled={i > step}
              className={`flex-1 text-left group ${i > step ? 'cursor-default' : ''}`}
            >
              <span className={`block h-1 rounded-full transition-colors ${
                i <= step ? 'bg-primary' : 'bg-gray-200'
              }`} />
              <span className={`block text-[11px] mt-1.5 font-medium truncate ${
                i === step ? 'text-primary' : i < step ? 'text-gray-500' : 'text-gray-300'
              }`}>
                {s.title}
              </span>
            </button>
          ))}
        </div>

        <div className="px-6 py-5 overflow-y-auto">
          <CarePointForm
            value={cp}
            onChange={setCp}
            step={step}
            errors={showErrors ? stepErrors : {}}
          />
        </div>

        <div className="flex items-center gap-3 px-6 py-4 bg-gray-50 border-t border-gray-100 flex-shrink-0">
          {err && <p className="text-xs text-red-600 flex-1">{err}</p>}
          {!err && <div className="flex-1" />}
          {step > 0 && (
            <button onClick={() => setStep(s => s - 1)} className="btn-outline">Back</button>
          )}
          {!last ? (
            <button onClick={next} className="btn-primary">Continue</button>
          ) : (
            <button onClick={save} disabled={saving} className="btn-primary">
              {saving ? 'Saving…' : initial.id ? 'Save changes' : 'Create Care Point'}
            </button>
          )}
        </div>
      </div>
    </div>
  )
}
