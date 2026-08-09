import { useState } from 'react'
import { signInWithEmailAndPassword } from 'firebase/auth'
import { auth } from '../firebase'
import { useAuth } from '../hooks/useAuth'
import { Navigate } from 'react-router-dom'

/** Maps Firebase auth codes onto something a human can act on. */
function friendlyError(code) {
  switch (code) {
    case 'auth/invalid-email':
      return 'That email address does not look right.'
    case 'auth/user-not-found':
    case 'auth/wrong-password':
    case 'auth/invalid-credential':
      return 'Email or password is incorrect.'
    case 'auth/too-many-requests':
      return 'Too many attempts. Wait a few minutes and try again.'
    case 'auth/network-request-failed':
      return 'No connection. Check your network and try again.'
    case 'auth/user-disabled':
      return 'This account has been disabled.'
    default:
      return 'Could not sign in. Please try again.'
  }
}

export default function Login() {
  const { user, authError } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  if (user) return <Navigate to="/dashboard" replace />

  async function handleSubmit(e) {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      await signInWithEmailAndPassword(auth, email.trim(), password)
    } catch (err) {
      // Say what actually went wrong. "Invalid credentials or you are not an
      // admin" was shown for network failures and lockouts too, which sends
      // people hunting for the wrong problem.
      setError(friendlyError(err?.code))
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen lg:grid lg:grid-cols-2">
      {/* Brand panel — hidden on small screens where it would just push the
          form below the fold. */}
      <aside className="relative hidden lg:flex flex-col justify-between bg-primary overflow-hidden p-12">
        <div
          className="absolute inset-0 opacity-[0.07]"
          style={{
            backgroundImage: 'url(/assets/ambulance_home.svg)',
            backgroundSize: '520px',
            backgroundPosition: 'center right',
            backgroundRepeat: 'no-repeat',
          }}
        />
        <div className="relative">
          <img src="/assets/logo.png" alt="eKonnect" className="h-16 object-contain" />
        </div>

        <div className="relative max-w-md">
          <h1 className="text-white text-3xl font-bold leading-tight">
            Emergency response,<br />coordinated.
          </h1>
          <p className="text-purple-200/80 mt-4 leading-relaxed">
            Dispatch, verify responders and follow every incident from the moment
            the SOS is pressed to the moment care is delivered.
          </p>

          <div className="mt-10 space-y-3">
            {[
              ['Live incident map', 'See every active emergency as it happens'],
              ['Verified responders', 'Only approved crews reach your patients'],
              ['Full incident journey', 'Timestamped from SOS to resolution'],
            ].map(([title, sub]) => (
              <div key={title} className="flex gap-3">
                <span className="mt-1.5 w-1.5 h-1.5 rounded-full bg-purple-300 flex-shrink-0" />
                <div>
                  <p className="text-white text-sm font-semibold">{title}</p>
                  <p className="text-purple-300/70 text-xs mt-0.5">{sub}</p>
                </div>
              </div>
            ))}
          </div>
        </div>

        <p className="relative text-purple-400/60 text-xs">
          © {new Date().getFullYear()} eKonnect · Tafiti Innovation Hub
        </p>
      </aside>

      {/* Form panel */}
      <main className="flex items-center justify-center bg-gray-50 p-6 min-h-screen lg:min-h-0">
        <div className="w-full max-w-sm">
          <div className="lg:hidden text-center mb-8">
            <div className="inline-flex items-center justify-center w-20 h-20 rounded-2xl bg-primary mb-4">
              <img src="/assets/logo.png" alt="" className="w-14 h-14 object-contain" />
            </div>
            <h1 className="text-2xl font-bold text-gray-900">eKonnect</h1>
          </div>

          <div className="mb-7">
            <h2 className="text-2xl font-bold text-gray-900">Welcome back</h2>
            <p className="text-sm text-gray-500 mt-1">
              Sign in to the admin portal to continue.
            </p>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4" noValidate>
            <div>
              <label htmlFor="email" className="block text-sm font-medium text-gray-700 mb-1.5">
                Email address
              </label>
              <input
                id="email"
                type="email"
                autoComplete="username"
                autoFocus
                value={email}
                onChange={e => setEmail(e.target.value)}
                required
                className="w-full bg-white border border-gray-200 rounded-xl px-4 py-3 text-sm placeholder:text-gray-300 focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-colors"
                placeholder="you@organisation.co.ke"
              />
            </div>

            <div>
              <label htmlFor="password" className="block text-sm font-medium text-gray-700 mb-1.5">
                Password
              </label>
              <div className="relative">
                <input
                  id="password"
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="current-password"
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  required
                  className="w-full bg-white border border-gray-200 rounded-xl px-4 py-3 pr-12 text-sm placeholder:text-gray-300 focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-colors"
                  placeholder="••••••••"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(v => !v)}
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                  className="absolute inset-y-0 right-0 px-3.5 text-gray-400 hover:text-gray-600 transition-colors text-xs font-medium"
                >
                  {showPassword ? 'Hide' : 'Show'}
                </button>
              </div>
            </div>

            {(error || authError) && (
              <div
                role="alert"
                className="flex gap-2.5 text-sm text-red-700 bg-red-50 border border-red-100 rounded-xl px-3.5 py-3"
              >
                <span aria-hidden className="mt-0.5">⚠</span>
                <span>{error || authError}</span>
              </div>
            )}

            <button
              type="submit"
              disabled={loading || !email || !password}
              className="w-full bg-primary text-white py-3.5 rounded-xl font-semibold text-sm hover:opacity-90 active:scale-[0.99] transition-all disabled:opacity-40 disabled:cursor-not-allowed flex items-center justify-center gap-2"
            >
              {loading && (
                <span className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
              )}
              {loading ? 'Signing in…' : 'Sign in'}
            </button>
          </form>

          <p className="text-center text-gray-400 text-xs mt-8 leading-relaxed">
            Admin access only. Activity on this portal is recorded.
          </p>
        </div>
      </main>
    </div>
  )
}
