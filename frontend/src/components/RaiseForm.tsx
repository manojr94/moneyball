import { useState, useCallback, type FormEvent } from 'react'
import { createSalary } from '../api/employees'
import { listCurrencies } from '../api/currencies'
import { majorToMinor } from '../utils/money'
import { useAuth } from '../contexts/AuthContext'
import { useApi } from '../hooks/useApi'

const REASONS = ['merit', 'promotion', 'correction', 'role_change'] as const

const inputCls =
  'w-full rounded-md border border-slate-300 px-3 py-2 text-sm text-slate-900 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 bg-white'

interface RaiseFormProps {
  employeeId: string | number
  onSuccess: () => void
  onCancel: () => void
}

export function RaiseForm({ employeeId, onSuccess, onCancel }: RaiseFormProps) {
  const { user } = useAuth()
  const isAdmin = user?.role === 'hr_admin'

  const [amount, setAmount] = useState('')
  const [currency, setCurrency] = useState('USD')
  const [effectiveDate, setEffectiveDate] = useState(() => new Date().toISOString().slice(0, 10))
  const [reason, setReason] = useState<typeof REASONS[number]>('merit')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchCurrencies = useCallback(() => listCurrencies(), [])
  const { data: currencies } = useApi(fetchCurrencies, [])

  if (!isAdmin) return null

  async function handleSubmit(e: FormEvent) {
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
      setError(err instanceof Error ? err.message : 'Unknown error')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      role="dialog"
      aria-modal="true"
      aria-label="Record salary change"
    >
      <div className="w-full max-w-md rounded-xl bg-white shadow-xl border border-slate-200 p-6">
        <h3 className="text-base font-semibold text-slate-900 mb-4">Record salary change</h3>
        {error && (
          <div className="mb-4 rounded-md bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-800" role="alert">
            {error}
          </div>
        )}
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label htmlFor="raise-amount" className="block text-sm font-medium text-slate-700 mb-1">
                Amount (major units)
              </label>
              <input
                id="raise-amount"
                type="number"
                min="0"
                step="any"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                required
                placeholder="e.g. 80000"
                className={inputCls}
              />
            </div>
            <div>
              <label htmlFor="raise-currency" className="block text-sm font-medium text-slate-700 mb-1">
                Currency
              </label>
              <select
                id="raise-currency"
                value={currency}
                onChange={(e) => setCurrency(e.target.value)}
                required
                className={inputCls}
              >
                {(currencies ?? ['USD']).map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </div>
          </div>
          <div>
            <label htmlFor="raise-effective-date" className="block text-sm font-medium text-slate-700 mb-1">
              Effective date
            </label>
            <input
              id="raise-effective-date"
              type="date"
              value={effectiveDate}
              onChange={(e) => setEffectiveDate(e.target.value)}
              required
              className={inputCls}
            />
          </div>
          <div>
            <label htmlFor="raise-reason" className="block text-sm font-medium text-slate-700 mb-1">
              Reason
            </label>
            <select
              id="raise-reason"
              value={reason}
              onChange={(e) => setReason(e.target.value as typeof REASONS[number])}
              className={inputCls}
            >
              {REASONS.map((r) => (
                <option key={r} value={r}>
                  {r.charAt(0).toUpperCase() + r.slice(1).replace('_', ' ')}
                </option>
              ))}
            </select>
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={onCancel}
              className="rounded-md border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 shadow-sm hover:bg-slate-50 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={submitting}
              className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {submitting ? 'Saving…' : 'Save'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
