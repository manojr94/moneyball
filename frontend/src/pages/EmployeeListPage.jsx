import { useState, useEffect, useCallback } from 'react'
import { Link } from 'react-router-dom'
import { ChevronUp, SlidersHorizontal, X } from 'lucide-react'
import { listEmployees } from '../api/employees'
import { listDepartments } from '../api/departments'
import { LoadingSpinner } from '../components/LoadingSpinner'
import { ErrorMessage } from '../components/ErrorMessage'
import { EmptyState } from '../components/EmptyState'
import { inputCls } from '../styles/shared'

const SORTABLE_COLUMNS = {
  employee_number: 'Number',
  last_name: 'Name',
  hire_date: 'Hire date',
  department: 'Department',
  job_title: 'Title',
  job_level: 'Level',
  country_code: 'Country',
  status: 'Status',
}

const STATUS_OPTIONS = ['', 'active', 'inactive', 'terminated']

const EMPTY_FILTERS = {
  status: '',
  department_id: '',
  country_code: '',
  job_title: '',
  job_level: '',
}

function activeFilterCount(filters) {
  return Object.values(filters).filter(Boolean).length
}

export function EmployeeListPage() {
  const [employees, setEmployees] = useState([])
  const [meta, setMeta] = useState({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [cursors, setCursors] = useState([null])
  const [pageIndex, setPageIndex] = useState(0)
  const [panelOpen, setPanelOpen] = useState(false)
  const [departments, setDepartments] = useState([])

  const [filters, setFilters] = useState({ ...EMPTY_FILTERS, status: 'active' })
  const [sort, setSort] = useState({ col: 'employee_number', dir: 'asc' })

  useEffect(() => {
    listDepartments()
      .then(setDepartments)
      .catch(() => {})
  }, [])

  const load = useCallback(
    async (cursor) => {
      setLoading(true)
      setError(null)
      try {
        const params = { per_page: 25, sort: sort.col, sort_dir: sort.dir }
        Object.entries(filters).forEach(([k, v]) => { if (v) params[k] = v })
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
    [filters, sort],
  )

  useEffect(() => {
    setCursors([null])
    setPageIndex(0)
    load(null)
  }, [load])

  function handleFilterChange(key, value) {
    setFilters((f) => ({ ...f, [key]: value }))
  }

  function clearFilters() {
    setFilters({ ...EMPTY_FILTERS })
  }

  function handleSortColumn(col) {
    setSort((s) => ({
      col,
      dir: s.col === col && s.dir === 'asc' ? 'desc' : 'asc',
    }))
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

  const activeCount = activeFilterCount(filters)

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-semibold text-slate-900">Employees</h2>
        <button
          onClick={() => setPanelOpen((o) => !o)}
          className="flex items-center gap-2 rounded-md border border-slate-300 bg-white px-3 py-1.5 text-sm font-medium text-slate-700 shadow-sm hover:bg-slate-50 transition-colors"
        >
          <SlidersHorizontal className="w-4 h-4" />
          {activeCount > 0 ? `Filters (${activeCount})` : 'Filters'}
        </button>
      </div>

      {panelOpen && (
        <div className="mb-4 rounded-lg border border-slate-200 bg-slate-50 p-4">
          <div className="flex flex-wrap gap-4">
            <div className="flex flex-col gap-1">
              <label className="text-xs font-medium text-slate-600">Status</label>
              <select
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

            <div className="flex flex-col gap-1">
              <label className="text-xs font-medium text-slate-600">Department</label>
              <select
                aria-label="Department filter"
                value={filters.department_id}
                onChange={(e) => handleFilterChange('department_id', e.target.value)}
                className={inputCls}
              >
                <option value="">All departments</option>
                {departments.map((d) => (
                  <option key={d.id} value={d.id}>
                    {d.name}
                  </option>
                ))}
              </select>
            </div>

            <div className="flex flex-col gap-1">
              <label className="text-xs font-medium text-slate-600">Country</label>
              <input
                type="text"
                aria-label="Country filter"
                placeholder="e.g. US"
                value={filters.country_code}
                onChange={(e) => handleFilterChange('country_code', e.target.value.toUpperCase())}
                className={`${inputCls} w-24`}
                maxLength={2}
              />
            </div>

            <div className="flex flex-col gap-1">
              <label className="text-xs font-medium text-slate-600">Job title</label>
              <input
                type="text"
                aria-label="Job title filter"
                placeholder="e.g. Engineer"
                value={filters.job_title}
                onChange={(e) => handleFilterChange('job_title', e.target.value)}
                className={`${inputCls} w-40`}
              />
            </div>

            <div className="flex flex-col gap-1">
              <label className="text-xs font-medium text-slate-600">Level</label>
              <input
                type="text"
                aria-label="Job level filter"
                placeholder="e.g. L4"
                value={filters.job_level}
                onChange={(e) => handleFilterChange('job_level', e.target.value)}
                className={`${inputCls} w-24`}
                maxLength={4}
              />
            </div>

            {activeCount > 0 && (
              <div className="flex items-end">
                <button
                  onClick={clearFilters}
                  className="flex items-center gap-1 text-sm text-slate-500 hover:text-slate-800 transition-colors"
                >
                  <X className="w-3.5 h-3.5" />
                  Clear all
                </button>
              </div>
            )}
          </div>
        </div>
      )}

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
                        {sort.col === col ? (
                          <ChevronUp
                            className={`w-3.5 h-3.5 text-indigo-600 transition-transform ${sort.dir === 'desc' ? 'rotate-180' : ''}`}
                          />
                        ) : (
                          <ChevronUp className="w-3.5 h-3.5 opacity-0 group-hover:opacity-40" />
                        )}
                      </span>
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {employees.map((e) => (
                  <tr key={e.id} className="hover:bg-slate-50 transition-colors">
                    <td className="px-4 py-3">
                      <Link
                        to={`/employees/${e.id}`}
                        className="text-indigo-600 hover:text-indigo-800 hover:underline font-medium"
                      >
                        {e.employee_number}
                      </Link>
                    </td>
                    <td className="px-4 py-3 text-slate-900">
                      {e.last_name}, {e.first_name}
                    </td>
                    <td className="px-4 py-3 text-slate-600">{e.hire_date}</td>
                    <td className="px-4 py-3 text-slate-600">{e.department?.name}</td>
                    <td className="px-4 py-3 text-slate-600">{e.job_title}</td>
                    <td className="px-4 py-3 text-slate-600">{e.job_level}</td>
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
