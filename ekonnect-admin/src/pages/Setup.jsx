import { useState, useEffect } from 'react'
import { createUserWithEmailAndPassword, signInWithEmailAndPassword, deleteUser } from 'firebase/auth'
import { collection, getDocs, query, where, setDoc, doc } from 'firebase/firestore'
import { auth, db } from '../firebase'
import { Navigate } from 'react-router-dom'

function withTimeout(promise, ms, label) {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error(`Timed out at: ${label}`)), ms)
    ),
  ])
}

export default function Setup() {
  const [checking, setChecking] = useState(true)
  const [adminExists, setAdminExists] = useState(false)
  const [form, setForm] = useState({ name: '', email: '', password: '', confirm: '' })
  const [error, setError] = useState('')
  const [step, setStep] = useState('')
  const [loading, setLoading] = useState(false)
  const [done, setDone] = useState(false)

  useEffect(() => {
    async function check() {
      try {
        const snap = await withTimeout(
          getDocs(query(collection(db, 'users'), where('role', '==', 'admin'))),
          35000,
          'checking for existing admins'
        )
        setAdminExists(!snap.empty)
      } catch (e) {
        // If check fails, allow setup to proceed
      }
      setChecking(false)
    }
    check()
  }, [])

  async function handleSubmit(e) {
    e.preventDefault()
    setError('')
    setStep('')

    if (form.password !== form.confirm) return setError('Passwords do not match.')
    if (form.password.length < 6) return setError('Password must be at least 6 characters.')

    setLoading(true)
    let firebaseUser = null

    try {
      // Step 1: create or sign in to auth
      setStep('Creating auth account…')
      try {
        const cred = await withTimeout(
          createUserWithEmailAndPassword(auth, form.email, form.password),
          35000, 'createUserWithEmailAndPassword'
        )
        firebaseUser = cred.user
      } catch (authErr) {
        if (authErr.code === 'auth/email-already-in-use') {
          // Previous attempt created the user — sign in and reuse it
          setStep('Auth account exists, signing in to reuse it…')
          const cred = await withTimeout(
            signInWithEmailAndPassword(auth, form.email, form.password),
            35000, 'signInWithEmailAndPassword'
          )
          firebaseUser = cred.user
        } else {
          throw authErr
        }
      }

      // Step 2: write Firestore document
      setStep('Saving admin record to database…')
      await withTimeout(
        setDoc(doc(db, 'users', firebaseUser.uid), {
          name: form.name,
          email: form.email,
          role: 'admin',
          isSuperAdmin: true,
          createdAt: new Date().toISOString(),
        }),
        35000, 'setDoc users'
      )

      // Step 3: sign out
      setStep('Finalising…')
      await auth.signOut()
      setDone(true)

    } catch (err) {
      // Clean up dangling auth user if Firestore failed
      if (firebaseUser) {
        try { await deleteUser(firebaseUser) } catch (_) {}
      }
      setError(err.code ? `[${err.code}] ${err.message}` : err.message)
    } finally {
      setLoading(false)
      setStep('')
    }
  }

  if (checking) {
    return (
      <div className="flex items-center justify-center h-screen bg-primary">
        <div className="text-white animate-pulse text-lg">Checking setup status…</div>
      </div>
    )
  }

  if (adminExists) return <Navigate to="/login" replace />

  if (done) {
    return (
      <div className="min-h-screen bg-primary flex items-center justify-center p-4">
        <div className="bg-white rounded-2xl shadow-xl p-8 max-w-sm w-full text-center">
          <div className="text-5xl mb-4">✅</div>
          <h2 className="text-xl font-bold text-gray-800 mb-2">Super Admin Created</h2>
          <p className="text-gray-500 text-sm mb-6">
            Your account is ready. Sign in and create other admins from the portal.
          </p>
          <a
            href="/login"
            className="block w-full bg-primary text-white py-3 rounded-xl font-semibold hover:opacity-90 transition-opacity"
          >
            Go to Login
          </a>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-primary flex items-center justify-center p-4">
      <div className="w-full max-w-sm">
        <div className="text-center mb-8">
          <div className="text-6xl mb-3">🚨</div>
          <h1 className="text-3xl font-bold text-white">eKonnect</h1>
          <p className="text-purple-300 mt-1">First-time Setup</p>
        </div>

        <div className="bg-white rounded-2xl shadow-xl p-8">
          <h2 className="text-xl font-semibold text-gray-800 mb-1">Create Super Admin</h2>
          <p className="text-sm text-gray-500 mb-6">
            Only shown once — when no admin account exists yet.
          </p>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Full Name</label>
              <input
                type="text"
                value={form.name}
                onChange={e => setForm(p => ({ ...p, name: e.target.value }))}
                required
                placeholder="Your name"
                className="w-full border border-gray-300 rounded-xl px-4 py-2.5 focus:outline-none focus:ring-2 focus:ring-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Email</label>
              <input
                type="email"
                value={form.email}
                onChange={e => setForm(p => ({ ...p, email: e.target.value }))}
                required
                placeholder="admin@ekonnect.co"
                className="w-full border border-gray-300 rounded-xl px-4 py-2.5 focus:outline-none focus:ring-2 focus:ring-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Password</label>
              <input
                type="password"
                value={form.password}
                onChange={e => setForm(p => ({ ...p, password: e.target.value }))}
                required
                placeholder="Min. 6 characters"
                className="w-full border border-gray-300 rounded-xl px-4 py-2.5 focus:outline-none focus:ring-2 focus:ring-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Confirm Password</label>
              <input
                type="password"
                value={form.confirm}
                onChange={e => setForm(p => ({ ...p, confirm: e.target.value }))}
                required
                placeholder="Repeat password"
                className="w-full border border-gray-300 rounded-xl px-4 py-2.5 focus:outline-none focus:ring-2 focus:ring-primary"
              />
            </div>

            {step && (
              <p className="text-sm text-blue-600 bg-blue-50 rounded-lg px-3 py-2 animate-pulse">
                {step}
              </p>
            )}
            {error && (
              <p className="text-sm text-red-600 bg-red-50 rounded-lg px-3 py-2 break-all">
                {error}
              </p>
            )}

            <button
              type="submit"
              disabled={loading}
              className="w-full bg-primary text-white py-3 rounded-xl font-semibold hover:opacity-90 transition-opacity disabled:opacity-50"
            >
              {loading ? 'Working…' : 'Create Super Admin'}
            </button>
          </form>
        </div>

        <p className="text-center text-purple-400 text-xs mt-6">
          This page locks itself once an admin exists.
        </p>
      </div>
    </div>
  )
}
