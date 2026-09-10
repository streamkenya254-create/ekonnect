import { useState, useEffect } from 'react'
import { Outlet, NavLink, useLocation } from 'react-router-dom'
import { signOut } from 'firebase/auth'
import { auth } from '../firebase'
import { useAuth } from '../hooks/useAuth'
import {
  IconDashboard, IconIncidents, IconResponders,
  IconTeams, IconSettings, IconX, IconLogout,
} from './Icons'

const navItems = [
  { path: 'dashboard',  label: 'Dashboard',  Icon: IconDashboard },
  { path: 'incidents',  label: 'Incidents',   Icon: IconIncidents },
  { path: 'responders', label: 'Responders',  Icon: IconResponders },
  { path: 'care-points', label: 'Care Points',  Icon: IconTeams },
  { path: 'events',     label: 'Events',      Icon: IconTeams },
  { path: 'settings',   label: 'Settings',    Icon: IconSettings },
]

const pageTitles = {
  dashboard:  'Dashboard',
  incidents:  'Incidents',
  responders: 'Responders',
  'care-points': 'Care Points',
  events:     'Trending Events',
  settings:   'Settings',
}

export default function Layout() {
  const { user } = useAuth()
  const [open, setOpen] = useState(false)
  const location = useLocation()

  const segment = location.pathname.split('/')[1] || 'dashboard'
  const title = pageTitles[segment] ?? 'eKonnect'

  // Close drawer on route change
  useEffect(() => setOpen(false), [location.pathname])

  const initials = user?.name
    ? user.name.split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase()
    : user?.email?.[0]?.toUpperCase() ?? 'A'

  return (
    <div className="flex h-screen overflow-hidden bg-cream">

      {/* Mobile backdrop */}
      {open && (
        <div
          className="fixed inset-0 bg-black/40 z-20 lg:hidden"
          onClick={() => setOpen(false)}
        />
      )}

      {/* Sidebar */}
      <aside className={`
        fixed inset-y-0 left-0 z-30 w-64 flex flex-col
        bg-ink
        transform transition-transform duration-300 ease-in-out
        lg:relative lg:translate-x-0 lg:flex-shrink-0
        ${open ? 'translate-x-0' : '-translate-x-full'}
      `}>
        {/* Logo */}
        <div className="flex items-center justify-between px-5 py-5 border-b border-white/10">
          <div>
            <div className="flex items-center gap-2.5">
              {/* logo.png is white artwork on transparency, so it only reads
                  against the dark sidebar. On any light ground use the purple
                  cut of the same mark: /assets/logo-purple.png. */}
              <img
                src="/assets/logo-white.png"
                alt=""
                className="w-9 h-9 object-contain"
              />
              <span className="text-white font-bold text-xl tracking-tightest">eKonnect</span>
            </div>
            <p className="text-white/35 text-[11px] font-semibold tracking-[0.16em] uppercase mt-1.5 ml-12">Admin console</p>
          </div>
          <button
            onClick={() => setOpen(false)}
            className="lg:hidden text-white/60 hover:text-white transition-colors"
          >
            <IconX className="w-5 h-5" />
          </button>
        </div>

        {/* Nav */}
        <nav className="flex-1 px-3 py-4 space-y-0.5 overflow-y-auto">
          {navItems.map(({ path, label, Icon }) => (
            <NavLink
              key={path}
              to={`/${path}`}
              className={({ isActive }) =>
                `flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-sm font-medium transition-all ${
                  isActive
                    ? 'bg-cream text-ink shadow-sm'
                    : 'text-white/55 hover:bg-white/10 hover:text-white'
                }`
              }
            >
              {({ isActive }) => (
                <>
                  <Icon className={`w-5 h-5 flex-shrink-0 ${isActive ? 'text-primary' : ''}`} />
                  <span>{label}</span>
                </>
              )}
            </NavLink>
          ))}
        </nav>

        {/* User footer */}
        <div className="px-3 pb-4 border-t border-white/10 pt-3">
          <div className="flex items-center gap-3 px-2 py-2 rounded-xl hover:bg-white/5 transition-colors">
            <div className="w-9 h-9 rounded-full bg-white/20 flex items-center justify-center text-white text-sm font-bold flex-shrink-0">
              {initials}
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-white text-sm font-medium truncate">
                {user?.name ?? 'Admin'}
              </p>
              <p className="text-white/40 text-xs truncate">{user?.email}</p>
            </div>
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

      {/* Main area */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {/* Top bar */}
        <header className="flex items-center gap-4 px-4 sm:px-8 h-[4.5rem] bg-cream/85 backdrop-blur-xl border-b border-ink/[0.06] flex-shrink-0 sticky top-0 z-10">
          {/* Page name leads, menu button closes. Each page used to print
              this same word in its own header, so "Dashboard" appeared twice
              within 60px of itself — the bar is now the only place it lives. */}
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tightest text-ink truncate">
            {title}
          </h1>
          <div className="ml-auto flex items-center gap-3 sm:gap-4 flex-shrink-0">
            <div className="hidden sm:flex items-center gap-2 text-xs bg-success/10 text-success px-3 py-1.5 rounded-full font-semibold tracking-wide">
              <span className="w-1.5 h-1.5 rounded-full bg-success animate-pulse" />
              Live
            </div>
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

        {/* Page content */}
        <main className="flex-1 overflow-auto">
          <Outlet />
        </main>
      </div>
    </div>
  )
}
