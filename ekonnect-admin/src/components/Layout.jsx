import { useState, useEffect } from 'react'
import { Outlet, NavLink, useLocation } from 'react-router-dom'
import { signOut } from 'firebase/auth'
import { auth } from '../firebase'
import { useAuth } from '../hooks/useAuth'
import {
  IconDashboard, IconIncidents, IconResponders,
  IconTeams, IconSettings, IconMenu, IconX, IconLogout,
} from './Icons'

const navItems = [
  { path: 'dashboard',  label: 'Dashboard',  Icon: IconDashboard },
  { path: 'incidents',  label: 'Incidents',   Icon: IconIncidents },
  { path: 'responders', label: 'Responders',  Icon: IconResponders },
  { path: 'teams',      label: 'Teams',       Icon: IconTeams },
  { path: 'settings',   label: 'Settings',    Icon: IconSettings },
]

const pageTitles = {
  dashboard:  'Dashboard',
  incidents:  'Incidents',
  responders: 'Responders',
  teams:      'Teams',
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
    <div className="flex h-screen overflow-hidden bg-slate-50">

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
        bg-gradient-to-b from-[#3D1152] to-[#1e0830]
        transform transition-transform duration-300 ease-in-out
        lg:relative lg:translate-x-0 lg:flex-shrink-0
        ${open ? 'translate-x-0' : '-translate-x-full'}
      `}>
        {/* Logo */}
        <div className="flex items-center justify-between px-5 py-5 border-b border-white/10">
          <div>
            <div className="flex items-center gap-2.5">
              {/* The brand mark is white artwork on transparency, so it only
                  reads against the dark sidebar — never place it on white. */}
              <img
                src="/assets/logo.png"
                alt=""
                className="w-8 h-8 object-contain"
              />
              <span className="text-white font-bold text-lg tracking-tight">eKonnect</span>
            </div>
            <p className="text-purple-400 text-xs mt-1 ml-10">Admin Portal</p>
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
                    ? 'bg-white text-primary shadow-sm'
                    : 'text-purple-200 hover:bg-white/10 hover:text-white'
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
              <p className="text-purple-400 text-xs truncate">{user?.email}</p>
            </div>
          </div>
          <button
            onClick={() => signOut(auth)}
            className="mt-1 w-full flex items-center gap-2 px-3 py-2 text-purple-300 hover:text-white hover:bg-white/10 rounded-xl text-sm transition-all"
          >
            <IconLogout className="w-4 h-4" />
            Sign out
          </button>
        </div>
      </aside>

      {/* Main area */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {/* Top bar */}
        <header className="flex items-center gap-4 px-4 sm:px-6 h-16 bg-white border-b border-gray-100 flex-shrink-0">
          <button
            onClick={() => setOpen(true)}
            className="lg:hidden p-2 rounded-xl text-gray-500 hover:bg-gray-100 transition-colors"
          >
            <IconMenu className="w-5 h-5" />
          </button>
          <h1 className="text-base font-semibold text-gray-800">{title}</h1>
          <div className="ml-auto flex items-center gap-3">
            <div className="hidden sm:flex items-center gap-2 text-xs bg-green-50 text-green-700 px-3 py-1.5 rounded-full font-medium">
              <span className="w-1.5 h-1.5 rounded-full bg-green-500 animate-pulse" />
              Live
            </div>
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
