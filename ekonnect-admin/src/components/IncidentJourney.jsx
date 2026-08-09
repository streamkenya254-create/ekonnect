/**
 * The full journey of an emergency, with the durations an admin needs.
 *
 * Mirrors the Flutter `IncidentJourneyView` on purpose — the patient and the
 * admin must be looking at the same account of the same emergency. If these two
 * ever disagree, the audit is worthless.
 */

const EVENT_META = {
  created:      { label: 'SOS raised',            dot: 'bg-rose-500' },
  accepted:     { label: 'Responder accepted',    dot: 'bg-violet-500' },
  en_route:     { label: 'On the way',            dot: 'bg-violet-500' },
  arrived:      { label: 'Reached patient',       dot: 'bg-violet-500' },
  referred:     { label: 'Referred',              dot: 'bg-violet-500' },
  departed_for: { label: 'Left for care point',   dot: 'bg-violet-500' },
  arrived_at:   { label: 'Arrived at care point', dot: 'bg-emerald-500' },
  declined:     { label: 'Turned away',           dot: 'bg-red-500' },
  resolved:     { label: 'Resolved',              dot: 'bg-emerald-500' },
  cancelled:    { label: 'Cancelled',             dot: 'bg-red-500' },
}

// Incidents written before the event log existed stored a bare status.
const LEGACY = {
  pending: 'created',
  assigned: 'accepted',
  en_route: 'en_route',
  arrived: 'arrived',
  resolved: 'resolved',
  cancelled: 'cancelled',
  referred: 'referred',
}

function parseEvents(timeline = []) {
  return timeline
    .map(e => {
      const at = new Date(e.timestamp ?? e.at)
      if (isNaN(at)) return null
      const raw = e.event ?? e.status ?? 'update'
      return {
        type: LEGACY[raw] ?? raw,
        at,
        note: e.note ?? null,
        carePoint: e.carePointName ?? e.carePoint ?? null,
        actorName: e.actorName ?? null,
      }
    })
    .filter(Boolean)
    .sort((a, b) => a.at - b.at)
}

function fmtDuration(ms) {
  if (ms == null || ms < 0) return '—'
  const secs = Math.round(ms / 1000)
  if (secs < 60) return `${secs} sec`
  const mins = Math.round(secs / 60)
  if (mins < 60) return `${mins} min`
  return `${Math.floor(mins / 60)}h ${String(mins % 60).padStart(2, '0')}m`
}

const time = d => d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
const day = d => d.toLocaleDateString([], { day: 'numeric', month: 'short' })

export default function IncidentJourney({ incident }) {
  const events = parseEvents(incident.timeline)
  const first = t => events.find(e => e.type === t)?.at ?? null
  const last = t => [...events].reverse().find(e => e.type === t)?.at ?? null

  const raised = first('created') ?? (incident.createdAt?.toDate?.() ?? null)
  const accepted = first('accepted')
  const reached = first('arrived')
  const closed = last('resolved') ?? last('cancelled')
  const departed = first('departed_for')

  const gap = (a, b) => (a && b ? b - a : null)

  const legs = []
  events.forEach((e, i) => {
    if (e.type !== 'departed_for') return
    const arrival = events
      .slice(i + 1)
      .find(l => l.type === 'arrived_at' && l.carePoint === e.carePoint)
    legs.push({ carePoint: e.carePoint, departed: e.at, arrived: arrival?.at ?? null })
  })

  const declined = events.filter(e => e.type === 'declined').length

  const metrics = [
    ['Waited for a responder', fmtDuration(gap(raised, accepted))],
    ['Time to reach patient', fmtDuration(gap(accepted, reached))],
    ['Total response', fmtDuration(gap(raised, reached))],
    ['On scene', fmtDuration(gap(reached, departed))],
    ['Whole incident', fmtDuration(gap(raised, closed))],
    ...legs.map(l => [
      `To ${l.carePoint}`,
      l.arrived ? fmtDuration(l.arrived - l.departed) : 'in transit',
    ]),
  ]

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
        {metrics.map(([label, value]) => (
          <div key={label} className="rounded-xl bg-gray-50 px-3 py-2">
            <p className="text-sm font-bold text-gray-900">{value}</p>
            <p className="text-[11px] text-gray-500 mt-0.5">{label}</p>
          </div>
        ))}
      </div>

      {declined > 0 && (
        <div className="rounded-xl bg-amber-50 border border-amber-200 px-3 py-2 text-xs text-amber-800">
          {declined} care point{declined > 1 ? 's' : ''} could not take this patient.
        </div>
      )}

      {events.length === 0 ? (
        <p className="text-sm text-gray-400">No journey recorded.</p>
      ) : (
        <ol className="relative">
          {events.map((e, i) => {
            const meta = EVENT_META[e.type] ?? { label: e.type, dot: 'bg-gray-400' }
            const since = i === 0 ? null : e.at - events[i - 1].at
            const label = e.carePoint
              ? e.type === 'departed_for'
                ? `Left for ${e.carePoint}`
                : e.type === 'arrived_at'
                  ? `Arrived at ${e.carePoint}`
                  : e.type === 'declined'
                    ? `${e.carePoint} could not help`
                    : `${meta.label} — ${e.carePoint}`
              : meta.label

            return (
              <li key={i} className="flex gap-3 pb-4 last:pb-0">
                <div className="flex flex-col items-center">
                  <span className={`w-3 h-3 rounded-full ${meta.dot} ring-2 ring-white`} />
                  {i < events.length - 1 && <span className="flex-1 w-px bg-gray-200 my-1" />}
                </div>
                <div className="flex-1 min-w-0 -mt-0.5">
                  <div className="flex items-baseline justify-between gap-3">
                    <p className="text-sm font-semibold text-gray-800">{label}</p>
                    <p className="text-xs font-semibold text-gray-700 whitespace-nowrap">
                      {time(e.at)}
                    </p>
                  </div>
                  <p className="text-[11px] text-gray-400 mt-0.5">
                    {day(e.at)}
                    {since != null && <span className="ml-2">+{fmtDuration(since)}</span>}
                    {e.actorName && <span className="ml-2">{e.actorName}</span>}
                  </p>
                  {e.note && (
                    <p className="mt-1.5 text-xs text-gray-700 bg-gray-50 rounded-lg px-2.5 py-1.5">
                      {e.note}
                    </p>
                  )}
                </div>
              </li>
            )
          })}
        </ol>
      )}
    </div>
  )
}
