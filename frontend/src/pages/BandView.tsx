import { useState, useCallback } from 'react'
import { listBands, createBand } from '../api/bands'
import { listPayZones } from '../api/pay_zones'
import { useApi } from '../hooks/useApi'
import { useAuth } from '../contexts/AuthContext'
import { LoadingSpinner } from '../components/LoadingSpinner'
import { ErrorMessage } from '../components/ErrorMessage'
import { formatMoney } from '../utils/money'
import { thCls, tdCls, inputCls } from '../styles/shared'
import type { SalaryBand } from '../types'

function today(): string {
  return new Date().toISOString().slice(0, 10)
}

interface BandForm {
  job_title: string
  job_level: string
  pay_zone_id: string
  currency: string
  min_minor_units: string
  mid_minor_units: string
  max_minor_units: string
  effective_from: string
}

const EMPTY_FORM: BandForm = {
  job_title: '',
  job_level: '',
  pay_zone_id: '',
  currency: '',
  min_minor_units: '',
  mid_minor_units: '',
  max_minor_units: '',
  effective_from: today(),
}

export function BandView() {
  const { user } = useAuth()
  const isAdmin = user?.role === 'hr_admin'

  const [effectiveOn, setEffectiveOn] = useState(today)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState<BandForm>({ ...EMPTY_FORM })
  const [formError, setFormError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  const fetchBands = useCallback(() => listBands({ effective_on: effectiveOn }), [effectiveOn])
  const { data: bands, loading, error, refresh } = useApi<SalaryBand[]>(fetchBands, [effectiveOn])

  const { data: payZones } = useApi(listPayZones, [])

  function handleFormChange(key: keyof BandForm, value: string) {
    setForm((f) => ({ ...f, [key]: value }))
  }

  async function handleCreateBand(e: React.FormEvent) {
    e.preventDefault()
    setFormError(null)
    setSubmitting(true)
    try {
      const payload = {
        ...form,
        pay_zone_id: Number(form.pay_zone_id),
        min_minor_units: Number(form.min_minor_units),
        mid_minor_units: Number(form.mid_minor_units),
        max_minor_units: Number(form.max_minor_units),
      }
      await createBand(payload)
      setForm({ ...EMPTY_FORM })
      setShowForm(false)
      refresh()
    } catch (err) {
      const apiErr = err as { body?: { errors?: string[] }; message?: string }
      setFormError(apiErr.body?.errors?.join(', ') ?? apiErr.message ?? 'Unknown error')
    } finally {
      setSubmitting(false)
    }
  }

  const fieldCls = `${inputCls} w-full`

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h2 className="text-xl font-semibold text-slate-900">Salary bands</h2>
          <p className="text-sm text-slate-500 mt-0.5">
            Min / midpoint / max pay ranges per role and pay zone. Compa-ratio = salary ÷ midpoint — 1.0 means paid at midpoint.
          </p>
        </div>
        {isAdmin && (
          <button
            onClick={() => setShowForm((s) => !s)}
            className="rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-medium text-white shadow-sm hover:bg-indigo-700 transition-colors"
          >
            {showForm ? 'Cancel' : 'New band'}
          </button>
        )}
      </div>

      {isAdmin && showForm && (
        <form
          onSubmit={handleCreateBand}
          className="mb-6 rounded-lg border border-slate-200 bg-slate-50 p-4"
          aria-label="New salary band"
        >
          <h3 className="text-sm font-semibold text-slate-800 mb-3">New salary band</h3>
          {formError && (
            <div className="mb-3 rounded-md bg-red-50 border border-red-200 px-4 py-2 text-sm text-red-800" role="alert">
              {formError}
            </div>
          )}
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div className="flex flex-col gap-1">
              <label className="text-xs font-medium text-slate-600">Job title</label>
              <input type="text" required value={form.job_title}
                onChange={(e) => handleFormChange('job_title', e.target.value)}
                className={fieldCls} placeholder="e.g. Engineer" />
            </div>
            <div className="flex flex-col gap-1">
              <label className="text-xs font-medium text-slate-600">Level</label>
              <input type="text" required value={form.job_level}
                onChange={(e) => handleFormChange('job_level', e.target.value)}
                className={fieldCls} placeholder="e.g. L4" />
            </div>
            <div className="flex flex-col gap-1">
              <label className="text-xs font-medium text-slate-600">Pay zone</label>
              <select required value={form.pay_zone_id}
                onChange={(e) => handleFormChange('pay_zone_id', e.target.value)}
                className={fieldCls}>
                <option value="">Select…</option>
                {(payZones ?? []).map((z) => (
                  <option key={z.id} value={z.id}>{z.name}</option>
                ))}
              </select>
            </div>
            <div className="flex flex-col gap-1">
              <label className="text-xs font-medium text-slate-600">Currency</label>
              <input type="text" required value={form.currency} maxLength={3}
                onChange={(e) => handleFormChange('currency', e.target.value.toUpperCase())}
                className={fieldCls} placeholder="USD" />
            </div>
            <div className="flex flex-col gap-1">
              <label className="text-xs font-medium text-slate-600">Min (minor units)</label>
              <input type="number" required value={form.min_minor_units}
                onChange={(e) => handleFormChange('min_minor_units', e.target.value)}
                className={fieldCls} placeholder="8000000" />
            </div>
            <div className="flex flex-col gap-1">
              <label className="text-xs font-medium text-slate-600">Midpoint</label>
              <input type="number" required value={form.mid_minor_units}
                onChange={(e) => handleFormChange('mid_minor_units', e.target.value)}
                className={fieldCls} placeholder="10000000" />
            </div>
            <div className="flex flex-col gap-1">
              <label className="text-xs font-medium text-slate-600">Max</label>
              <input type="number" required value={form.max_minor_units}
                onChange={(e) => handleFormChange('max_minor_units', e.target.value)}
                className={fieldCls} placeholder="13000000" />
            </div>
            <div className="flex flex-col gap-1">
              <label className="text-xs font-medium text-slate-600">Effective from</label>
              <input type="date" required value={form.effective_from}
                onChange={(e) => handleFormChange('effective_from', e.target.value)}
                className={fieldCls} />
            </div>
          </div>
          <div className="mt-3">
            <button type="submit" disabled={submitting}
              className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-indigo-700 disabled:opacity-50 transition-colors">
              {submitting ? 'Saving…' : 'Create band'}
            </button>
          </div>
        </form>
      )}

      <div className="flex flex-wrap gap-4 mb-6">
        <div className="flex items-center gap-2">
          <label htmlFor="bands-effective-on" className="text-sm font-medium text-slate-700">
            Effective on
          </label>
          <input id="bands-effective-on" type="date" value={effectiveOn}
            onChange={(e) => setEffectiveOn(e.target.value)} className={inputCls} />
        </div>
      </div>

      {error && <ErrorMessage message={error} />}

      {loading ? (
        <LoadingSpinner />
      ) : !bands || bands.length === 0 ? (
        <div className="rounded-lg border border-slate-200 bg-slate-50 px-6 py-10 text-center">
          <p className="text-sm font-medium text-slate-700 mb-1">No salary bands for this date</p>
          <p className="text-sm text-slate-500">
            {isAdmin
              ? 'Create a band to define the pay range for a role in a pay zone. Use the "New band" button above to get started.'
              : 'No bands have been configured yet. Contact your HR admin to set up salary bands.'}
          </p>
        </div>
      ) : (
        <div className="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm">
          <table className="min-w-full divide-y divide-slate-200 text-sm">
            <thead className="bg-slate-50">
              <tr>
                <th className={thCls}>Pay zone</th>
                <th className={thCls}>Title</th>
                <th className={thCls}>Level</th>
                <th className={thCls}>Currency</th>
                <th className={thCls}>Min</th>
                <th className={thCls}>Mid</th>
                <th className={thCls}>Max</th>
                <th className={thCls}>From</th>
                <th className={thCls}>To</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {bands.map((b) => (
                <tr key={b.id} className="hover:bg-slate-50">
                  <td className={tdCls}>{b.pay_zone_name ?? b.pay_zone_id}</td>
                  <td className={`${tdCls} font-medium text-slate-900`}>{b.job_title}</td>
                  <td className={tdCls}>{b.job_level}</td>
                  <td className={tdCls}>{b.currency}</td>
                  <td className={`${tdCls} tabular-nums`}>{formatMoney(b.min_minor_units, b.currency)}</td>
                  <td className={`${tdCls} tabular-nums`}>{formatMoney(b.mid_minor_units, b.currency)}</td>
                  <td className={`${tdCls} tabular-nums`}>{formatMoney(b.max_minor_units, b.currency)}</td>
                  <td className={tdCls}>{b.effective_from}</td>
                  <td className={tdCls}>{b.effective_to ?? 'open'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
