import { useState, useRef, useEffect, useCallback } from 'react'
import { GoogleMap, useJsApiLoader, Marker, InfoWindow } from '@react-google-maps/api'
import { useIncidents } from '../hooks/useIncidents'
import { INCIDENT_META, STATUS_META, timeAgo } from '../utils/formatters'

const GOOGLE_MAPS_KEY = 'AIzaSyDKHnoJTRRT45f369O51QQ_ZV5tbx3fXYc'
const mapContainerStyle = { width: '100%', height: '100%' }
const defaultCenter = { lat: -1.286389, lng: 36.817223 }

/// A teardrop pin in the incident's own colour, with a pulse ring when the call
/// is still unanswered so pending emergencies stand out at a glance.
function pinFor(incident) {
  const colour = INCIDENT_META[incident.type]?.color ?? '#3D1152'
  const pending = incident.status === 'pending'
  const svg = `
<svg xmlns="http://www.w3.org/2000/svg" width="46" height="58" viewBox="0 0 46 58">
  ${pending ? `<circle cx="23" cy="21" r="20" fill="${colour}" opacity="0.18"/>` : ''}
  <path d="M23 4c-7.7 0-14 6.3-14 14 0 10.5 14 26 14 26s14-15.5 14-26c0-7.7-6.3-14-14-14z"
        fill="${colour}" stroke="#ffffff" stroke-width="3"/>
  <circle cx="23" cy="18" r="5.5" fill="#ffffff"/>
</svg>`.trim()

  return {
    url: `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(svg)}`,
    scaledSize: new window.google.maps.Size(46, 58),
    anchor: new window.google.maps.Point(23, 52),
  }
}

const mapStyles = [
  { featureType: 'poi', elementType: 'labels', stylers: [{ visibility: 'off' }] },
]

