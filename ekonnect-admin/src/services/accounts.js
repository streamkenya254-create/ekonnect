import { initializeApp, getApp, getApps } from 'firebase/app'
import {
  getAuth, createUserWithEmailAndPassword, sendPasswordResetEmail, signOut,
} from 'firebase/auth'
import { doc, setDoc, getDocs, query, collection, where, limit, serverTimestamp } from 'firebase/firestore'
import { db, firebaseConfig } from '../firebase'

/**
 * Creating logins for other people, from the browser, without signing yourself
 * out.
 *
 * `createUserWithEmailAndPassword` signs the *new* user in on whichever Firebase
 * app it is called on — so calling it on the main app would boot the
 * administrator out of their own session mid-task. A second, named app instance
 * shares the project but keeps its own auth state, so the new account is created
 * there and immediately signed out again. The administrator never notices.
 *
 * No password is ever emailed or shown. The account is created with a random
 * one nobody keeps, and Firebase sends the person a link to set their own —
 * which is a real email, sent by Firebase, with no backend of ours involved.
 */
const SECONDARY = 'account-minting'

function secondaryAuth() {
  const app = getApps().find(a => a.name === SECONDARY)
    ?? initializeApp(firebaseConfig, SECONDARY)
  return getAuth(app)
}

/** A password nobody needs to remember, because nobody is told it. */
function throwawayPassword() {
  const bytes = crypto.getRandomValues(new Uint8Array(18))
  return 'Ek!' + btoa(String.fromCharCode(...bytes)).replace(/[^A-Za-z0-9]/g, '') + '9z'
}

/**
 * Finds the `users` document for an email, if somebody already signed up with
 * it. Returns null when nobody has.
 */
export async function findUserByEmail(email) {
  const clean = (email ?? '').trim().toLowerCase()
  if (!clean) return null
  const snap = await getDocs(
    query(collection(db, 'users'), where('email', '==', clean), limit(1)),
  )
  return snap.empty ? null : { id: snap.docs[0].id, ...snap.docs[0].data() }
}

/**
 * Ensures there is a login for `email` carrying `profile`, then emails them a
 * link to set their password and reach the site.
 *
 * Returns `{ uid, created, emailed }` — `created` false means the person
 * already had an account and it was updated in place rather than duplicated.
 */
export async function provisionAccount({ email, profile, continueUrl }) {
  const clean = (email ?? '').trim().toLowerCase()
  if (!clean) throw new Error('An email address is required to create a login.')

  const existing = await findUserByEmail(clean)
  let uid = existing?.id
  let created = false

  if (!uid) {
    const auth2 = secondaryAuth()
    try {
      const cred = await createUserWithEmailAndPassword(auth2, clean, throwawayPassword())
      uid = cred.user.uid
      created = true
    } catch (e) {
      // Signed up in the app already but with no `users` document yet, or
      // signed up under a differently-cased address. Either way the account
      // exists, so fall through to the reset email and let them in.
      if (e?.code !== 'auth/email-already-in-use') throw e
    } finally {
      // Never leave the minted session hanging around in this tab.
      await signOut(auth2).catch(() => {})
    }
  }

  if (uid) {
    await setDoc(
      doc(db, 'users', uid),
      { ...profile, email: clean, updatedAt: serverTimestamp() },
      { merge: true },
    )
  }

  // Firebase sends this one itself. `continueUrl` is where the link drops them
  // once the password is set, so the email effectively carries the portal link.
  let emailed = true
  try {
    await sendPasswordResetEmail(getAuth(getApp()), clean, {
      url: continueUrl ?? `${window.location.origin}/login`,
      handleCodeInApp: false,
    })
  } catch {
    emailed = false
  }

  return { uid, created, emailed }
}

/** Re-sends the set-your-password email, for when the first one is lost. */
export async function resendInvite(email, continueUrl) {
  await sendPasswordResetEmail(getAuth(getApp()), (email ?? '').trim().toLowerCase(), {
    url: continueUrl ?? `${window.location.origin}/login`,
    handleCodeInApp: false,
  })
}
