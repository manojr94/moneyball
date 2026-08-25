import { useState, useEffect, useCallback } from 'react'
import { Link } from 'react-router-dom'
import { listEmployees } from '../api/employees'
import { LoadingSpinner } from '../components/LoadingSpinner'
import { ErrorMessage } from '../components/ErrorMessage'
import { EmptyState } from '../components/EmptyState'

const SORT_OPTIONS = [
  { value: 'last_name', label: 'Last name' },
  { value: 'hire_date', label: 'Hire date' },
]

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

  return (
    <div className="page">
      <div className="page-header">
        <h2>Employees</h2>
      </div>

      <div className="filters">
        <div className="field-inline">
          <label htmlFor="status-filter">Status</label>
          <select
            id="status-filter"
            aria-label="Status filter"
            value={filters.status}
            onChange={(e) => handleFilterChange('status', e.target.value)}
          >
            {STATUS_OPTIONS.map((s) => (
              <option key={s} value={s}>
                {s === '' ? 'All' : s.charAt(0).toUpperCase() + s.slice(1)}
              </option>
            ))}
          </select>
        </div>

        <div className="field-inline">
          <label htmlFor="sort-by">Sort by</label>
          <select
            id="sort-by"
            aria-label="Sort by"
            value={filters.sort}
            onChange={(e) => handleFilterChange('sort', e.target.value)}
          >
            {SORT_OPTIONS.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
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
          <table className="table">
            <thead>
              <tr>
                <th>Number</th>
                <th>Name</th>
                <th>Department</th>
                <th>Title / Level</th>
                <th>Country</th>
                <th>Hire date</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {employees.map((e) => (
                <tr key={e.id}>
                  <td>
                    <Link to={`/employees/${e.id}`}>{e.employee_number}</Link>
                  </td>
                  <td>
                    {e.last_name}, {e.first_name}
                  </td>
                  <td>{e.department?.name}</td>
                  <td>
                    {e.job_title} · {e.job_level}
                  </td>
                  <td>{e.country_code}</td>
                  <td>{e.hire_date}</td>
                  <td>
                    <span className={`status-badge status-${e.status}`}>{e.status}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          <div className="pagination">
            <button onClick={prevPage} disabled={pageIndex === 0} className="btn">
              Previous
            </button>
            <span>Page {pageIndex + 1}</span>
            <button onClick={nextPage} disabled={!meta.next_cursor} className="btn">
              Next
            </button>
          </div>
        </>
      )}
    </div>
  )
}
