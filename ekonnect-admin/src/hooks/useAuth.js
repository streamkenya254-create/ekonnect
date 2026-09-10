import { useState, useEffect } from 'react'
import { onAuthStateChanged } from 'firebase/auth'
import { doc, getDoc } from 'firebase/firestore'
import { auth, db } from '../firebase'

/** Roles allowed to sign in to this web app at all. */
export const WEB_ROLES = {
  admin: 'admin',                       // the whole network
  carePoint: 'care_point_admin',        // one facility, via /portal
}

/**
 * Who is signed in, and what they are allowed to see.
 *
 * Two roles reach this app now: a network administrator, and a Care Point
 * administrator scoped to a single facility by `teamId`. Everyone else — app
 * users, responders — is signed straight back out, because this is not their
 * front door.
 */
export function useAuth() {
  const [user, setUser] = useState(null)
  const [loading, setLoading] = useState(true)
  const [authError, setAuthError] = useState('')

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (firebaseUser) => {
      if (!firebaseUser) {
        setUser(null)
        setLoading(false)
        return
      }

      try {
        const snap = await getDoc(doc(db, 'users', firebaseUser.uid))
        const data = snap.data()
        const role = data?.role

        if (role === WEB_ROLES.admin) {
          setAuthError('')
          setUser({ ...firebaseUser, ...data, isAdmin: true, isCarePoint: false })
        } else if (role === WEB_ROLES.carePoint && data?.teamId) {
          // A Care Point administrator without a teamId has nothing to
          // administer — treat it as a misconfiguration rather than letting
          // them into an empty portal wondering what is broken.
          setAuthError('')
          setUser({ ...firebaseUser, ...data, isAdmin: false, isCarePoint: true })
        } else {
          await auth.signOut()
          setUser(null)
          setAuthError(
            role === WEB_ROLES.carePoint
              ? 'This Care Point account is not linked to a facility yet. Ask the eKonnect team to finish setting it up.'
              : 'This account does not have access to the console.',
          )
        }
      } catch {
        await auth.signOut()
        setUser(null)
        setAuthError('Could not verify your account. Check your connection and try again.')
      }
      setLoading(false)
    })
    return unsub
  }, [])

  return { user, loading, authError }
}
