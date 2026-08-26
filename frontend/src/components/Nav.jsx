import { NavLink } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'

export function Nav() {
  const { user, logout } = useAuth()

  async function handleLogout() {
    await logout()
  }

  return (
    <nav className="relative z-10 bg-slate-900 text-white h-14 flex items-center gap-8 px-6 shrink-0">
      <div className="font-bold text-base text-indigo-300 whitespace-nowrap">Moneyball</div>
      <ul className="flex gap-1 flex-1 list-none m-0 p-0">
        <li>
          <NavLink
            to="/employees"
            className={({ isActive }) =>
              isActive
                ? 'text-white bg-slate-700 px-3 py-1.5 rounded text-sm font-medium'
                : 'text-slate-300 hover:text-white hover:bg-slate-700 px-3 py-1.5 rounded text-sm transition-colors'
            }
          >
            Employees
          </NavLink>
        </li>
        <li>
          <NavLink
            to="/analytics"
            className={({ isActive }) =>
              isActive
                ? 'text-white bg-slate-700 px-3 py-1.5 rounded text-sm font-medium'
                : 'text-slate-300 hover:text-white hover:bg-slate-700 px-3 py-1.5 rounded text-sm transition-colors'
            }
          >
            Analytics
          </NavLink>
        </li>
        <li>
          <NavLink
            to="/bands"
            className={({ isActive }) =>
              isActive
                ? 'text-white bg-slate-700 px-3 py-1.5 rounded text-sm font-medium'
                : 'text-slate-300 hover:text-white hover:bg-slate-700 px-3 py-1.5 rounded text-sm transition-colors'
            }
          >
            Bands
          </NavLink>
        </li>
        {user?.role === 'hr_admin' && (
          <li>
            <NavLink
              to="/import"
              className={({ isActive }) =>
                isActive
                  ? 'text-white bg-slate-700 px-3 py-1.5 rounded text-sm font-medium'
                  : 'text-slate-300 hover:text-white hover:bg-slate-700 px-3 py-1.5 rounded text-sm transition-colors'
              }
            >
              Import
            </NavLink>
          </li>
        )}
      </ul>
      <div className="flex items-center gap-4 text-sm text-slate-300">
        <span>{user?.name}</span>
        <button
          type="button"
          onClick={handleLogout}
          className="cursor-pointer text-slate-300 hover:text-white underline underline-offset-2 transition-colors"
        >
          Sign out
        </button>
      </div>
    </nav>
  )
}
