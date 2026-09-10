import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useAuth } from './hooks/useAuth'
import Landing from './pages/Landing'
import Login from './pages/Login'
import Setup from './pages/Setup'
import RegisterCarePoint from './pages/RegisterCarePoint'
import RegisterResponder from './pages/RegisterResponder'
import Guide from './pages/Guide'
import Privacy from './pages/Privacy'
import Layout from './components/Layout'
import PortalLayout from './components/PortalLayout'
import BootScreen from './components/BootScreen'
import Dashboard from './pages/Dashboard'
import Incidents from './pages/Incidents'
import Responders from './pages/Responders'
import CarePoints from './pages/CarePoints'
import Events from './pages/Events'
import Settings from './pages/Settings'
import PortalOverview from './pages/portal/PortalOverview'
import PortalFleet from './pages/portal/PortalFleet'
import PortalCrew from './pages/portal/PortalCrew'
import PortalJobs from './pages/portal/PortalJobs'
import PortalFacility from './pages/portal/PortalFacility'
import PortalSubscribers from './pages/portal/PortalSubscribers'

/**
 * Two signed-in worlds share this app: the network console at the root, and a
 * Care Point's own portal under /portal. A route guard checks the role rather
 * than only checking for a session, so a Care Point administrator following a
 * link to /responders lands in their portal instead of somebody else's data.
 */
function RequireRole({ role, children }) {
  const { user, loading } = useAuth()
  if (loading) return <BootScreen />
  if (!user) return <Navigate to="/login" replace />

  if (role === 'admin' && !user.isAdmin) return <Navigate to="/portal" replace />
  if (role === 'carePoint' && !user.isCarePoint) return <Navigate to="/dashboard" replace />
  return children
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        {/* Public */}
        <Route path="/" element={<Landing />} />
        <Route path="/setup" element={<Setup />} />
        <Route path="/register" element={<RegisterCarePoint />} />
        <Route path="/apply" element={<RegisterResponder />} />
        <Route path="/guide" element={<Guide />} />
        <Route path="/privacy" element={<Privacy />} />
        <Route path="/login" element={<Login />} />

        {/* Network console */}
        <Route element={<RequireRole role="admin"><Layout /></RequireRole>}>
          <Route path="dashboard" element={<Dashboard />} />
          <Route path="incidents" element={<Incidents />} />
          <Route path="responders" element={<Responders />} />
          <Route path="care-points" element={<CarePoints />} />
          <Route path="events" element={<Events />} />
          <Route path="settings" element={<Settings />} />
        </Route>

        {/* Care Point portal */}
        <Route path="portal" element={<RequireRole role="carePoint"><PortalLayout /></RequireRole>}>
          <Route index element={<PortalOverview />} />
          <Route path="fleet" element={<PortalFleet />} />
          <Route path="crew" element={<PortalCrew />} />
          <Route path="jobs" element={<PortalJobs />} />
          <Route path="subscribers" element={<PortalSubscribers />} />
          <Route path="facility" element={<PortalFacility />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}
