import { useState, useCallback } from 'react'
import { listBands } from '../api/bands'
import { useApi } from '../hooks/useApi'
import { LoadingSpinner } from '../components/LoadingSpinner'
import { ErrorMessage } from '../components/ErrorMessage'
import { EmptyState } from '../components/EmptyState'
import { formatMoney } from '../utils/money'

function today() {
  return new Date().toISOString().slice(0, 10)
}

const thCls = 'px-4 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wide'
const tdCls = 'px-4 py-3 text-sm text-slate-700'

export function BandView() {
  const [effectiveOn, setEffectiveOn] = useState(today)

  const fetch = useCallback(() => listBands({ effective_on: effectiveOn }), [effectiveOn])
  const { data: bands, loading, error } = useApi(fetch, [effectiveOn])

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-semibold text-slate-900">Salary bands</h2>
      </div>

      <div className="flex flex-wrap gap-4 mb-6">
        <div className="flex items-center gap-2">
          <label
            htmlFor="bands-effective-on"
            className="text-sm font-medium text-slate-700"
          >
            Effective on
          </label>
          <input
            id="bands-effective-on"
            type="date"
            value={effectiveOn}
            onChange={(e) => setEffectiveOn(e.target.value)}
            className="rounded-md border border-slate-300 px-3 py-1.5 text-sm text-slate-900 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 bg-white"
          />
        </div>
      </div>

      {error && <ErrorMessage message={error} />}

      {loading ? (
        <LoadingSpinner />
      ) : !bands || bands.length === 0 ? (
        <EmptyState message="No salary bands found for this date." />
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
