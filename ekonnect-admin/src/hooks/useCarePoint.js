import { useState, useEffect } from 'react'
import {
  doc, onSnapshot, collection, query, where, orderBy, limit,
  addDoc, setDoc, deleteDoc, serverTimestamp,
} from 'firebase/firestore'
import { db } from '../firebase'

/**
 * Everything one Care Point can see about itself.
 *
 * Every query is filtered by `teamId` at the source rather than fetched wide
 * and narrowed in the browser — a portal that downloads the whole network and
 * hides most of it is not scoped, it is just quiet about it. The Firestore
 * rules enforce the same boundary independently.
 */
export function useCarePoint(teamId) {
  const [carePoint, setCarePoint] = useState(null)
  const [crew, setCrew] = useState([])
  const [vehicles, setVehicles] = useState([])
  const [jobs, setJobs] = useState([])
  const [crewApplications, setCrewApplications] = useState([])
  const [subscribers, setSubscribers] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    if (!teamId) return
    const stop = []
    let settled = 0
    const done = () => { if (++settled >= 2) setLoading(false) }

    stop.push(onSnapshot(
      doc(db, 'teams', teamId),
      snap => { setCarePoint(snap.exists() ? { id: snap.id, ...snap.data() } : null); done() },
      () => { setError('Could not load this Care Point.'); done() },
    ))

    stop.push(onSnapshot(
      query(collection(db, 'users'), where('teamId', '==', teamId)),
      snap => { setCrew(snap.docs.map(d => ({ id: d.id, ...d.data() }))); done() },
      () => done(),
    ))

    stop.push(onSnapshot(
      query(collection(db, 'vehicles'), where('teamId', '==', teamId)),
      snap => setVehicles(snap.docs.map(d => ({ id: d.id, ...d.data() }))),
      () => setVehicles([]),
    ))

    // Work done. Ordered by the field the app always writes, and capped —
    // a busy facility should not pull a year of history to draw a summary.
    stop.push(onSnapshot(
      query(
        collection(db, 'incidents'),
        where('assignedTeamId', '==', teamId),
        orderBy('createdAt', 'desc'),
        limit(100),
      ),
      snap => setJobs(snap.docs.map(d => ({ id: d.id, ...d.data() }))),
      // Missing composite index is the likely cause here, and it is worth
      // saying so plainly rather than showing an empty history.
      () => setError('Job history needs a Firestore index — ask the eKonnect team.'),
    ))

    // Every application this Care Point has ever submitted, decided or not.
    // Showing only the pending ones meant an approval or a rejection simply
    // vanished, and the facility never learned the outcome.
    stop.push(onSnapshot(
      query(collection(db, 'responderApplications'), where('teamId', '==', teamId)),
      snap => setCrewApplications(snap.docs.map(d => ({ id: d.id, ...d.data() }))),
      () => setCrewApplications([]),
    ))

    // The clients who have put their emergencies in this facility's hands.
    stop.push(onSnapshot(
      query(collection(db, 'subscriptions'), where('teamId', '==', teamId)),
      snap => setSubscribers(snap.docs.map(d => ({ id: d.id, ...d.data() }))),
      () => setSubscribers([]),
    ))

    return () => stop.forEach(fn => fn())
  }, [teamId])

  async function saveVehicle(vehicle) {
    const id = vehicle.id || `veh_${Date.now()}`
    const { id: _drop, ...rest } = vehicle
    await setDoc(
      doc(db, 'vehicles', id),
      { ...rest, teamId, updatedAt: serverTimestamp() },
      { merge: true },
    )
  }

  async function removeVehicle(id) {
    await deleteDoc(doc(db, 'vehicles', id))
  }

  async function submitCrewApplication(application, submittedBy) {
    await addDoc(collection(db, 'responderApplications'), {
      ...application,
      email: (application.email ?? '').trim().toLowerCase(),
      affiliation: 'care_point',
      teamId,
      teamName: carePoint?.name ?? '',
      status: 'pending',
      source: 'care-point',
      submittedBy: submittedBy ?? null,
      submittedAt: serverTimestamp(),
    })
  }

  /**
   * Records that a client has paid, and until when.
   *
   * eKonnect processes no money, so cover is only ever as true as this write.
   * The date is stored rather than a duration: a subscriber must be able to
   * see the day their cover ends, and a countdown computed from "30 days"
   * drifts the moment anyone edits anything.
   */
  async function setCover(subscriptionId, until) {
    await setDoc(
      doc(db, 'subscriptions', subscriptionId),
      {
        expiresAt: until,
        status: 'active',
        coverSetBy: teamId,
        coverSetAt: serverTimestamp(),
      },
      { merge: true },
    )
  }

  const pendingCrew = crewApplications.filter(a => a.status === 'pending')

  return {
    carePoint, crew, vehicles, jobs, crewApplications, pendingCrew, subscribers,
    loading, error,
    saveVehicle, removeVehicle, submitCrewApplication, setCover,
  }
}

/** Where a subscription stands right now. */
export function coverState(sub) {
  if (sub.status === 'cancelled') {
    return { label: 'Left', tone: 'bad', sub: 'This client cancelled their cover.' }
  }
  const until = sub.expiresAt?.toDate?.() ?? null
  if (!until) {
    return {
      label: 'Awaiting payment',
      tone: 'warn',
      sub: 'Registered, but no cover dates set. Set them once they have paid.',
    }
  }
  if (until < new Date()) {
    return {
      label: 'Expired',
      tone: 'bad',
      sub: `Cover ran out on ${until.toLocaleDateString()}.`,
    }
  }
  const days = Math.ceil((until - new Date()) / 86400000)
  return {
    label: days <= 7 ? `${days}d left` : 'Active',
    tone: days <= 7 ? 'warn' : 'good',
    sub: `Covered until ${until.toLocaleDateString()}.`,
  }
}

/** The crew who can actually be dispatched right now. */
export function dutySummary(crew) {
  const responders = crew.filter(c => c.role === 'ambulance' || c.role === 'practitioner')
  const verified = responders.filter(c => c.verificationStatus === 'verified')
  return {
    total: responders.length,
    verified: verified.length,
    onDuty: verified.filter(c => c.isAvailable).length,
    onCall: responders.filter(c => c.currentIncidentId).length,
    awaiting: responders.filter(c => c.verificationStatus !== 'verified').length,
  }
}
