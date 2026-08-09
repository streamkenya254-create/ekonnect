import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useAuth } from './hooks/useAuth'
import Login from './pages/Login'
import Setup from './pages/Setup'
import Layout from './components/Layout'
import Dashboard from './pages/Dashboard'
import Incidents from './pages/Incidents'
import Responders from './pages/Responders'
import Teams from './pages/Teams'
import Settings from './pages/Settings'

function PrivateRoute({ children }) {
  const { user, loading } = useAuth()
  if (loading) {
    return (
      <div className="flex items-center justify-center h-screen bg-primary">
        <div className="text-center text-white">
          <div className="text-4xl mb-4">🚨</div>
          <div className="text-xl font-bold">eKonnect Admin</div>
          <div className="mt-4 animate-pulse text-purple-300">Loading…</div>
        </div>
      </div>
    )
  }
  return user ? children : <Navigate to="/login" replace />
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/setup" element={<Setup />} />
        <Route path="/login" element={<Login />} />
        <Route
          path="/"
          element={
            <PrivateRoute>
              <Layout />
            </PrivateRoute>
          }
        >
          <Route index element={<Navigate to="/dashboard" replace />} />
          <Route path="dashboard" element={<Dashboard />} />
          <Route path="incidents" element={<Incidents />} />
          <Route path="responders" element={<Responders />} />
          <Route path="teams" element={<Teams />} />
          <Route path="settings" element={<Settings />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}
