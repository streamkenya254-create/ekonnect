import { useState, useEffect } from 'react'
import { Outlet, NavLink, useLocation } from 'react-router-dom'
import { signOut } from 'firebase/auth'
import { auth } from '../firebase'
import { useAuth } from '../hooks/useAuth'
import { useCarePoint } from '../hooks/useCarePoint'
import { IconDashboard, IconResponders, IconIncidents, IconTeams, IconX, IconLogout } from './Icons'
import BootScreen from './BootScreen'

/** Segment after /portal → what the bar calls this page. */
const pageTitles = {
  '':         'Overview',
  fleet:      'Fleet',
  crew:       'Crew',
  jobs:       'Jobs',
  subscribers: 'Subscribers',
  facility:   'Facility',
}

const navItems = [
  { path: 'portal',           label: 'Overview', Icon: IconDashboard, end: true },
  { path: 'portal/fleet',     label: 'Fleet',    Icon: IconTeams },
  { path: 'portal/crew',      label: 'Crew',     Icon: IconResponders },
  { path: 'portal/jobs',      label: 'Jobs',     Icon: IconIncidents },
  { path: 'portal/subscribers', label: 'Subscribers', Icon: IconResponders },
  { path: 'portal/facility',  label: 'Facility', Icon: IconTeams },
]

/**
 * The Care Point portal shell.
 *
 * Same furniture as the network console so the two do not feel like separate
 * products, but the sidebar names the facility rather than eKonnect — someone
 * working here manages one hospital, not a network, and the chrome should not
 * imply otherwise.
 */
export default function PortalLayout() {
  const { user } = useAuth()
  const scope = useCarePoint(user?.teamId)
  const [open, setOpen] = useState(false)
  const location = useLocation()

  useEffect(() => setOpen(false), [location.pathname])

  const segment = location.pathname.split('/')[2] ?? ''
  const title = pageTitles[segment] ?? 'Portal'

  if (scope.loading) return <BootScreen label="Loading your Care Point" />

  const cp = scope.carePoint

  return (
    <div className="flex h-screen overflow-hidden bg-cream">
      {open && (
        <div className="fixed inset-0 bg-black/40 z-20 lg:hidden" onClick={() => setOpen(false)} />
      )}

      <aside className={`
        fixed inset-y-0 left-0 z-30 w-64 flex flex-col bg-ink
        transform transition-transform duration-300 ease-in-out
        lg:relative lg:translate-x-0 lg:flex-shrink-0
        ${open ? 'translate-x-0' : '-translate-x-full'}
      `}>
        <div className="flex items-start justify-between gap-2 px-5 py-5 border-b border-white/10">
          <div className="min-w-0">
            <div className="flex items-center gap-2.5">
              {cp?.logo ? (
                <img src={cp.logo} alt="" className="w-9 h-9 rounded-lg object-contain bg-white/95 p-0.5 flex-shrink-0" />
              ) : (
                <img src="/assets/logo-white.png" alt="" className="w-9 h-9 object-contain flex-shrink-0" />
              )}
              <span className="text-white font-bold text-lg tracking-tightest truncate">
                {cp?.name ?? 'Care Point'}
              </span>
            </div>
            <p className="text-white/35 text-[11px] font-semibold tracking-[0.16em] uppercase mt-1.5 ml-12">
              Care Point portal
            </p>
          </div>
          <button onClick={() => setOpen(false)} className="lg:hidden text-white/60 hover:text-white transition-colors">
            <IconX className="w-5 h-5" />
          </button>
        </div>

        <nav className="flex-1 px-3 py-4 space-y-0.5 overflow-y-auto">
          {navItems.map(({ path, label, Icon, end }) => (
            <NavLink
              key={path}
              to={`/${path}`}
              end={end}
              className={({ isActive }) =>
                `flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-sm font-medium transition-all ${
                  isActive ? 'bg-cream text-ink shadow-sm' : 'text-white/55 hover:bg-white/10 hover:text-white'
                }`
              }
            >
              {({ isActive }) => (
                <>
                  <Icon className={`w-5 h-5 flex-shrink-0 ${isActive ? 'text-primary' : ''}`} />
                  <span>{label}</span>
                  {path === 'portal/crew' && scope.pendingCrew.length > 0 && (
                    <span className="ml-auto text-[10px] font-bold bg-amber-400 text-ink px-1.5 py-0.5 rounded-full">
                      {scope.pendingCrew.length}
                    </span>
                  )}
                </>
              )}
            </NavLink>
          ))}
        </nav>

        <div className="px-3 pb-4 border-t border-white/10 pt-3">
          <div className="px-2 py-2">
            <p className="text-white text-sm font-medium truncate">{user?.name ?? 'Care Point admin'}</p>
            <p className="text-white/40 text-xs truncate">{user?.email}</p>
          </div>
          <button
            onClick={() => signOut(auth)}
            className="mt-1 w-full flex items-center gap-2 px-3 py-2 text-white/50 hover:text-white hover:bg-white/10 rounded-xl text-sm font-medium transition-all"
          >
            <IconLogout className="w-4 h-4" />
            Sign out
          </button>
        </div>
      </aside>

      <div className="flex-1 flex flex-col overflow-hidden">
        <header className="flex items-center gap-4 px-4 sm:px-8 h-[4.5rem] bg-cream/85 backdrop-blur-xl border-b border-ink/[0.06] flex-shrink-0">
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tightest text-ink truncate">
            {title}
          </h1>
          <div className="ml-auto flex items-center gap-3 sm:gap-4 flex-shrink-0">
            {/* Verification state, always visible. An unverified Care Point
                receives nothing, and that should never be a surprise. */}
            {cp?.verificationStatus === 'verified' ? (
              <span className="hidden sm:flex items-center gap-2 text-xs bg-success/10 text-success px-3 py-1.5 rounded-full font-semibold">
                <span className="w-1.5 h-1.5 rounded-full bg-success" /> Verified
              </span>
            ) : (
              <span className="hidden sm:flex items-center gap-2 text-xs bg-amber-100 text-amber-800 px-3 py-1.5 rounded-full font-semibold">
                <span className="w-1.5 h-1.5 rounded-full bg-amber-500 animate-pulse" /> Awaiting verification
              </span>
            )}
            <button
              onClick={() => setOpen(true)}
              className="lg:hidden w-12 h-12 rounded-xl flex items-center justify-center flex-shrink-0
                         border border-ink/[0.12] bg-cream-card text-ink
                         hover:bg-ink hover:text-cream hover:border-ink
                         active:scale-95 transition-all duration-200"
              aria-label="Open menu"
            >
              <svg className="w-7 h-7" viewBox="0 0 24 24" fill="none" stroke="currentColor"
                   strokeWidth="2.75" strokeLinecap="round">
                <path d="M3.5 7h17" /><path d="M3.5 12h17" /><path d="M3.5 17h17" />
              </svg>
            </button>
          </div>
        </header>

        <main className="flex-1 overflow-auto">
          <Outlet context={scope} />
        </main>
      </div>
    </div>
  )
}
