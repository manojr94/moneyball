import { NavLink, useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'

export function Nav() {
  const { user, logout } = useAuth()
  const navigate = useNavigate()

  async function handleLogout() {
    await logout()
    navigate('/login')
  }

  return (
    <nav className="nav">
      <div className="nav-brand">Moneyball</div>
      <ul className="nav-links">
        <li>
          <NavLink to="/employees" className={({ isActive }) => (isActive ? 'active' : '')}>
            Employees
          </NavLink>
        </li>
        <li>
          <NavLink to="/analytics" className={({ isActive }) => (isActive ? 'active' : '')}>
            Analytics
          </NavLink>
        </li>
        <li>
          <NavLink to="/bands" className={({ isActive }) => (isActive ? 'active' : '')}>
            Bands
          </NavLink>
        </li>
      </ul>
      <div className="nav-user">
        <span>{user?.name}</span>
        <button onClick={handleLogout} className="btn-link">
          Sign out
        </button>
      </div>
    </nav>
  )
}
