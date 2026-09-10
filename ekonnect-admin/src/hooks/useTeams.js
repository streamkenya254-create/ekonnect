import { useState, useEffect } from 'react'
import { collection, onSnapshot, doc, setDoc, deleteDoc, serverTimestamp } from 'firebase/firestore'
import { db } from '../firebase'

/**
 * Care Points, stored in the `teams` collection.
 *
 * The collection keeps its original name because responder routing already
 * keys off `teamId` and `routedTeamId`; renaming it would orphan every
 * responder already attached to one.
 */
export function useTeams() {
  const [teams, setTeams] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const unsub = onSnapshot(collection(db, 'teams'), (snap) => {
      setTeams(snap.docs.map(d => ({ id: d.id, ...d.data() })))
      setLoading(false)
    })
    return unsub
  }, [])

  async function saveTeam(team) {
    const id = team.id || `team_${Date.now()}`
    // The document id lives in the path, not the body — and Firestore rejects
    // an explicit `undefined` value outright, so the key has to be *removed*
    // rather than blanked. `{ ...team, id: undefined }` looks like it drops
    // the field but actually sends it, which is what threw
    // "Unsupported field value: undefined (found in field id)".
    await setDoc(
      doc(db, 'teams', id),
      { ...stripUndefined(team), updatedAt: serverTimestamp() },
      // Merge so a partial save — verifying, say — cannot silently drop
      // fields that were not part of the form being submitted.
      { merge: true },
    )
    return id
  }

  async function deleteTeam(id) {
    await deleteDoc(doc(db, 'teams', id))
  }

  return { teams, loading, saveTeam, deleteTeam }
}

/**
 * Drops `id` and every key whose value is `undefined`.
 *
 * Firestore treats `undefined` as an error rather than "leave this alone", and
 * these records are assembled by spreading form state, application documents
 * and defaults together — any one of which can leave a hole.
 */
function stripUndefined(obj) {
  const out = {}
  for (const [k, v] of Object.entries(obj)) {
    if (k === 'id' || v === undefined) continue
    out[k] = v
  }
  return out
}
