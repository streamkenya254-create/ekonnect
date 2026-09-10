import { useState } from 'react'
import { signInWithEmailAndPassword } from 'firebase/auth'
import { auth } from '../firebase'
import { useAuth } from '../hooks/useAuth'
import { Navigate, Link } from 'react-router-dom'
import BootScreen from '../components/BootScreen'

// ─────────────────────────────────────────────────────────────────────────
// DEMO PREFILL — REMOVE BEFORE PRODUCTION
//
// Investors are sent straight to this page and should not have to hunt for
// credentials, so the shared demo account is filled in and they can press
// Sign in. This ships a real password in the client bundle, where anyone can
// read it — that is the deliberate trade while the console holds no live
// patient data.
//
// To remove: delete this block and the banner below it. The two useState
// initialisers fall back to '' on their own.
const DEMO = {
  email: 'ekonnectadmin@gmail.com',
  password: 'Ekonnect@2026',
}
// ─────────────────────────────────────────────────────────────────────────

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
  const [email, setEmail] = useState(DEMO?.email ?? '')
  const [password, setPassword] = useState(DEMO?.password ?? '')
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  // Land people where their role can actually do something. A Care Point
  // administrator sent to /dashboard would only bounce off the guard.
  if (user) return <Navigate to={user.isAdmin ? '/dashboard' : '/portal'} replace />

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
    <div className="min-h-screen bg-cream text-ink font-sans antialiased lg:grid lg:grid-cols-[1.05fr_1fr]">
      {/* Covers the wait between submitting and the dashboard mounting. It
          fades in on a delay, so a rejected password surfaces its error
          instead of flashing a loader first. */}
      {loading && <BootScreen label="Signing you in" className="ek-boot-in" />}
      {/* ── Brand panel ──────────────────────────────────────────────────
          Hidden on small screens, where it would only push the form below
          the fold. Same photograph-and-scrim treatment as the landing hero,
          so arriving here does not feel like a different product. */}
      <aside className="relative hidden lg:flex flex-col justify-between overflow-hidden p-14 text-white">
        <img
          src="/assets/photos/crew-scene.jpg"
          alt=""
          className="absolute inset-0 w-full h-full object-cover"
        />
        <div className="absolute inset-0 bg-primary/70 mix-blend-multiply" />
        <div className="absolute inset-0 bg-gradient-to-br from-ink/95 via-ink/80 to-ink/40" />

        {/* logo-white is the disc mark on its own. logo.png bakes a small
            "eKonnect" wordmark into the artwork, so at 40px it printed an
            illegible second wordmark right next to the real one. */}
        <Link to="/" className="relative flex items-center gap-4 w-fit group">
          <img src="/assets/logo-white.png" alt="" className="w-16 h-16 object-contain" />
          <span className="font-bold text-3xl tracking-tightest">eKonnect</span>
        </Link>

        {/* One statement, nothing to read past it. The feature list that sat
            here competed with the form for attention on a page where there is
            only one thing to do. */}
        <div className="relative max-w-lg">
          <h1 className="text-5xl xl:text-6xl font-bold tracking-tightest leading-[1.02]">
            Emergency response,<br />coordinated.
          </h1>
          <p className="mt-6 text-lg text-white/60 leading-relaxed max-w-md">
            Dispatch crews, verify responders and follow every incident from the
            moment the SOS is pressed to the moment care is delivered.
          </p>
        </div>

        <p className="relative text-xs text-white/40">
          © {new Date().getFullYear()} eKonnect ·{' '}
          <a
            href="https://tafitirnihub.co.ke"
            target="_blank"
            rel="noopener noreferrer"
            className="hover:text-white/80 underline decoration-white/20 underline-offset-2 transition-colors"
          >
            Tafiti Research &amp; Innovation Hub
          </a>
        </p>
      </aside>

      {/* ── Form panel ───────────────────────────────────────────────────── */}
      <main className="relative flex items-center justify-center p-6 sm:p-10 min-h-screen lg:min-h-0">
        {/* A way back to the public site — people land here from the hero and
            need an exit that is not the browser's back button. */}
        <Link
          to="/"
          className="absolute top-6 right-6 sm:top-8 sm:right-8 inline-flex items-center gap-2 text-sm font-semibold
                     text-ink-mute hover:text-ink transition-colors"
        >
          <svg className="w-4 h-4 rotate-180" viewBox="0 0 24 24" fill="none" stroke="currentColor"
               strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M5 12h14m0 0l-6-6m6 6l-6 6" />
          </svg>
          Back to site
        </Link>

        <div className="w-full max-w-md">
          <div className="lg:hidden text-center mb-10">
            <img src="/assets/logo-purple.png" alt="" className="w-20 h-20 object-contain mx-auto" />
          </div>

          <span className="block text-xs font-semibold tracking-[0.16em] uppercase text-primary">
            Admin console
          </span>
          <h2 className="lp-display text-4xl sm:text-5xl mt-3">Welcome back</h2>
          <p className="mt-3 text-ink-soft leading-relaxed">
            Sign in to dispatch, verify crews and follow live incidents.
          </p>

          {/* DEMO PREFILL — REMOVE BEFORE PRODUCTION (see DEMO above). Says
              out loud that the fields are pre-filled, so a real administrator
              signing in knows to clear them rather than wondering whose
              session they have landed in. */}
          {DEMO && (
            <div className="mt-8 flex gap-3 rounded-2xl border border-ink/[0.07] bg-cream-card px-4 py-3.5">
              <span className="mt-1.5 w-2 h-2 rounded-full bg-block-coral flex-shrink-0 animate-pulse" />
              <p className="text-sm text-ink-soft leading-relaxed">
                <strong className="font-semibold text-ink">Demo access pre-filled.</strong>{' '}
                Press Sign in to explore the console. Shared account — anything
                you change is visible to everyone.
              </p>
            </div>
          )}

          <form onSubmit={handleSubmit} className="mt-8 space-y-5" noValidate>
            <div>
              <label htmlFor="email" className="block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2">
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
                placeholder="you@organisation.co.ke"
                className="w-full bg-cream-card border border-ink/15 rounded-xl px-4 py-3.5 text-sm
                           placeholder:text-ink-mute/60 focus:outline-none focus:border-primary
                           focus:ring-4 focus:ring-primary/10 transition-all"
              />
            </div>

            <div>
              <label htmlFor="password" className="block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2">
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
                  placeholder="••••••••"
                  className="w-full bg-cream-card border border-ink/15 rounded-xl px-4 py-3.5 pr-16 text-sm
                             placeholder:text-ink-mute/60 focus:outline-none focus:border-primary
                             focus:ring-4 focus:ring-primary/10 transition-all"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(v => !v)}
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                  className="absolute inset-y-0 right-0 px-4 text-xs font-semibold text-ink-mute
                             hover:text-ink transition-colors"
                >
                  {showPassword ? 'Hide' : 'Show'}
                </button>
              </div>
            </div>

            {(error || authError) && (
              <div
                role="alert"
                className="flex gap-3 text-sm rounded-xl border border-emergency/25 bg-emergency/[0.06] px-4 py-3.5"
              >
                <svg className="w-4 h-4 mt-0.5 flex-shrink-0 text-emergency" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM9 9a1 1 0 012 0v4a1 1 0 11-2 0V9zm1-4a1 1 0 100 2 1 1 0 000-2z" clipRule="evenodd" />
                </svg>
                <span className="text-ink-soft leading-relaxed">{error || authError}</span>
              </div>
            )}

            <button
              type="submit"
              disabled={loading || !email || !password}
              className="w-full inline-flex items-center justify-center gap-2 bg-ink text-cream py-4 rounded-xl
                         text-sm font-semibold tracking-tight hover:bg-block-plum hover:gap-3
                         active:scale-[0.99] disabled:opacity-30 disabled:cursor-not-allowed
                         disabled:hover:bg-ink disabled:hover:gap-2 transition-all duration-300"
            >
              {loading && (
                <span className="w-4 h-4 border-2 border-cream/30 border-t-cream rounded-full animate-spin" />
              )}
              {loading ? 'Signing in…' : 'Sign in'}
              {!loading && (
                <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor"
                     strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M5 12h14m0 0l-6-6m6 6l-6 6" />
                </svg>
              )}
            </button>
          </form>

          <p className="mt-8 text-xs text-ink-mute leading-relaxed">
            Admin access only. Activity on this portal is recorded.
          </p>
        </div>
      </main>
    </div>
  )
}
