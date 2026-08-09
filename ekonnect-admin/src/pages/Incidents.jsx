import { useState } from 'react'
import { useIncidents } from '../hooks/useIncidents'
import { INCIDENT_META, STATUS_META, formatDate, timeAgo } from '../utils/formatters'
import { IconSearch } from '../components/Icons'
import IncidentJourney from '../components/IncidentJourney'

const FILTERS = [
  { key: 'active',   label: 'Active' },
  { key: 'resolved', label: 'Resolved' },
  { key: 'all',      label: 'All' },
]

export default function Incidents() {
  const [filter, setFilter] = useState('active')
  const [search, setSearch] = useState('')
  const [journey, setJourney] = useState(null)
  const { incidents, loading, fetchError, updateStatus } = useIncidents(filter)

  const filtered = incidents.filter(i =>
    i.userName?.toLowerCase().includes(search.toLowerCase()) ||
    i.type?.toLowerCase().includes(search.toLowerCase()) ||
    i.assignedToName?.toLowerCase().includes(search.toLowerCase())
  )

  return (
    <div className="p-4 sm:p-6 max-w-7xl mx-auto">
      {/* Header */}
      <div className="page-header">
        <div>
          <h1 className="page-title">Incidents</h1>
          <p className="page-subtitle">Monitor and manage all emergency incidents</p>
        </div>
        <div className="flex items-center gap-2 text-sm text-gray-500 bg-white border border-gray-100 rounded-xl px-4 py-2 shadow-sm">
          <span className="w-2 h-2 rounded-full bg-primary/80" />
          <span>{incidents.length} {filter === 'active' ? 'active' : filter}</span>
        </div>
      </div>

      {/* Error banner */}
      {fetchError && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-xl text-sm text-red-600 flex items-center gap-2">
          <span>⚠</span> Firestore error: {fetchError}
        </div>
      )}

      {/* Controls */}
      <div className="flex flex-col sm:flex-row gap-3 mb-5">
        <div className="flex bg-white rounded-xl border border-gray-200 shadow-sm p-1 gap-0.5">
          {FILTERS.map(f => (
            <button
              key={f.key}
              onClick={() => setFilter(f.key)}
              className={`px-4 py-1.5 rounded-lg text-sm font-medium transition-all ${
                filter === f.key
                  ? 'bg-primary text-white shadow-sm'
                  : 'text-gray-500 hover:text-gray-800 hover:bg-gray-50'
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>
        <div className="relative flex-1">
          <IconSearch className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            type="text"
            placeholder="Search by name, type, responder…"
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="input pl-10"
          />
        </div>
      </div>

      {/* Desktop Table */}
      <div className="table-wrapper hidden md:block">
        <table className="w-full text-sm">
          <thead className="table-head">
            <tr>
              <th className="th">Type</th>
              <th className="th">User</th>
              <th className="th">Responder</th>
              <th className="th">Status</th>
              <th className="th">Time</th>
              <th className="th">Actions</th>
            </tr>
          </thead>
          <tbody>
            {loading && (
              <tr>
                <td colSpan={6} className="td text-center py-16 text-gray-400">
                  <div className="flex justify-center">
                    <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
                  </div>
                </td>
              </tr>
            )}
            {!loading && filtered.length === 0 && (
              <tr>
                <td colSpan={6} className="td text-center py-16">
                  <div className="text-4xl mb-2">📋</div>
                  <p className="text-gray-400 text-sm">No incidents found</p>
                </td>
              </tr>
            )}
            {filtered.map(inc => {
              const meta  = INCIDENT_META[inc.type]  || {}
              const sMeta = STATUS_META[inc.status]  || {}
              return (
                <tr key={inc.id} className="tr">
                  <td className="td">
                    <div className="flex items-center gap-2">
                      <img src={meta.icon} alt="" className="w-6 h-6 object-contain" />
                      <span className="font-medium" style={{ color: meta.color }}>{meta.label}</span>
                    </div>
                  </td>
                  <td className="td">
                    <div className="font-medium text-gray-800">{inc.userName}</div>
                    <div className="text-xs text-gray-400 mt-0.5">{inc.userPhone}</div>
                  </td>
                  <td className="td">
                    {inc.assignedToName ? (
                      <>
                        <div className="font-medium text-gray-800">{inc.assignedToName}</div>
                        <div className="text-xs text-gray-400 mt-0.5">{inc.assignedToPhone}</div>
                      </>
                    ) : (
                      <span className="inline-flex items-center px-2 py-0.5 rounded-full text-xs bg-gray-100 text-gray-500">
                        Unassigned
                      </span>
                    )}
                  </td>
                  <td className="td">
                    <span className="badge" style={{ color: sMeta.color, backgroundColor: sMeta.bg }}>
                      {sMeta.label}
                    </span>
                  </td>
                  <td className="td">
                    <div className="text-gray-700">{timeAgo(inc.createdAt)}</div>
                    <div className="text-xs text-gray-400 mt-0.5">{formatDate(inc.createdAt)}</div>
                  </td>
                  <td className="td">
                    <div className="flex gap-2">
                      <button
                        onClick={() => setJourney(inc)}
                        className="text-xs font-semibold text-violet-700 hover:text-violet-900 bg-violet-50 hover:bg-violet-100 px-2.5 py-1 rounded-lg transition-colors"
                      >
                        Journey
                      </button>
                      {inc.status !== 'resolved' && inc.status !== 'cancelled' && (
                        <button
                          onClick={() => updateStatus(inc.id, 'resolved')}
                          className="text-xs font-semibold text-emerald-600 hover:text-emerald-800 bg-emerald-50 hover:bg-emerald-100 px-2.5 py-1 rounded-lg transition-colors"
                        >
                          Resolve
                        </button>
                      )}
                      {inc.status === 'pending' && (
                        <button
                          onClick={() => updateStatus(inc.id, 'cancelled')}
                          className="text-xs font-semibold text-red-500 hover:text-red-700 bg-red-50 hover:bg-red-100 px-2.5 py-1 rounded-lg transition-colors"
                        >
                          Cancel
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>

      {/* Mobile Cards */}
      <div className="md:hidden space-y-3">
        {loading && (
          <div className="flex justify-center py-16">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
          </div>
        )}
        {!loading && filtered.length === 0 && (
          <div className="card text-center py-12">
            <div className="text-4xl mb-2">📋</div>
            <p className="text-gray-400 text-sm">No incidents found</p>
          </div>
        )}
        {filtered.map(inc => {
          const meta  = INCIDENT_META[inc.type]  || {}
          const sMeta = STATUS_META[inc.status]  || {}
          return (
            <div key={inc.id} className="card">
              <div className="flex items-start justify-between mb-3">
                <div className="flex items-center gap-2">
                  <img src={meta.icon} alt="" className="w-7 h-7 object-contain" />
                  <span className="font-semibold" style={{ color: meta.color }}>{meta.label}</span>
                </div>
                <span className="badge" style={{ color: sMeta.color, backgroundColor: sMeta.bg }}>
                  {sMeta.label}
                </span>
              </div>
              <div className="grid grid-cols-2 gap-2 text-sm mb-3">
                <div>
                  <p className="text-xs text-gray-400">User</p>
                  <p className="font-medium text-gray-800">{inc.userName}</p>
                  <p className="text-xs text-gray-400">{inc.userPhone}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400">Responder</p>
                  {inc.assignedToName
                    ? <p className="font-medium text-gray-800">{inc.assignedToName}</p>
                    : <p className="text-gray-400 text-xs">Unassigned</p>
                  }
                </div>
              </div>
              <div className="flex items-center justify-between border-t border-gray-50 pt-3">
                <span className="text-xs text-gray-400">{timeAgo(inc.createdAt)}</span>
                <div className="flex gap-2">
                  <button
                    onClick={() => setJourney(inc)}
                    className="text-xs font-semibold text-violet-700 bg-violet-50 px-2.5 py-1 rounded-lg"
                  >
                    Journey
                  </button>
                  {inc.status !== 'resolved' && inc.status !== 'cancelled' && (
                    <button
                      onClick={() => updateStatus(inc.id, 'resolved')}
                      className="text-xs font-semibold text-emerald-600 bg-emerald-50 px-2.5 py-1 rounded-lg"
                    >
                      Resolve
                    </button>
                  )}
                  {inc.status === 'pending' && (
                    <button
                      onClick={() => updateStatus(inc.id, 'cancelled')}
                      className="text-xs font-semibold text-red-500 bg-red-50 px-2.5 py-1 rounded-lg"
                    >
                      Cancel
                    </button>
                  )}
                </div>
              </div>
            </div>
          )
        })}
      </div>

      {journey && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 p-0 sm:p-6">
          <div className="bg-white w-full sm:max-w-lg rounded-t-2xl sm:rounded-2xl max-h-[92vh] overflow-y-auto">
            <div className="sticky top-0 bg-white border-b border-gray-100 px-5 py-4 flex items-start justify-between">
              <div>
                <h2 className="font-bold text-gray-900">
                  {INCIDENT_META[journey.type]?.label ?? journey.type}
                </h2>
                <p className="text-xs text-gray-400 mt-0.5">
                  {journey.userName} · {formatDate(journey.createdAt)}
                </p>
              </div>
              <button
                onClick={() => setJourney(null)}
                className="text-gray-400 hover:text-gray-700 text-xl leading-none"
              >
                ×
              </button>
            </div>
            <div className="p-5">
              <IncidentJourney incident={journey} />
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
