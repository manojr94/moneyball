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
    <div className="page">
      <div className="breadcrumb">
        <Link to="/employees">Employees</Link> / {employee.first_name} {employee.last_name}
      </div>

      <div className="page-header">
        <h2>
          {employee.first_name} {employee.last_name}
        </h2>
        {isAdmin && (
          <button className="btn btn-primary" onClick={() => setShowRaiseForm(true)}>
            Record salary change
          </button>
        )}
      </div>

      <div className="detail-grid">
        <div className="detail-card">
          <h3>Details</h3>
          <dl className="detail-list">
            <dt>Employee #</dt>
            <dd>{employee.employee_number}</dd>
            <dt>Email</dt>
            <dd>{employee.email}</dd>
            <dt>Department</dt>
            <dd>{employee.department?.name}</dd>
            <dt>Title</dt>
            <dd>{employee.job_title}</dd>
            <dt>Level</dt>
            <dd>{employee.job_level}</dd>
            <dt>Country</dt>
            <dd>{employee.country_code}</dd>
            <dt>Hire date</dt>
            <dd>{employee.hire_date}</dd>
            <dt>Status</dt>
            <dd>
              <span className={`status-badge status-${employee.status}`}>{employee.status}</span>
            </dd>
          </dl>
        </div>

        <div className="detail-card">
          <h3>Salary timeline</h3>
          {salLoading ? (
            <LoadingSpinner />
          ) : salError ? (
            <ErrorMessage message={salError} />
          ) : !salaries || salaries.length === 0 ? (
            <EmptyState message="No salary records." />
          ) : (
            <table className="table salary-table">
              <thead>
                <tr>
                  <th>Effective date</th>
                  <th>Amount</th>
                  <th>Reason</th>
                </tr>
              </thead>
              <tbody>
                {salaries.map((s, i) => (
                  <tr key={s.id} className={i === 0 ? 'current-salary' : ''}>
                    <td>{s.effective_date}</td>
                    <td>{formatMoney(s.amount_minor_units, s.currency)}</td>
                    <td>{s.reason}</td>
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
