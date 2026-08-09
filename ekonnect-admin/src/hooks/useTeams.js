import { useState, useEffect } from 'react'
import { collection, onSnapshot, doc, setDoc, deleteDoc } from 'firebase/firestore'
import { db } from '../firebase'

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
    await setDoc(doc(db, 'teams', id), { ...team, id: undefined })
  }

  async function deleteTeam(id) {
    await deleteDoc(doc(db, 'teams', id))
  }

  return { teams, loading, saveTeam, deleteTeam }
}
