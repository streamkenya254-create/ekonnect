import { useState, useEffect } from 'react'
import { onAuthStateChanged } from 'firebase/auth'
import { doc, getDoc } from 'firebase/firestore'
import { auth, db } from '../firebase'

export function useAuth() {
  const [user, setUser] = useState(null)
  const [loading, setLoading] = useState(true)
  const [authError, setAuthError] = useState('')

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (firebaseUser) => {
      if (firebaseUser) {
        // Check admin role in Firestore
        const snap = await getDoc(doc(db, 'users', firebaseUser.uid))
        const data = snap.data()
        if (data?.role === 'admin') {
          setAuthError('')
          setUser({ ...firebaseUser, ...data })
        } else {
          // Not an admin — sign out
          await auth.signOut()
          setUser(null)
          setAuthError('This account does not have admin access.')
        }
      } else {
        setUser(null)
      }
      setLoading(false)
    })
    return unsub
  }, [])

  return { user, loading, authError }
}
