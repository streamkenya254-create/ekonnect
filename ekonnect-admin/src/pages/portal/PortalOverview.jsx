import { useOutletContext, Link } from 'react-router-dom'
import { dutySummary } from '../../hooks/useCarePoint'
import { vehicleDutyState } from '../../data/fleet'

/**
 * What a Care Point administrator needs at a glance: is anyone actually on
 * duty right now, is anything blocking them, and what has the facility done
 * lately.
 */
export default function PortalOverview() {
  const { carePoint, crew, vehicles, jobs, pendingCrew } = useOutletContext()
  const duty = dutySummary(crew)

  const fleet = vehicles.map(v => ({ ...v, state: vehicleDutyState(v, crew) }))
  const readyVehicles = fleet.filter(v => v.state.key === 'on_duty' || v.state.key === 'on_call').length
  const openJobs = jobs.filter(j => j.status !== 'resolved' && j.status !== 'cancelled').length
  const resolved = jobs.filter(j => j.status === 'resolved').length

  const blockers = []
  if (carePoint?.verificationStatus !== 'verified') {
    blockers.push('This Care Point is not verified yet, so no emergencies are being routed to it.')
  }
  if (duty.verified === 0) {
    blockers.push('No verified crew. Register crew and an eKonnect administrator will approve them.')
  } else if (duty.onDuty === 0) {
    blockers.push('Nobody is on duty. Crews go on duty from the responder app.')
  }
  if (vehicles.length === 0) {
    blockers.push('No vehicles registered yet.')
  }

  return (
    <div className="px-4 sm:px-8 lg:px-12 py-8">
      <div className="page-header">
        <div>
          <span className="eyebrow">Today</span>
          <h1 className="page-title mt-2">{carePoint?.name ?? 'Your Care Point'}</h1>
          <p className="page-subtitle">
            {carePoint?.town ? `${carePoint.town}, ${carePoint.county}` : carePoint?.county}
          </p>
        </div>
        {carePoint?.acceptingCases === false && (
          <span className="badge bg-amber-100 text-amber-800 !px-3 !py-1.5">Not accepting cases</span>
        )}
      </div>

      {blockers.length > 0 && (
        <div className="mb-6 rounded-2xl border border-amber-200 bg-amber-50/70 p-5">
          <p className="text-sm font-bold text-amber-900 mb-2">
            {blockers.length === 1 ? 'One thing needs attention' : `${blockers.length} things need attention`}
          </p>
          <ul className="space-y-1.5">
            {blockers.map(b => (
              <li key={b} className="text-sm text-amber-900/80 leading-relaxed flex gap-2.5">
                <span className="text-amber-500 font-bold">·</span>{b}
              </li>
            ))}
          </ul>
        </div>
      )}

      <div className="grid sm:grid-cols-2 xl:grid-cols-4 gap-4">
        <Stat label="Crew on duty" value={duty.onDuty} of={duty.verified} sub="verified and available" />
        <Stat label="Vehicles ready" value={readyVehicles} of={vehicles.length} sub="crewed and in service" />
        <Stat label="Open jobs" value={openJobs} sub="accepted, not yet resolved" tone={openJobs > 0 ? 'busy' : 'idle'} />
        <Stat label="Resolved" value={resolved} sub="in the last 100 jobs" />
      </div>

      <div className="grid xl:grid-cols-2 gap-5 mt-5">
        <section className="panel">
          <div className="flex items-start justify-between gap-4">
            <div>
              <span className="eyebrow">Fleet</span>
              <h2 className="text-2xl font-bold tracking-tightest mt-2">Right now</h2>
            </div>
            <Link to="/portal/fleet" className="btn-outline !py-2 !text-xs">Manage fleet</Link>
          </div>

          {fleet.length === 0 ? (
            <Empty>No vehicles registered. Add your first from the Fleet page.</Empty>
          ) : (
            <ul className="mt-6 space-y-2">
              {fleet.slice(0, 6).map(v => (
                <li key={v.id} className="flex items-center gap-3 rounded-xl bg-cream px-4 py-3">
                  <span className="font-mono font-semibold text-sm text-ink">{v.plate}</span>
                  <span className="text-xs text-ink-mute truncate flex-1">{v.make || ''}</span>
                  <DutyPill state={v.state} />
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="panel">
          <div className="flex items-start justify-between gap-4">
            <div>
              <span className="eyebrow">Recent work</span>
              <h2 className="text-2xl font-bold tracking-tightest mt-2">Last jobs</h2>
            </div>
            <Link to="/portal/jobs" className="btn-outline !py-2 !text-xs">All jobs</Link>
          </div>

          {jobs.length === 0 ? (
            <Empty>No jobs yet. They appear here the moment one of your crews accepts an emergency.</Empty>
          ) : (
            <ul className="mt-6 space-y-2">
              {jobs.slice(0, 6).map(j => (
                <li key={j.id} className="flex items-center gap-3 rounded-xl bg-cream px-4 py-3">
                  <span className="text-sm font-semibold capitalize text-ink">{j.type}</span>
                  <span className="text-xs text-ink-mute truncate flex-1">
                    {j.assignedToName ?? 'Unassigned'}
                  </span>
                  <span className="text-xs text-ink-mute">{when(j.createdAt)}</span>
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>

      {pendingCrew.length > 0 && (
        <div className="mt-5 panel">
          <span className="eyebrow">Waiting on eKonnect</span>
          <h2 className="text-2xl font-bold tracking-tightest mt-2">
            {pendingCrew.length} crew {pendingCrew.length === 1 ? 'application' : 'applications'} under review
          </h2>
          <p className="text-sm text-ink-soft mt-2 max-w-lg leading-relaxed">
            A network administrator checks every licence before a crew can take
            calls. You will see them appear under Crew once approved.
          </p>
          <Link to="/portal/crew" className="btn-primary mt-5">Review your submissions</Link>
        </div>
      )}
    </div>
  )
}

function Stat({ label, value, of, sub, tone }) {
  return (
    <div className="panel !p-6">
      <p className="text-xs font-semibold tracking-[0.14em] uppercase text-ink-mute">{label}</p>
      <p className="mt-3 flex items-baseline gap-2">
        <span className={`text-5xl font-bold tracking-tightest leading-none tabular-nums ${
          tone === 'busy' ? 'text-primary' : 'text-ink'
        }`}>
          {value}
        </span>
        {of !== undefined && <span className="text-lg font-semibold text-ink-mute">/ {of}</span>}
      </p>
      <p className="text-xs text-ink-mute mt-2.5 leading-relaxed">{sub}</p>
    </div>
  )
}

export function DutyPill({ state }) {
  const tones = {
    good:  'bg-success/10 text-success',
    busy:  'bg-primary/10 text-primary',
    idle:  'bg-ink/[0.06] text-ink-mute',
    warn:  'bg-amber-100 text-amber-800',
    muted: 'bg-ink/[0.06] text-ink-mute line-through',
  }
  return (
    <span className={`badge flex-shrink-0 ${tones[state.tone] ?? tones.idle}`}>{state.label}</span>
  )
}

export function Empty({ children }) {
  return <p className="mt-6 text-sm text-ink-mute leading-relaxed">{children}</p>
}

export function when(ts) {
  const d = ts?.toDate ? ts.toDate() : ts ? new Date(ts) : null
  if (!d || Number.isNaN(d.getTime())) return ''
  return d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short' })
}
