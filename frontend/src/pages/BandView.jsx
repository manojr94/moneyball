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

export function BandView() {
  const [effectiveOn, setEffectiveOn] = useState(today)

  const fetch = useCallback(() => listBands({ effective_on: effectiveOn }), [effectiveOn])
  const { data: bands, loading, error } = useApi(fetch, [effectiveOn])

  return (
    <div className="page">
      <div className="page-header">
        <h2>Salary bands</h2>
      </div>

      <div className="filters">
        <div className="field-inline">
          <label htmlFor="bands-effective-on">Effective on</label>
          <input
            id="bands-effective-on"
            type="date"
            value={effectiveOn}
            onChange={(e) => setEffectiveOn(e.target.value)}
          />
        </div>
      </div>

      {error && <ErrorMessage message={error} />}

      {loading ? (
        <LoadingSpinner />
      ) : !bands || bands.length === 0 ? (
        <EmptyState message="No salary bands found for this date." />
      ) : (
        <table className="table">
          <thead>
            <tr>
              <th>Pay zone</th>
              <th>Title</th>
              <th>Level</th>
              <th>Currency</th>
              <th>Min</th>
              <th>Mid</th>
              <th>Max</th>
              <th>From</th>
              <th>To</th>
            </tr>
          </thead>
          <tbody>
            {bands.map((b) => (
              <tr key={b.id}>
                <td>{b.pay_zone_name ?? b.pay_zone_id}</td>
                <td>{b.job_title}</td>
                <td>{b.job_level}</td>
                <td>{b.currency}</td>
                <td>{formatMoney(b.min_minor_units, b.currency)}</td>
                <td>{formatMoney(b.mid_minor_units, b.currency)}</td>
                <td>{formatMoney(b.max_minor_units, b.currency)}</td>
                <td>{b.effective_from}</td>
                <td>{b.effective_to ?? 'open'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}
