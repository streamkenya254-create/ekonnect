import { useState, useMemo } from 'react'
import { useOutletContext } from 'react-router-dom'
import { Empty } from './PortalOverview'

/**
 * Work this Care Point has done.
 *
 * Read-only on purpose: an incident record is evidence, and a facility editing
 * its own response times would make the whole timeline worthless.
 */
export default function PortalJobs() {
  const { jobs, error } = useOutletContext()
  const [filter, setFilter] = useState('all')

  const shown = useMemo(() => {
    if (filter === 'open') return jobs.filter(j => j.status !== 'resolved' && j.status !== 'cancelled')
    if (filter === 'resolved') return jobs.filter(j => j.status === 'resolved')
    if (filter === 'cancelled') return jobs.filter(j => j.status === 'cancelled')
    if (filter === 'unresolved') return jobs.filter(j => j.status === 'closed_unresolved')
    return jobs
  }, [jobs, filter])

  const resolved = jobs.filter(j => j.status === 'resolved')
  const unresolved = jobs.filter(j => j.status === 'closed_unresolved')
  const median = medianMinutes(resolved)

  return (
    <div className="px-4 sm:px-8 lg:px-12 py-8">
      <div className="page-header">
        <div>
          <span className="eyebrow block mb-2">Record</span>
          <p className="page-subtitle max-w-xl">
            Every emergency one of your crews accepted, with the times the app
            recorded as it happened.
          </p>
        </div>
      </div>

      {error && (
        <div className="mb-6 rounded-2xl border border-amber-200 bg-amber-50/70 px-4 py-3.5 text-sm text-amber-900">
          {error}
        </div>
      )}

      {jobs.length > 0 && (
        <div className="grid sm:grid-cols-2 xl:grid-cols-4 gap-4 mb-6">
          <Metric label="Jobs recorded" value={jobs.length} />
          <Metric label="Resolved" value={resolved.length} />
          <Metric
            label="Closed unresolved"
            value={unresolved.length}
            sub={unresolved.length ? 'attended, could not finish' : undefined}
          />
          <Metric
            label="Median time to resolve"
            value={median === null ? '—' : `${median} min`}
            sub={median === null ? 'not enough resolved jobs yet' : `across ${resolved.length} jobs`}
          />
        </div>
      )}

      <div className="flex gap-1.5 flex-wrap mb-5">
        {[
          ['all', `All ${jobs.length}`],
          ['open', 'Open'],
          ['resolved', 'Resolved'],
          ['cancelled', 'Cancelled'],
          ['unresolved', 'Not resolved'],
        ].map(([k, label]) => (
          <button
            key={k}
            onClick={() => setFilter(k)}
            className={`px-3.5 py-2 rounded-xl text-xs font-semibold transition-all ${
              filter === k ? 'bg-ink text-cream' : 'bg-cream-card border border-ink/10 text-ink-soft hover:border-ink/30'
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      {shown.length === 0 ? (
        <div className="panel text-center py-16">
          <p className="font-semibold text-ink">Nothing here</p>
          <Empty>
            {jobs.length === 0
              ? 'Jobs appear the moment one of your crews accepts an emergency.'
              : 'No jobs match that filter.'}
          </Empty>
        </div>
      ) : (
        <div className="table-wrapper overflow-x-auto">
          <table className="w-full min-w-[720px]">
            <thead className="table-head">
              <tr>
                <th className="th">Emergency</th>
                <th className="th">Crew</th>
                <th className="th">Raised</th>
                <th className="th">Accepted</th>
                <th className="th">Resolved</th>
                <th className="th">Status</th>
              </tr>
            </thead>
            <tbody>
              {shown.map(j => (
                <tr key={j.id} className="tr">
                  <td className="td">
                    <span className="font-semibold capitalize text-ink">{j.type}</span>
                    {j.routingScope === 'private' && (
                      <span className="badge bg-amber-100 text-amber-800 ml-2">Private</span>
                    )}
                  </td>
                  <td className="td text-ink-soft">
                    {j.assignedToName ?? '—'}
                    {j.assignedToVehicleNumber && (
                      <span className="block text-xs text-ink-mute font-mono">{j.assignedToVehicleNumber}</span>
                    )}
                    {(j.assignees ?? []).length > 1 && (
                      <span className="block text-xs text-primary font-semibold mt-0.5">
                        +{j.assignees.length - 1} backup
                      </span>
                    )}
                  </td>
                  <td className="td text-ink-soft whitespace-nowrap">{stamp(j.createdAt)}</td>
                  <td className="td text-ink-soft whitespace-nowrap">{legTime(j, 'assigned')}</td>
                  <td className="td text-ink-soft whitespace-nowrap">{legTime(j, 'resolved')}</td>
                  <td className="td">
                    <StatusPill status={j.status} />
                    {j.closedReason && (
                      <span className="block text-xs text-ink-mute mt-1 max-w-[16rem]">
                        {j.closedReason}
                      </span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

function Metric({ label, value, sub }) {
  return (
    <div className="panel !p-6">
      <p className="text-xs font-semibold tracking-[0.14em] uppercase text-ink-mute">{label}</p>
      <p className="text-4xl font-bold tracking-tightest text-ink mt-3 tabular-nums">{value}</p>
      {sub && <p className="text-xs text-ink-mute mt-2">{sub}</p>}
    </div>
  )
}

function StatusPill({ status }) {
  const tones = {
    resolved:  'bg-success/10 text-success',
    cancelled: 'bg-ink/[0.06] text-ink-mute',
    closed_unresolved: 'bg-amber-100 text-amber-800',
    assigned:  'bg-primary/10 text-primary',
    en_route:  'bg-primary/10 text-primary',
    arrived:   'bg-primary/10 text-primary',
    pending:   'bg-amber-100 text-amber-800',
  }
  return (
    <span className={`badge capitalize ${tones[status] ?? 'bg-ink/[0.06] text-ink-mute'}`}>
      {(status ?? 'unknown').replace(/_/g, ' ')}
    </span>
  )
}

/** The app writes a `timeline` array of `{ status, timestamp }` as it goes. */
function legTime(job, status) {
  const entry = (job.timeline ?? []).find(t => t.status === status)
  if (!entry?.timestamp) return '—'
  const d = new Date(entry.timestamp)
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' })
}

function stamp(ts) {
  const d = ts?.toDate ? ts.toDate() : ts ? new Date(ts) : null
  if (!d || Number.isNaN(d.getTime())) return '—'
  return d.toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
}

/**
 * Median rather than mean: one job left open overnight would drag an average
 * far enough to make it meaningless.
 */
function medianMinutes(resolved) {
  const spans = resolved
    .map(j => {
      const start = (j.timeline ?? []).find(t => t.status === 'assigned')?.timestamp
      const end = (j.timeline ?? []).find(t => t.status === 'resolved')?.timestamp
      if (!start || !end) return null
      const mins = (new Date(end) - new Date(start)) / 60000
      return Number.isFinite(mins) && mins >= 0 ? mins : null
    })
    .filter(m => m !== null)
    .sort((a, b) => a - b)

  if (spans.length < 3) return null
  const mid = Math.floor(spans.length / 2)
  const value = spans.length % 2 ? spans[mid] : (spans[mid - 1] + spans[mid]) / 2
  return Math.round(value)
}