export default function Dashboard() {
  const { incidents, loading, updateStatus } = useIncidents('active')
  const [selected, setSelected] = useState(null)
  const [mobileTab, setMobileTab] = useState('map')

  const { isLoaded } = useJsApiLoader({ googleMapsApiKey: GOOGLE_MAPS_KEY })
  const mapRef = useRef(null)

  const onMapLoad = useCallback(map => { mapRef.current = map }, [])

  const fitToIncidents = useCallback(() => {
    const map = mapRef.current
    if (!map || !window.google) return
    const pts = incidents.filter(
      i => Number.isFinite(i.userLat) && Number.isFinite(i.userLng) &&
           !(i.userLat === 0 && i.userLng === 0),
    )
    if (pts.length === 0) return
    if (pts.length === 1) {
      map.setCenter({ lat: pts[0].userLat, lng: pts[0].userLng })
      map.setZoom(14)
      return
    }
    const bounds = new window.google.maps.LatLngBounds()
    pts.forEach(i => bounds.extend({ lat: i.userLat, lng: i.userLng }))
    map.fitBounds(bounds, 80)
  }, [incidents])

  // Frame whatever is actually happening.
  //
  // The map used to be pinned to Nairobi at zoom 12, so an incident anywhere
  // else — Kakamega is ~350 km away — sat far outside the viewport. The marker
  // was being drawn the whole time; nobody could see it. An admin should never
  // have to hunt the country for a live emergency.
  const withCoords = incidents.filter(
    i => Number.isFinite(i.userLat) && Number.isFinite(i.userLng) &&
         !(i.userLat === 0 && i.userLng === 0),
  )

  useEffect(() => {
    const map = mapRef.current
    if (!map || !window.google || withCoords.length === 0) return

    if (withCoords.length === 1) {
      map.setCenter({ lat: withCoords[0].userLat, lng: withCoords[0].userLng })
      map.setZoom(14)
      return
    }
    const bounds = new window.google.maps.LatLngBounds()
    withCoords.forEach(i => bounds.extend({ lat: i.userLat, lng: i.userLng }))
    map.fitBounds(bounds, 80)
  }, [withCoords.map(i => `${i.id}:${i.userLat},${i.userLng}`).join('|')])

  const stats = {
    pending:  incidents.filter(i => i.status === 'pending').length,
    active:   incidents.filter(i => ['assigned', 'en_route', 'arrived'].includes(i.status)).length,
    total:    incidents.length,
  }

  const mapEl = (
    <div className="relative w-full h-full">
      {isLoaded ? (
        <GoogleMap
          mapContainerStyle={mapContainerStyle}
          center={defaultCenter}
          zoom={12}
          onLoad={onMapLoad}
          options={{ disableDefaultUI: false, zoomControl: true, styles: mapStyles }}
        >
          {withCoords.map(inc => (
            <Marker
              key={inc.id}
              position={{ lat: inc.userLat, lng: inc.userLng }}
              // Drawn inline rather than fetched from maps.google.com over
              // plain http — the site is https, so those icon requests were
              // mixed content and blocked by the browser.
              icon={pinFor(inc)}
              title={`${INCIDENT_META[inc.type]?.label ?? inc.type} · ${inc.userName ?? ''}`}
              onClick={() => setSelected(inc)}
            />
          ))}
          {selected && (
            <InfoWindow
              position={{ lat: selected.userLat, lng: selected.userLng }}
              onCloseClick={() => setSelected(null)}
            >
              <div className="text-sm p-1 min-w-[160px]">
                <p className="font-bold text-base mb-2">
                  {INCIDENT_META[selected.type]?.emoji} {INCIDENT_META[selected.type]?.label}
                </p>
                <div className="space-y-0.5 text-gray-700">
                  <p><span className="text-gray-400">User:</span> {selected.userName}</p>
                  <p><span className="text-gray-400">Phone:</span> {selected.userPhone}</p>
                  <p><span className="text-gray-400">Status:</span> {STATUS_META[selected.status]?.label}</p>
                  <p><span className="text-gray-400">Time:</span> {timeAgo(selected.createdAt)}</p>
                  {selected.assignedToName && (
                    <p><span className="text-gray-400">Responder:</span> {selected.assignedToName}</p>
                  )}
                </div>
              </div>
            </InfoWindow>
          )}
        </GoogleMap>
      ) : (
        <div className="flex items-center justify-center h-full bg-slate-100">
          <div className="text-center">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary mx-auto mb-2" />
            <p className="text-gray-400 text-sm">Loading map…</p>
          </div>
        </div>
      )}

      {/* Floating stat chips */}
      <div className="absolute top-3 left-3 flex flex-wrap gap-2">
        <StatChip label="Pending" value={stats.pending} color="bg-amber-500" />
        <StatChip label="Active"  value={stats.active}  color="bg-blue-600" />
        <StatChip label="Total"   value={stats.total}   color="bg-gray-700" />
        {withCoords.length > 0 && (
          <button
            onClick={fitToIncidents}
            className="bg-white text-gray-700 text-xs px-3 py-1.5 rounded-lg shadow-md flex items-center gap-1.5 hover:bg-gray-50 transition-colors font-medium"
          >
            ⤢ Show all
          </button>
        )}
      </div>

      {/* An incident with no usable coordinates can never appear on the map,
          so say so rather than letting the count and the map disagree. */}
      {incidents.length > withCoords.length && (
        <div className="absolute bottom-3 left-3 bg-amber-50 border border-amber-200 text-amber-800 text-xs px-3 py-2 rounded-lg shadow-sm max-w-xs">
          {incidents.length - withCoords.length} incident
          {incidents.length - withCoords.length > 1 ? 's have' : ' has'} no
          location and cannot be mapped.
        </div>
      )}
    </div>
  )

  const listEl = (
    <div className="flex flex-col h-full bg-white">
      <div className="px-4 py-3.5 border-b border-gray-100 flex items-center justify-between flex-shrink-0">
        <div>
          <h2 className="font-semibold text-gray-900 text-sm">Live Incidents</h2>
          <p className="text-xs text-gray-400 mt-0.5">{incidents.length} active</p>
        </div>
        <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
      </div>
      <div className="flex-1 overflow-y-auto">
        {loading && (
          <div className="flex items-center justify-center h-32">
            <div className="animate-spin rounded-full h-7 w-7 border-b-2 border-primary" />
          </div>
        )}
        {!loading && incidents.length === 0 && (
          <div className="flex flex-col items-center justify-center h-40 text-gray-400">
            <span className="text-4xl mb-2">✅</span>
            <p className="text-sm">No active incidents</p>
          </div>
        )}
        {incidents.map(inc => (
          <IncidentRow
            key={inc.id}
            incident={inc}
            isSelected={selected?.id === inc.id}
            onClick={() => setSelected(inc)}
            onUpdateStatus={updateStatus}
          />
        ))}
      </div>
    </div>
  )

  return (
    <>
      {/* Desktop layout */}
      <div className="hidden lg:flex h-full">
        <div className="flex-1">{mapEl}</div>
        <div className="w-80 border-l border-gray-100 flex flex-col">{listEl}</div>
      </div>

      {/* Mobile layout — tabs */}
      <div className="lg:hidden flex flex-col h-full">
        <div className="flex border-b border-gray-200 bg-white flex-shrink-0">
          {['map', 'list'].map(tab => (
            <button
              key={tab}
              onClick={() => setMobileTab(tab)}
              className={`flex-1 py-3 text-sm font-semibold capitalize transition-colors ${
                mobileTab === tab
                  ? 'text-primary border-b-2 border-primary'
                  : 'text-gray-400 hover:text-gray-600'
              }`}
            >
              {tab === 'map' ? '🗺️ Map' : `📋 Incidents (${incidents.length})`}
            </button>
          ))}
        </div>
        <div className="flex-1 overflow-hidden">
          {mobileTab === 'map' ? mapEl : listEl}
        </div>
      </div>
    </>
  )
}

