import { Navigate, Outlet } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { Nav } from './Nav'
import { LoadingSpinner } from './LoadingSpinner'

export function Layout() {
  const { user, loading } = useAuth()

  if (loading) return <LoadingSpinner />
  if (!user) return <Navigate to="/login" replace />

  return (
    <div className="app-layout">
      <Nav />
      <main className="main-content">
        <Outlet />
      </main>
    </div>
  )
}
