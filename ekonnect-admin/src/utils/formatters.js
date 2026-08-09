import { formatDistanceToNow, format } from 'date-fns'

export function timeAgo(timestamp) {
  if (!timestamp) return '—'
  const date = timestamp?.toDate ? timestamp.toDate() : new Date(timestamp)
  return formatDistanceToNow(date, { addSuffix: true })
}

export function formatDate(timestamp) {
  if (!timestamp) return '—'
  const date = timestamp?.toDate ? timestamp.toDate() : new Date(timestamp)
  return format(date, 'dd MMM yyyy, HH:mm')
}

// `icon` points at the same artwork the mobile app uses, so an incident looks
// identical to the responder in the field and the admin watching them. `emoji`
// stays as a fallback for anywhere the image cannot load.
export const INCIDENT_META = {
  medical: { label: 'Medical', color: '#1976D2', bg: '#E3F2FD', emoji: '🚑', icon: '/assets/doctor.svg' },
  fire: { label: 'Fire', color: '#E64A19', bg: '#FBE9E7', emoji: '🔥', icon: '/assets/fire.svg' },
  flood: { label: 'Flood', color: '#0097A7', bg: '#E0F7FA', emoji: '🌊', icon: '/assets/flood.svg' },
  security: { label: 'Security', color: '#7B1FA2', bg: '#F3E5F5', emoji: '🚨', icon: '/assets/police.svg' },
}

export const STATUS_META = {
  pending: { label: 'Pending', color: '#FF8F00', bg: '#FFF8E1' },
  assigned: { label: 'Assigned', color: '#1976D2', bg: '#E3F2FD' },
  en_route: { label: 'En Route', color: '#0097A7', bg: '#E0F7FA' },
  arrived: { label: 'Arrived', color: '#5C6BC0', bg: '#E8EAF6' },
  resolved: { label: 'Resolved', color: '#2E7D32', bg: '#E8F5E9' },
  cancelled: { label: 'Cancelled', color: '#757575', bg: '#F5F5F5' },
}

export function getMeta(map, key, field) {
  return map[key]?.[field] ?? key
}
