import { useState, useCallback } from 'react'
import PropTypes from 'prop-types'
import { Info } from 'lucide-react'
import { payAnalytics, compaRatioAnalytics, bandCoverage } from '../api/analytics'
import { useApi } from '../hooks/useApi'
import { LoadingSpinner } from '../components/LoadingSpinner'
import { ErrorMessage } from '../components/ErrorMessage'
import { EmptyState } from '../components/EmptyState'
import { Tooltip } from '../components/Tooltip'
import { formatMoney } from '../utils/money'
import { thCls, tdCls, inputCls } from '../styles/shared'

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

function TableWrapper({ children }) {
  return (
    <div className="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm">
      <table className="min-w-full divide-y divide-slate-200">{children}</table>
    </div>
  )
}

TableWrapper.propTypes = { children: PropTypes.node.isRequired }

function PayTable({ groups = [] }) {
  if (!groups || groups.length === 0) return <EmptyState message="No data for current filters." />
  return (
    <TableWrapper>
      <thead className="bg-slate-50">
        <tr>
          <th className={thCls}>Group</th>
          <th className={thCls}>Headcount</th>
          <th className={thCls}>Min ({REPORTING_CURRENCY})</th>
          <th className={thCls}>Median ({REPORTING_CURRENCY})</th>
          <th className={thCls}>Avg ({REPORTING_CURRENCY})</th>
          <th className={thCls}>Max ({REPORTING_CURRENCY})</th>
          <th className={thCls}>Total spend ({REPORTING_CURRENCY})</th>
        </tr>
      </thead>
      <tbody className="divide-y divide-slate-100">
        {groups.map((g) => (
          <tr key={g.key} className="hover:bg-slate-50">
            <td className={`${tdCls} font-medium text-slate-900`}>{g.label ?? g.key}</td>
            <td className={`${tdCls} tabular-nums`}>{g.headcount}</td>
            <td className={`${tdCls} tabular-nums`}>{formatMoney(g.min_usd_minor_units, REPORTING_CURRENCY)}</td>
            <td className={`${tdCls} tabular-nums`}>{formatMoney(g.median_usd_minor_units, REPORTING_CURRENCY)}</td>
            <td className={`${tdCls} tabular-nums`}>{formatMoney(g.avg_usd_minor_units, REPORTING_CURRENCY)}</td>
            <td className={`${tdCls} tabular-nums`}>{formatMoney(g.max_usd_minor_units, REPORTING_CURRENCY)}</td>
            <td className={`${tdCls} tabular-nums`}>{formatMoney(g.total_spend_usd_minor_units, REPORTING_CURRENCY)}</td>
          </tr>
        ))}
      </tbody>
    </TableWrapper>
  )
}

PayTable.propTypes = { groups: PropTypes.array }

function CompaTable({ groups = [] }) {
  if (!groups || groups.length === 0) return <EmptyState message="No compa-ratio data." />
  return (
    <TableWrapper>
      <thead className="bg-slate-50">
        <tr>
          <th className={thCls}>Group</th>
          <th className={thCls}>Headcount</th>
          <th className={thCls}>Avg compa-ratio</th>
          <th className={thCls}>Below band</th>
          <th className={thCls}>Within band</th>
          <th className={thCls}>Above band</th>
          <th className={thCls}>No band</th>
        </tr>
      </thead>
      <tbody className="divide-y divide-slate-100">
        {groups.map((g) => (
          <tr key={g.key ?? g.label} className="hover:bg-slate-50">
            <td className={`${tdCls} font-medium text-slate-900`}>{g.label ?? g.key}</td>
            <td className={`${tdCls} tabular-nums`}>{g.headcount}</td>
            <td className={`${tdCls} tabular-nums`}>{g.avg_compa_ratio != null ? Number(g.avg_compa_ratio).toFixed(2) : '—'}</td>
            <td className={`${tdCls} tabular-nums`}>{g.below ?? '—'}</td>
            <td className={`${tdCls} tabular-nums`}>{g.within ?? '—'}</td>
            <td className={`${tdCls} tabular-nums`}>{g.above ?? '—'}</td>
            <td className={`${tdCls} tabular-nums`}>{g.unresolved ?? '—'}</td>
          </tr>
        ))}
      </tbody>
    </TableWrapper>
  )
}

CompaTable.propTypes = { groups: PropTypes.array }

function BandCoverageTable({ data = null }) {
  const uncovered = data?.uncovered ?? data
  if (!Array.isArray(uncovered) || uncovered.length === 0)
    return <EmptyState message="All title/level/zone combinations are covered." />
  return (
    <TableWrapper>
      <thead className="bg-slate-50">
        <tr>
          <th className={thCls}>Title</th>
          <th className={thCls}>Level</th>
          <th className={thCls}>Pay zone</th>
        </tr>
      </thead>
      <tbody className="divide-y divide-slate-100">
        {uncovered.map((row, i) => (
          <tr key={i} className="hover:bg-slate-50">
            <td className={`${tdCls} font-medium text-slate-900`}>{row.job_title}</td>
            <td className={tdCls}>{row.job_level}</td>
            <td className={tdCls}>{row.pay_zone_name ?? row.pay_zone_id}</td>
          </tr>
        ))}
      </tbody>
    </TableWrapper>
  )
}

