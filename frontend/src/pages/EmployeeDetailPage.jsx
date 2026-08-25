import { useState, useCallback } from 'react'
import { useParams, Link } from 'react-router-dom'
import { getEmployee, listSalaries } from '../api/employees'
import { useApi } from '../hooks/useApi'
import { useAuth } from '../contexts/AuthContext'
import { LoadingSpinner } from '../components/LoadingSpinner'
import { ErrorMessage } from '../components/ErrorMessage'
import { EmptyState } from '../components/EmptyState'
import { RaiseForm } from '../components/RaiseForm'
import { formatMoney } from '../utils/money'

const thCls = 'px-4 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wide'
const tdCls = 'px-4 py-3 text-sm text-slate-700'

export function EmployeeDetailPage() {
  const { id } = useParams()
  const { user } = useAuth()
  const isAdmin = user?.role === 'hr_admin'
  const [showRaiseForm, setShowRaiseForm] = useState(false)

  const employeeFetch = useCallback(() => getEmployee(id), [id])
  const { data: employee, loading: empLoading, error: empError } = useApi(employeeFetch, [id])

  const salariesFetch = useCallback(() => listSalaries(id), [id])
  const {
    data: salaries,
    loading: salLoading,
    error: salError,
    refresh: refreshSalaries,
  } = useApi(salariesFetch, [id])

  function handleRaiseSuccess() {
    setShowRaiseForm(false)
    refreshSalaries()
  }

  if (empLoading) return <LoadingSpinner />
  if (empError) return <ErrorMessage message={empError} />
  if (!employee) return null

  return (
    <div>
      <div className="mb-4 text-sm text-slate-500">
        <Link to="/employees" className="text-indigo-600 hover:underline">
          Employees
        </Link>
        {' / '}
        {employee.first_name} {employee.last_name}
      </div>

      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-semibold text-slate-900">
          {employee.first_name} {employee.last_name}
        </h2>
        {isAdmin && (
          <button
            className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 transition-colors"
            onClick={() => setShowRaiseForm(true)}
          >
            Record salary change
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="rounded-lg border border-slate-200 bg-white shadow-sm">
          <div className="px-6 py-4 border-b border-slate-200">
            <h3 className="text-sm font-semibold text-slate-900 uppercase tracking-wide">
              Details
            </h3>
          </div>
          <dl className="divide-y divide-slate-100 text-sm">
            {[
              ['Employee #', employee.employee_number],
              ['Email', employee.email],
              ['Department', employee.department?.name],
              ['Title', employee.job_title],
              ['Level', employee.job_level],
              ['Country', employee.country_code],
              ['Hire date', employee.hire_date],
            ].map(([label, value]) => (
              <div key={label} className="flex items-center px-6 py-3 gap-4">
                <dt className="w-24 shrink-0 text-slate-500">{label}</dt>
                <dd className="text-slate-900 font-medium">{value}</dd>
              </div>
            ))}
            <div className="flex items-center px-6 py-3 gap-4">
              <dt className="w-24 shrink-0 text-slate-500">Status</dt>
              <dd>
                <span className={`status-badge status-${employee.status}`}>{employee.status}</span>
              </dd>
            </div>
          </dl>
        </div>

        <div className="rounded-lg border border-slate-200 bg-white shadow-sm">
          <div className="px-6 py-4 border-b border-slate-200">
            <h3 className="text-sm font-semibold text-slate-900 uppercase tracking-wide">
              Salary timeline
            </h3>
          </div>
          {salLoading ? (
            <div className="p-6">
              <LoadingSpinner />
            </div>
          ) : salError ? (
            <div className="p-6">
              <ErrorMessage message={salError} />
            </div>
          ) : !salaries || salaries.length === 0 ? (
            <div className="p-6">
              <EmptyState message="No salary records." />
            </div>
          ) : (
            <table className="min-w-full divide-y divide-slate-100 text-sm">
              <thead className="bg-slate-50">
                <tr>
                  <th className={thCls}>Effective date</th>
                  <th className={thCls}>Amount</th>
                  <th className={thCls}>Reason</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {salaries.map((s, i) => (
                  <tr key={s.id} className={i === 0 ? 'bg-indigo-50' : 'hover:bg-slate-50'}>
                    <td className={tdCls}>{s.effective_date}</td>
                    <td className={`${tdCls} font-medium tabular-nums`}>
                      {formatMoney(s.amount_minor_units, s.currency)}
                    </td>
                    <td className={tdCls}>{s.reason}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {showRaiseForm && (
        <RaiseForm
          employeeId={id}
          onSuccess={handleRaiseSuccess}
          onCancel={() => setShowRaiseForm(false)}
        />
      )}
    </div>
  )
}
