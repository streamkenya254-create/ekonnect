import { useState } from 'react'
import { useOutletContext } from 'react-router-dom'
import { Timestamp } from 'firebase/firestore'
import { coverState } from '../../hooks/useCarePoint'
import { withTimeout } from '../../utils/withTimeout'
import { Empty } from './PortalOverview'

/**
 * The clients registered with this Care Point, and the state of their cover.
 *
 * eKonnect takes no payment and holds no money — clients pay the facility
 * directly, off the platform. That makes this page the only place cover
 * becomes real: until someone here records the dates, a registered client is
 * only *asking* to be covered, and the app tells them so.
 */
export default function PortalSubscribers() {
  const { carePoint, subscribers, setCover } = useOutletContext()
  const [busy, setBusy] = useState(null)
  const [error, setError] = useState('')

  const days = Number(carePoint?.coverDays) || 30
  const price = carePoint?.coverPrice

  const rows = [...subscribers].sort((a, b) => {
    // Anyone waiting to be switched on comes first — they have paid, or think
    // they have, and are currently uncovered.
    const rank = s => (coverState(s).label === 'Awaiting payment' ? 0
      : coverState(s).label === 'Expired' ? 1 : 2)
    return rank(a) - rank(b)
  })

  const waiting = rows.filter(s => coverState(s).label === 'Awaiting payment').length

  /** Extends from whichever is later: today, or the cover they already have. */
  async function extend(sub) {
    setBusy(sub.id)
    setError('')
    try {
      const current = sub.expiresAt?.toDate?.() ?? null
      const from = current && current > new Date() ? current : new Date()
      const until = new Date(from)
      until.setDate(until.getDate() + days)
      await withTimeout(
        setCover(sub.id, Timestamp.fromDate(until)),
        15000,
        'Setting cover',
      )
    } catch (e) {
      setError(e.message ?? 'Could not set cover.')
    } finally {
      setBusy(null)
    }
  }

  /** Ends cover now — for a client who has not paid, or a refund. */
  async function endNow(sub) {
    setBusy(sub.id)
    setError('')
    try {
      await withTimeout(
        setCover(sub.id, Timestamp.fromDate(new Date())),
        15000,
        'Ending cover',
      )
    } catch (e) {
      setError(e.message ?? 'Could not end cover.')
    } finally {
      setBusy(null)
    }
  }

  const tones = {
    good: 'bg-success/10 text-success',
    warn: 'bg-amber-100 text-amber-800',
    bad: 'bg-emergency/10 text-emergency',
  }

  return (
    <div className="px-4 sm:px-8 lg:px-12 py-8">
      <div className="page-header">
        <div>
          <span className="eyebrow block mb-2">Clients</span>
          <p className="page-subtitle max-w-xl">
            People whose emergencies come to you and no one else. Their cover
            is only active once you record that they have paid.
          </p>
        </div>
      </div>

      {error && (
        <div className="mb-6 rounded-2xl border border-emergency/25 bg-emergency/[0.06] px-4 py-3.5 text-sm text-ink-soft">
          {error}
        </div>
      )}

      {carePoint?.visibility !== 'private' && (
        <div className="mb-6 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3.5 text-sm text-ink-soft leading-relaxed">
          You are a public Care Point, so clients cannot register with you
          exclusively. Switch to private on the Facility page if you sell your
          own cover.
        </div>
      )}

      {(!carePoint?.coverPrice || !carePoint?.payBill) && carePoint?.visibility === 'private' && (
        <div className="mb-6 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3.5 text-sm text-ink-soft leading-relaxed">
          Your price and paybill are not set, so the app cannot tell a client
          how to pay you. Add them under <strong>Cover</strong> on the Facility
          page.
        </div>
      )}

      <section className="panel">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <span className="eyebrow">Registered</span>
            <h2 className="text-2xl font-bold tracking-tightest mt-2">
              {rows.length} {rows.length === 1 ? 'client' : 'clients'}
            </h2>
            <p className="text-sm text-ink-soft mt-2 leading-relaxed max-w-2xl">
              {waiting > 0
                ? `${waiting} ${waiting === 1 ? 'is' : 'are'} waiting for you to confirm payment. Until then their SOS still goes to the public network.`
                : 'Everyone here has cover dates recorded.'}
            </p>
          </div>
          <div className="text-right">
            <p className="text-xs text-ink-mute">Each confirmation adds</p>
            <p className="text-lg font-bold text-ink">
              {days} days{price ? ` · KSh ${price}` : ''}
            </p>
          </div>
        </div>

        {rows.length === 0 ? (
          <Empty>
            No clients yet. Anyone who registers with you in the app appears
            here.
          </Empty>
        ) : (
          <ul className="mt-6 space-y-2">
            {rows.map(s => {
              const st = coverState(s)
              const gone = s.status === 'cancelled'
              return (
                <li
                  key={s.id}
                  className="flex flex-wrap items-center gap-3 rounded-xl bg-cream px-4 py-3"
                >
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-semibold text-ink truncate">
                      {s.userName || s.userId}
                    </p>
                    {s.userPhone && (
                      <p className="text-xs text-ink-mute truncate">{s.userPhone}</p>
                    )}
                    <p className="text-xs text-ink-soft mt-1 leading-relaxed">{st.sub}</p>
                  </div>
                  <span className={`badge flex-shrink-0 ${tones[st.tone]}`}>{st.label}</span>
                  {!gone && (
                    <div className="flex gap-2 flex-shrink-0">
                      <button
                        onClick={() => extend(s)}
                        disabled={busy === s.id}
                        className="btn-primary text-xs px-3 py-2 disabled:opacity-50"
                      >
                        {busy === s.id ? 'Saving…' : `Paid · +${days}d`}
                      </button>
                      {s.expiresAt && (
                        <button
                          onClick={() => endNow(s)}
                          disabled={busy === s.id}
                          className="btn-ghost text-xs px-3 py-2 disabled:opacity-50"
                        >
                          End
                        </button>
                      )}
                    </div>
                  )}
                </li>
              )
            })}
          </ul>
        )}
      </section>
    </div>
  )
}
