import { useState, useEffect } from 'react'
import { collection, onSnapshot, doc, updateDoc, serverTimestamp } from 'firebase/firestore'
import { db, auth } from '../firebase'
import { withTimeout } from '../utils/withTimeout'
import { provisionAccount } from '../services/accounts'
import { responderRoleLabel, APPLICATION_SOURCES } from '../data/responders'
import InviteMessage from './InviteMessage'
import { buildResponderInvite } from '../data/invites'

/**
 * The review queue for people who want to answer emergencies.
 *
 * Approving does three things in one act: it creates or finds their login,
 * writes the verified responder profile, and has Firebase email them a link to
 * set their password. Before this, approval only flipped a flag and somebody
 * had to remember to tell the person — which is how approved responders sat
 * unaware for days.
 */
export default function ResponderApplications() {
  const [apps, setApps] = useState([])
  const [busyId, setBusyId] = useState('')
  const [result, setResult] = useState(null)
  const [error, setError] = useState('')
  const [rejecting, setRejecting] = useState(null)

  useEffect(() => {
    return onSnapshot(
      collection(db, 'responderApplications'),
      snap => setApps(
        snap.docs.map(d => ({ id: d.id, ...d.data() })).filter(a => a.status === 'pending'),
      ),
      () => setApps([]),
    )
  }, [])

  if (apps.length === 0 && !result) return null

  async function approve(app) {
    setBusyId(app.id)
    setError('')
    setResult(null)
    try {
      const { uid, created, emailed } = await withTimeout(
        provisionAccount({
          email: app.email,
          continueUrl: `${window.location.origin}/login`,
          profile: {
            name: app.name,
            phone: app.phone ?? null,
            role: app.role,
            teamId: app.teamId || null,
            organisation: app.teamName || null,
            licenseNumber: app.licenseNumber || null,
            vehicleNumber: app.vehicleNumber || null,
            specialization: app.specialization || null,
            county: app.county || null,
            visibility: 'public',
            verificationStatus: 'verified',
            verifiedBy: auth.currentUser?.uid ?? null,
            verifiedAt: serverTimestamp(),
            // Never on duty by default. Going on duty is the responder's own
            // act, made in the app when they are actually able to answer.
            isAvailable: false,
          },
        }),
        25000,
        'Creating the responder account',
      )

      await updateDoc(doc(db, 'responderApplications', app.id), {
        status: 'approved',
        matchedUserId: uid ?? null,
        accountCreated: created,
        inviteEmailed: emailed,
        reviewedBy: auth.currentUser?.uid ?? null,
        reviewedAt: serverTimestamp(),
      })

      setResult({
        name: app.name,
        email: app.email,
        phone: app.phone ?? '',
        created,
        emailed,
        invite: buildResponderInvite({
          name: app.name,
          email: app.email,
          role: app.role,
          facility: app.teamName,
          licenseNumber: app.licenseNumber,
          vehicleNumber: app.vehicleNumber,
        }),
      })
    } catch (e) {
      setError(`${app.name}: ${e.message ?? 'could not be approved.'}`)
    } finally {
      setBusyId('')
    }
  }

  async function reject(app, note) {
    setBusyId(app.id)
    try {
      await updateDoc(doc(db, 'responderApplications', app.id), {
        status: 'rejected',
        reviewNote: note || null,
        reviewedBy: auth.currentUser?.uid ?? null,
        reviewedAt: serverTimestamp(),
      })
      setRejecting(null)
    } catch (e) {
      setError(e.message ?? 'Could not reject.')
    } finally {
      setBusyId('')
    }
  }

  return (
    <section className="mb-6">
      {result && (
        <div className="mb-4 rounded-2xl border border-success/25 bg-success/[0.07] p-5">
          <p className="text-sm font-bold text-ink">{result.name} is on the network</p>
          <p className="text-sm text-ink-soft mt-1.5 leading-relaxed">
            {result.created ? 'A login was created for ' : 'Their existing account was updated — '}
            <strong className="text-ink">{result.email}</strong>
            {result.emailed
              ? '. They have been emailed a link to set their password.'
              : '. The invite email could not be sent — use Resend on their row, or tell them to use “Forgot password” at sign-in.'}
          </p>
          {result.invite && (
            <InviteMessage
              email={result.email}
              phone={result.phone}
              invite={result.invite}
            />
          )}
          <button onClick={() => setResult(null)} className="btn-ghost !py-1.5 !text-xs mt-3">Dismiss</button>
        </div>
      )}

      {error && (
        <div className="mb-4 rounded-2xl border border-emergency/25 bg-emergency/[0.06] px-4 py-3.5 text-sm text-ink-soft">
          {error}
        </div>
      )}

      {apps.length > 0 && (
        <div className="rounded-2xl border border-amber-200 bg-amber-50/60 p-5">
          <div className="flex items-center gap-2 mb-2">
            <span className="w-2 h-2 rounded-full bg-amber-500 animate-pulse" />
            <h2 className="text-sm font-bold text-amber-900">
              {apps.length} responder {apps.length === 1 ? 'application' : 'applications'}
            </h2>
          </div>
          <p className="text-xs text-amber-800/80 mb-4 leading-relaxed max-w-3xl">
            Check the licence number before approving. Approving creates their
            login, verifies them, and emails a link to set a password — they can
            take calls as soon as they go on duty in the app.
          </p>

          <div className="space-y-2">
            {apps.map(app => (
              <div key={app.id} className="bg-cream-card rounded-xl px-4 py-3.5 border border-amber-100">
                <div className="flex items-start gap-3 flex-wrap">
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-semibold text-ink">
                      {app.name}
                      <span className="font-normal text-ink-mute"> · {responderRoleLabel(app.role)}</span>
                    </p>
                    <p className="text-xs text-ink-mute mt-0.5">
                      {app.teamName
                        ? <span className="text-primary font-semibold">{app.teamName}</span>
                        : 'Independent'}
                      {' · '}Licence {app.licenseNumber || '—'}
                      {app.vehicleNumber && ` · ${app.vehicleNumber}`}
                      {app.county && ` · ${app.county}`}
                    </p>
                    <p className="text-xs text-ink-mute mt-0.5">
                      {app.email} · {app.phone}
                      {app.source === APPLICATION_SOURCES.portal && (
                        <span className="badge bg-primary/10 text-primary ml-2">Submitted by their Care Point</span>
                      )}
                    </p>
                    {app.note && (
                      <p className="text-xs text-ink-soft mt-2 leading-relaxed italic">“{app.note}”</p>
                    )}
                  </div>
                  <div className="flex gap-2 flex-shrink-0">
                    <button onClick={() => setRejecting(app)} disabled={busyId === app.id}
                            className="btn-ghost !py-1.5 !text-xs">
                      Reject
                    </button>
                    <button onClick={() => approve(app)} disabled={busyId === app.id}
                            className="btn-primary !py-1.5 !text-xs">
                      {busyId === app.id ? 'Approving…' : 'Approve & invite'}
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {rejecting && (
        <RejectDialog
          app={rejecting}
          busy={busyId === rejecting.id}
          onCancel={() => setRejecting(null)}
          onConfirm={note => reject(rejecting, note)}
        />
      )}
    </section>
  )
}

function RejectDialog({ app, busy, onCancel, onConfirm }) {
  const [note, setNote] = useState('')
  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-cream-card rounded-3xl shadow-2xl w-full max-w-md p-6">
        <h2 className="font-bold tracking-tight text-ink">Reject {app.name}?</h2>
        <p className="text-sm text-ink-soft mt-2 leading-relaxed">
          Say why. Their Care Point sees this note in their portal, and it is the
          only explanation anyone gets.
        </p>
        <textarea
          rows={3}
          className="input mt-4"
          value={note}
          onChange={e => setNote(e.target.value)}
          placeholder="Licence number could not be verified against the register."
          autoFocus
        />
        <div className="flex gap-3 mt-5">
          <button onClick={onCancel} className="btn-outline flex-1 justify-center">Cancel</button>
          <button onClick={() => onConfirm(note)} disabled={busy} className="btn-danger flex-1 justify-center">
            {busy ? 'Rejecting…' : 'Reject application'}
          </button>
        </div>
      </div>
    </div>
  )
}
