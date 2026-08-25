import { useState, useEffect, useCallback } from 'react'
import { Link } from 'react-router-dom'
import { ChevronUp } from 'lucide-react'
import { listEmployees } from '../api/employees'
import { LoadingSpinner } from '../components/LoadingSpinner'
import { ErrorMessage } from '../components/ErrorMessage'
import { EmptyState } from '../components/EmptyState'

const SORTABLE_COLUMNS = {
  employee_number: 'Number',
  last_name: 'Name',
  hire_date: 'Hire date',
}

const STATUS_OPTIONS = ['', 'active', 'inactive', 'terminated']

export function EmployeeListPage() {
  const [employees, setEmployees] = useState([])
  const [meta, setMeta] = useState({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [cursors, setCursors] = useState([null])
  const [pageIndex, setPageIndex] = useState(0)

  const [filters, setFilters] = useState({
    status: 'active',
    sort: 'last_name',
  })

  const load = useCallback(
    async (cursor) => {
      setLoading(true)
      setError(null)
      try {
        const params = { ...filters, per_page: 25 }
        if (cursor) params.cursor = cursor
        const result = await listEmployees(params)
        setEmployees(result.data)
        setMeta(result.meta)
      } catch (e) {
        setError(e.message)
      } finally {
        setLoading(false)
      }
    },
    [filters],
  )

  useEffect(() => {
    setCursors([null])
    setPageIndex(0)
    load(null)
  }, [load])

  function handleFilterChange(key, value) {
    setFilters((f) => ({ ...f, [key]: value }))
  }

  function handleSortColumn(col) {
    setFilters((f) => ({ ...f, sort: col }))
  }

  function nextPage() {
    const next = meta.next_cursor
    if (!next) return
    const newCursors = [...cursors.slice(0, pageIndex + 1), next]
    setCursors(newCursors)
    setPageIndex(pageIndex + 1)
    load(next)
  }

  function prevPage() {
    if (pageIndex === 0) return
    const newIndex = pageIndex - 1
    setPageIndex(newIndex)
    load(cursors[newIndex])
  }

  const inputCls =
    'rounded-md border border-slate-300 px-3 py-1.5 text-sm text-slate-900 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 bg-white'

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-semibold text-slate-900">Employees</h2>
      </div>

      <div className="flex flex-wrap gap-4 mb-4">
        <div className="flex items-center gap-2">
          <label htmlFor="status-filter" className="text-sm font-medium text-slate-700">
            Status
          </label>
          <select
            id="status-filter"
            aria-label="Status filter"
            value={filters.status}
            onChange={(e) => handleFilterChange('status', e.target.value)}
            className={inputCls}
          >
            {STATUS_OPTIONS.map((s) => (
              <option key={s} value={s}>
                {s === '' ? 'All' : s.charAt(0).toUpperCase() + s.slice(1)}
              </option>
            ))}
          </select>
        </div>
      </div>

      {error && <ErrorMessage message={error} />}

      {loading ? (
        <LoadingSpinner />
      ) : employees.length === 0 ? (
        <EmptyState message="No employees match the current filters." />
      ) : (
        <>
          <div className="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm">
            <table className="min-w-full divide-y divide-slate-200 text-sm">
              <thead className="bg-slate-50">
                <tr>
                  {Object.entries(SORTABLE_COLUMNS).map(([col, label]) => (
                    <th
                      key={col}
                      className="px-4 py-3 text-left font-medium text-slate-600 cursor-pointer select-none hover:text-slate-900 group"
                      onClick={() => handleSortColumn(col)}
                    >
                      <span className="flex items-center gap-1">
                        {label}
                        <ChevronUp
                          className={`w-3.5 h-3.5 transition-opacity ${filters.sort === col ? 'opacity-100 text-indigo-600' : 'opacity-0 group-hover:opacity-40'}`}
                        />
                      </span>
                    </th>
                  ))}
                  <th className="px-4 py-3 text-left font-medium text-slate-600">Department</th>
                  <th className="px-4 py-3 text-left font-medium text-slate-600">Title / Level</th>
                  <th className="px-4 py-3 text-left font-medium text-slate-600">Country</th>
                  <th className="px-4 py-3 text-left font-medium text-slate-600">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {employees.map((e) => (
                  <tr key={e.id} className="hover:bg-slate-50 transition-colors">
                    <td className="px-4 py-3">
                      <Link to={`/employees/${e.id}`} className="text-indigo-600 hover:text-indigo-800 hover:underline font-medium">
                        {e.employee_number}
                      </Link>
                    </td>
                    <td className="px-4 py-3 text-slate-900">
                      {e.last_name}, {e.first_name}
                    </td>
                    <td className="px-4 py-3 text-slate-600">{e.hire_date}</td>
                    <td className="px-4 py-3 text-slate-600">{e.department?.name}</td>
                    <td className="px-4 py-3 text-slate-600">
                      {e.job_title} · {e.job_level}
                    </td>
                    <td className="px-4 py-3 text-slate-600">{e.country_code}</td>
                    <td className="px-4 py-3">
                      <span className={`status-badge status-${e.status}`}>{e.status}</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="flex items-center justify-between mt-4">
            <button
              onClick={prevPage}
              disabled={pageIndex === 0}
              className="rounded-md border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 shadow-sm hover:bg-slate-50 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
            >
              Previous
            </button>
            <span className="text-sm text-slate-600">Page {pageIndex + 1}</span>
            <button
              onClick={nextPage}
              disabled={!meta.next_cursor}
              className="rounded-md border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 shadow-sm hover:bg-slate-50 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
            >
              Next
            </button>
          </div>
        </>
      )}
    </div>
  )
}