BandCoverageTable.propTypes = { data: PropTypes.oneOfType([PropTypes.object, PropTypes.array]) }

function LabelWithTooltip({ htmlFor, label, tooltip }) {
  return (
    <div className="flex items-center gap-1">
      <label htmlFor={htmlFor} className="text-sm font-medium text-slate-700">
        {label}
      </label>
      <Tooltip content={tooltip}>
        <button
          type="button"
          aria-label={`Help: ${label}`}
          className="text-slate-400 hover:text-slate-600 focus:outline-none"
        >
          <Info className="w-3.5 h-3.5" />
        </button>
      </Tooltip>
    </div>
  )
}

LabelWithTooltip.propTypes = {
  htmlFor: PropTypes.string,
  label: PropTypes.string.isRequired,
  tooltip: PropTypes.string.isRequired,
}

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

  const tabLabel = (t) => {
    if (t === 'pay') return 'Pay'
    if (t === 'compa_ratio') return 'Compa-ratio'
    return 'Band coverage'
  }

  const unconvertible = payData?.meta?.unconvertible_currencies ?? []

  return (
    <div>
      <div className="mb-6">
        <h2 className="text-xl font-semibold text-slate-900">Analytics</h2>
      </div>

      <div className="flex gap-1 border-b border-slate-200 mb-6">
        {TAB_OPTIONS.map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`px-4 py-2.5 text-sm font-medium rounded-t-md transition-colors focus:outline-none ${
              tab === t
                ? 'bg-white border border-b-white border-slate-200 text-indigo-600 -mb-px'
                : 'text-slate-500 hover:text-slate-700 hover:bg-slate-50'
            }`}
          >
            {tabLabel(t)}
          </button>
        ))}
      </div>

      {tab !== 'band_coverage' && (
        <div className="flex flex-wrap gap-4 mb-6">
          <div className="flex items-center gap-2">
            <label className="text-sm font-medium text-slate-700">Group by</label>
            <select
              aria-label="Group by"
              value={groupBy}
              onChange={(e) => setGroupBy(e.target.value)}
              className={inputCls}
            >
              {GROUP_BY_OPTIONS.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
          </div>
          <div className="flex items-center gap-2">
            <LabelWithTooltip
              htmlFor="as-of-date"
              label="As of"
              tooltip="Show the salary each employee held on this date. Use a past date to see historical headcount and pay."
            />
            <input
              id="as-of-date"
              type="date"
              aria-label="As of date"
              max={today()}
              value={asOf}
              onChange={(e) => setAsOf(e.target.value)}
              className={inputCls}
            />
          </div>
          <div className="flex items-center gap-2">
            <LabelWithTooltip
              htmlFor="rate-date"
              label="Rate date"
              tooltip="Convert local salaries to USD using the exchange rate that was in effect on this date. Change this to model what the payroll would be worth at a different point in time."
            />
            <input
              id="rate-date"
              type="date"
              aria-label="Rate date"
              max={today()}
              value={rateDate}
              onChange={(e) => setRateDate(e.target.value)}
              className={inputCls}
            />
          </div>
        </div>
      )}

      <div>
        {tab === 'pay' && (
          <>
            {payLoading && <LoadingSpinner />}
            {payError && <ErrorMessage message={payError} />}
            {!payLoading && !payError && <PayTable groups={payData?.groups} />}
            {unconvertible.length > 0 && (
              <div className="mt-3 flex items-start gap-2 rounded-md bg-amber-50 border border-amber-200 px-4 py-3 text-sm text-amber-800">
                <Info className="w-4 h-4 mt-0.5 shrink-0 text-amber-600" />
                <span>
                  <strong>{unconvertible.length} {unconvertible.length === 1 ? 'currency' : 'currencies'} excluded</strong>
                  {' '}— no exchange rate on file for {rateDate}: {unconvertible.join(', ')}.
                  Employees paid in {unconvertible.length === 1 ? 'this currency are' : 'these currencies are'} omitted from all totals.
                  Add a rate for {rateDate} to include them.
                </span>
              </div>
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
            <div className="mb-4 rounded-md bg-slate-50 border border-slate-200 px-4 py-3 text-sm text-slate-700">
              <p className="font-medium mb-1">About band coverage</p>
              <p>
                A title/level/zone combination is <strong>uncovered</strong> when at least one
                active employee holds that role but no salary band exists for it in the current pay
                zone. Without a band, compa-ratio cannot be calculated and the employee appears as
                &ldquo;no band&rdquo; in the compa-ratio view. To resolve, add a salary band for
                each row listed below.
              </p>
            </div>
            {coverageLoading && <LoadingSpinner />}
            {coverageError && <ErrorMessage message={coverageError} />}
            {!coverageLoading && !coverageError && <BandCoverageTable data={coverageData} />}
          </>
        )}
      </div>
    </div>
  )
}
