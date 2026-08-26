import { Navigate, Outlet } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { Nav } from './Nav'
import { LoadingSpinner } from './LoadingSpinner'

export function Layout() {
  const { user, loading } = useAuth()

  if (loading) return <LoadingSpinner />
  if (!user) return <Navigate to="/login" replace />

  return (
    <div className="min-h-screen bg-slate-50 flex flex-col">
      <Nav />
      <main className="flex-1 w-full max-w-7xl mx-auto px-6 py-8">
        <Outlet />
      </main>
    </div>
  )
}
