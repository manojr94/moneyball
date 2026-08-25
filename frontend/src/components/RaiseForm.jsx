import { useState } from 'react'
import PropTypes from 'prop-types'
import { createSalary } from '../api/employees'
import { majorToMinor } from '../utils/money'
import { useAuth } from '../contexts/AuthContext'

const REASONS = ['merit', 'promotion', 'correction', 'role_change']

export function RaiseForm({ employeeId, onSuccess, onCancel }) {
  const { user } = useAuth()
  const isAdmin = user?.role === 'hr_admin'

  const [amount, setAmount] = useState('')
  const [currency, setCurrency] = useState('USD')
  const [effectiveDate, setEffectiveDate] = useState(() => new Date().toISOString().slice(0, 10))
  const [reason, setReason] = useState('merit')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState(null)

  if (!isAdmin) return null

  async function handleSubmit(e) {
    e.preventDefault()
    setError(null)
    setSubmitting(true)
    try {
      const minorUnits = majorToMinor(amount, currency)
      await createSalary(employeeId, {
        amount_minor_units: minorUnits,
        currency,
        effective_date: effectiveDate,
        reason,
      })
      onSuccess()
    } catch (err) {
      setError(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="modal-overlay" role="dialog" aria-modal="true" aria-label="Record salary change">
      <div className="modal">
        <h3>Record salary change</h3>
        {error && (
          <div className="error-message" role="alert">
            {error}
          </div>
        )}
        <form onSubmit={handleSubmit} className="raise-form">
          <div className="field-row">
            <div className="field">
              <label htmlFor="raise-amount">Amount (major units)</label>
              <input
                id="raise-amount"
                type="number"
                min="0"
                step="any"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                required
                placeholder="e.g. 80000"
              />
            </div>
            <div className="field">
              <label htmlFor="raise-currency">Currency</label>
              <input
                id="raise-currency"
                type="text"
                maxLength={3}
                pattern="[A-Z]{3}"
                title="3-letter ISO 4217 currency code (e.g. USD, EUR, JPY)"
                value={currency}
                onChange={(e) => setCurrency(e.target.value.toUpperCase())}
                required
                placeholder="USD"
              />
            </div>
          </div>
          <div className="field">
            <label htmlFor="raise-effective-date">Effective date</label>
            <input
              id="raise-effective-date"
              type="date"
              value={effectiveDate}
              onChange={(e) => setEffectiveDate(e.target.value)}
              required
            />
          </div>
          <div className="field">
            <label htmlFor="raise-reason">Reason</label>
            <select
              id="raise-reason"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            >
              {REASONS.map((r) => (
                <option key={r} value={r}>
                  {r}
                </option>
              ))}
            </select>
          </div>
          <div className="form-actions">
            <button type="button" className="btn" onClick={onCancel}>
              Cancel
            </button>
            <button type="submit" className="btn btn-primary" disabled={submitting}>
              {submitting ? 'Saving…' : 'Save'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

RaiseForm.propTypes = {
  employeeId: PropTypes.oneOfType([PropTypes.string, PropTypes.number]).isRequired,
  onSuccess: PropTypes.func.isRequired,
  onCancel: PropTypes.func.isRequired,
}