function StatChip({ label, value, color }) {
  return (
    <div className={`${color} text-white text-xs px-3 py-1.5 rounded-lg shadow-md flex items-center gap-1.5 backdrop-blur`}>
      <span className="font-bold text-sm">{value}</span>
      <span className="opacity-80">{label}</span>
    </div>
  )
}

function IncidentRow({ incident: inc, isSelected, onClick, onUpdateStatus }) {
  const meta  = INCIDENT_META[inc.type] || {}
  const sMeta = STATUS_META[inc.status] || {}

  return (
    <div
      onClick={onClick}
      className={`px-4 py-3.5 border-b border-gray-50 cursor-pointer transition-colors ${
        isSelected
          ? 'bg-purple-50 border-l-[3px] border-l-primary'
          : 'hover:bg-gray-50/80 border-l-[3px] border-l-transparent'
      }`}
    >
      <div className="flex items-start gap-2.5">
        <img src={meta.icon} alt="" className="w-7 h-7 object-contain mt-0.5 flex-shrink-0" />
        <div className="flex-1 min-w-0">
          <div className="flex items-center justify-between gap-2 mb-0.5">
            <span className="font-semibold text-sm text-gray-800 truncate">{meta.label}</span>
            <span
              className="badge flex-shrink-0 text-xs"
              style={{ color: sMeta.color, backgroundColor: sMeta.bg }}
            >
              {sMeta.label}
            </span>
          </div>
          <p className="text-xs text-gray-500 truncate">{inc.userName}</p>
          <div className="flex items-center justify-between mt-1">
            <p className="text-xs text-gray-400">{timeAgo(inc.createdAt)}</p>
            {inc.assignedToName && (
              <p className="text-xs text-blue-600 truncate max-w-[100px]">👤 {inc.assignedToName}</p>
            )}
          </div>
        </div>
      </div>
      {inc.status === 'pending' && (
        <button
          onClick={e => { e.stopPropagation(); onUpdateStatus(inc.id, 'cancelled') }}
          className="mt-2 text-xs text-red-500 hover:text-red-700 font-medium bg-red-50 hover:bg-red-100 px-2.5 py-1 rounded-lg transition-colors"
        >
          Cancel
        </button>
      )}
    </div>
  )
}
