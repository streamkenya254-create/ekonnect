import { useState, useEffect } from 'react'
import { collection, onSnapshot, query, orderBy, doc, updateDoc, serverTimestamp, arrayUnion } from 'firebase/firestore'
import { db } from '../firebase'

const ACTIVE_STATUSES  = ['pending', 'assigned', 'en_route', 'arrived']
const CLOSED_STATUSES  = ['resolved', 'cancelled']

export function useIncidents(filter = 'active') {
  const [incidents, setIncidents] = useState([])
  const [loading, setLoading] = useState(true)
  const [fetchError, setFetchError] = useState(null)

  useEffect(() => {
    // Single-field orderBy only — avoids composite index requirement.
    // Status filtering is done client-side.
    const q = query(collection(db, 'incidents'), orderBy('createdAt', 'desc'))

    const unsub = onSnapshot(
      q,
      (snap) => {
        const all = snap.docs.map(d => ({ id: d.id, ...d.data() }))
        const filtered =
          filter === 'active'   ? all.filter(i => ACTIVE_STATUSES.includes(i.status))
          : filter === 'resolved' ? all.filter(i => CLOSED_STATUSES.includes(i.status))
          : all
        setIncidents(filtered)
        setLoading(false)
        setFetchError(null)
      },
      (err) => {
        console.error('Firestore incidents error:', err)
        setFetchError(err.message)
        setLoading(false)
      }
    )
    return unsub
  }, [filter])

  async function updateStatus(incidentId, status) {
    await updateDoc(doc(db, 'incidents', incidentId), {
      status,
      timeline: arrayUnion({ status, timestamp: new Date().toISOString() }),
      ...(status === 'resolved' || status === 'cancelled'
        ? { resolvedAt: serverTimestamp() }
        : {}),
    })
  }

  return { incidents, loading, fetchError, updateStatus }
}
