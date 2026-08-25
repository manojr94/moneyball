import { useState, useCallback } from 'react'
import PropTypes from 'prop-types'
import { payAnalytics, compaRatioAnalytics, bandCoverage } from '../api/analytics'
import { useApi } from '../hooks/useApi'
import { LoadingSpinner } from '../components/LoadingSpinner'
import { ErrorMessage } from '../components/ErrorMessage'
import { EmptyState } from '../components/EmptyState'
import { formatMoney } from '../utils/money'

const GROUP_BY_OPTIONS = [
  { value: 'region', label: 'Region' },
  { value: 'department', label: 'Department' },
  { value: 'level', label: 'Level' },
  { value: 'country', label: 'Country' },
]

const TAB_OPTIONS = ['pay', 'compa_ratio', 'band_coverage']

function today() {
  return new Date().toISOString().slice(0, 10)
}

// The analytics endpoint converts all amounts to USD using the caller-supplied rate_date.
const REPORTING_CURRENCY = 'USD'

function PayTable({ groups }) {
  if (!groups || groups.length === 0) return <EmptyState message="No data for current filters." />
  return (
    <table className="table">
      <thead>
        <tr>
          <th>Group</th>
          <th>Headcount</th>
          <th>Min ({REPORTING_CURRENCY})</th>
          <th>Median ({REPORTING_CURRENCY})</th>
          <th>Avg ({REPORTING_CURRENCY})</th>
          <th>Max ({REPORTING_CURRENCY})</th>
          <th>Total spend ({REPORTING_CURRENCY})</th>
        </tr>
      </thead>
      <tbody>
        {groups.map((g) => (
          <tr key={g.key}>
            <td>{g.label ?? g.key}</td>
            <td>{g.headcount}</td>
            <td>{formatMoney(g.min_usd_minor_units, REPORTING_CURRENCY)}</td>
            <td>{formatMoney(g.median_usd_minor_units, REPORTING_CURRENCY)}</td>
            <td>{formatMoney(g.avg_usd_minor_units, REPORTING_CURRENCY)}</td>
            <td>{formatMoney(g.max_usd_minor_units, REPORTING_CURRENCY)}</td>
            <td>{formatMoney(g.total_spend_usd_minor_units, REPORTING_CURRENCY)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

PayTable.propTypes = { groups: PropTypes.array }
PayTable.defaultProps = { groups: [] }

function CompaTable({ groups }) {
  if (!groups || groups.length === 0) return <EmptyState message="No compa-ratio data." />
  return (
    <table className="table">
      <thead>
        <tr>
          <th>Group</th>
          <th>Headcount</th>
          <th>Avg compa-ratio</th>
          <th>Below band</th>
          <th>Within band</th>
          <th>Above band</th>
          <th>No band</th>
        </tr>
      </thead>
      <tbody>
        {groups.map((g) => (
          <tr key={g.key ?? g.label}>
            <td>{g.label ?? g.key}</td>
            <td>{g.headcount}</td>
            <td>{g.avg_compa_ratio != null ? Number(g.avg_compa_ratio).toFixed(2) : '—'}</td>
            <td>{g.below ?? '—'}</td>
            <td>{g.within ?? '—'}</td>
            <td>{g.above ?? '—'}</td>
            <td>{g.unresolved ?? '—'}</td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

CompaTable.propTypes = { groups: PropTypes.array }
CompaTable.defaultProps = { groups: [] }

function BandCoverageTable({ data }) {
  const uncovered = data?.uncovered ?? data
  if (!Array.isArray(uncovered) || uncovered.length === 0)
    return <EmptyState message="All title/level/zone combinations are covered." />
  return (
    <table className="table">
      <thead>
        <tr>
          <th>Title</th>
          <th>Level</th>
          <th>Pay zone</th>
        </tr>
      </thead>
      <tbody>
        {uncovered.map((row, i) => (
          <tr key={i}>
            <td>{row.job_title}</td>
            <td>{row.job_level}</td>
            <td>{row.pay_zone_name ?? row.pay_zone_id}</td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

BandCoverageTable.propTypes = { data: PropTypes.oneOfType([PropTypes.object, PropTypes.array]) }
BandCoverageTable.defaultProps = { data: null }

export function AnalyticsDashboard() {
  const [tab, setTab] = useState('pay')
  const [groupBy, setGroupBy] = useState('region')
  const [asOf, setAsOf] = useState(today)
  const [rateDate, setRateDate] = useState(today)

  const payFetch = useCallback(
    () => payAnalytics({ group_by: groupBy, as_of: asOf, rate_date: rateDate }),
    [groupBy, asOf, rateDate],
  )
  const {
    data: payData,
    loading: payLoading,
    error: payError,
  } = useApi(payFetch, [groupBy, asOf, rateDate], { enabled: tab === 'pay' })

  const compaFetch = useCallback(
    () => compaRatioAnalytics({ group_by: groupBy, as_of: asOf, rate_date: rateDate }),
    [groupBy, asOf, rateDate],
  )
  const {
    data: compaData,
    loading: compaLoading,
    error: compaError,
  } = useApi(compaFetch, [groupBy, asOf, rateDate], { enabled: tab === 'compa_ratio' })

  const coverageFetch = useCallback(() => bandCoverage(), [])
  const {
    data: coverageData,
    loading: coverageLoading,
    error: coverageError,
  } = useApi(coverageFetch, [], { enabled: tab === 'band_coverage' })

  return (
    <div className="page">
      <div className="page-header">
        <h2>Analytics</h2>
      </div>

      <div className="tab-bar">
        {TAB_OPTIONS.map((t) => (
          <button
            key={t}
            className={`tab-btn ${tab === t ? 'active' : ''}`}
            onClick={() => setTab(t)}
          >
            {t === 'pay' ? 'Pay' : t === 'compa_ratio' ? 'Compa-ratio' : 'Band coverage'}
          </button>
        ))}
      </div>

      {tab !== 'band_coverage' && (
        <div className="filters">
          <div className="field-inline">
            <label>Group by</label>
            <select
              aria-label="Group by"
              value={groupBy}
              onChange={(e) => setGroupBy(e.target.value)}
            >
              {GROUP_BY_OPTIONS.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
          </div>
          <div className="field-inline">
            <label>As of</label>
            <input
              type="date"
              aria-label="As of date"
              max={today()}
              value={asOf}
              onChange={(e) => setAsOf(e.target.value)}
            />
          </div>
          <div className="field-inline">
            <label>Rate date</label>
            <input
              type="date"
              aria-label="Rate date"
              max={today()}
              value={rateDate}
              onChange={(e) => setRateDate(e.target.value)}
            />
          </div>
        </div>
      )}

      <div className="analytics-content">
        {tab === 'pay' && (
          <>
            {payLoading && <LoadingSpinner />}
            {payError && <ErrorMessage message={payError} />}
            {!payLoading && !payError && <PayTable groups={payData?.groups} />}
            {payData?.meta?.unconvertible_currencies?.length > 0 && (
              <p className="warning">
                Currencies excluded (no rate): {payData.meta.unconvertible_currencies.join(', ')}
              </p>
            )}
          </>
        )}

        {tab === 'compa_ratio' && (
          <>
            {compaLoading && <LoadingSpinner />}
            {compaError && <ErrorMessage message={compaError} />}
            {!compaLoading && !compaError && <CompaTable groups={compaData?.groups} />}
          </>
        )}

        {tab === 'band_coverage' && (
          <>
            {coverageLoading && <LoadingSpinner />}
            {coverageError && <ErrorMessage message={coverageError} />}
            {!coverageLoading && !coverageError && <BandCoverageTable data={coverageData} />}
          </>
        )}
      </div>
    </div>
  )
}
