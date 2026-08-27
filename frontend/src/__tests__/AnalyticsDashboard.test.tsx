import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { vi, describe, it, expect, beforeEach } from 'vitest'
import { AnalyticsDashboard } from '../pages/AnalyticsDashboard'
import { AuthContext } from '../contexts/AuthContext'
import type { AuthContextValue } from '../contexts/AuthContext'
import type { User } from '../types'
import { TooltipProvider } from '../components/Tooltip'
import * as analyticsApi from '../api/analytics'

vi.mock('../api/analytics')

const adminUser: User = { id: 1, name: 'Admin', role: 'hr_admin', email: 'admin@example.com' }

function makeCtx(user: User): AuthContextValue {
  return { user, loading: false, login: vi.fn(), loginWithToken: vi.fn(), logout: vi.fn() }
}

function renderPage(user = adminUser) {
  return render(
    <AuthContext.Provider value={makeCtx(user)}>
      <MemoryRouter>
        <TooltipProvider>
          <AnalyticsDashboard />
        </TooltipProvider>
      </MemoryRouter>
    </AuthContext.Provider>,
  )
}

const sampleGroups = [
  {
    key: 'na',
    label: 'NA',
    headcount: 10,
    total_spend_usd_minor_units: 1000000,
    min_usd_minor_units: 50000,
    median_usd_minor_units: 100000,
    avg_usd_minor_units: 100000,
    max_usd_minor_units: 150000,
  },
]

describe('AnalyticsDashboard', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    vi.mocked(analyticsApi.bandCoverage).mockResolvedValue({ uncovered: [] })
  })

  it('shows loading spinner initially', () => {
    vi.mocked(analyticsApi.payAnalytics).mockReturnValue(new Promise<never>(() => {}))
    vi.mocked(analyticsApi.compaRatioAnalytics).mockReturnValue(new Promise<never>(() => {}))
    renderPage()
    expect(screen.getAllByRole('status').length).toBeGreaterThan(0)
  })

  it('renders pay groups in a table', async () => {
    vi.mocked(analyticsApi.payAnalytics).mockResolvedValue({
      groups: sampleGroups,
      meta: { as_of: '2024-01-01', rate_date: '2024-01-01', group_by: 'region', unconvertible_currencies: [] },
    })
    vi.mocked(analyticsApi.compaRatioAnalytics).mockResolvedValue({ groups: [], meta: { as_of: '2024-01-01', rate_date: '2024-01-01', group_by: 'region', unconvertible_currencies: [] } })
    renderPage()
    expect(await screen.findByText('NA')).toBeInTheDocument()
    expect(screen.getByText('10')).toBeInTheDocument()
  })

  it('shows empty state when no groups', async () => {
    vi.mocked(analyticsApi.payAnalytics).mockResolvedValue({
      groups: [],
      meta: { as_of: '2024-01-01', rate_date: '2024-01-01', group_by: 'region', unconvertible_currencies: [] },
    })
    vi.mocked(analyticsApi.compaRatioAnalytics).mockResolvedValue({ groups: [], meta: { as_of: '2024-01-01', rate_date: '2024-01-01', group_by: 'region', unconvertible_currencies: [] } })
    renderPage()
    expect(await screen.findByText(/no data for current filters/i)).toBeInTheDocument()
  })

  it('shows error when pay API fails', async () => {
    vi.mocked(analyticsApi.payAnalytics).mockRejectedValue(new Error('API failure'))
    vi.mocked(analyticsApi.compaRatioAnalytics).mockResolvedValue({ groups: [], meta: { as_of: '2024-01-01', rate_date: '2024-01-01', group_by: 'region', unconvertible_currencies: [] } })
    renderPage()
    expect(await screen.findByRole('alert')).toHaveTextContent('API failure')
  })

  it('switches to compa-ratio tab', async () => {
    vi.mocked(analyticsApi.payAnalytics).mockResolvedValue({ groups: [], meta: { as_of: '2024-01-01', rate_date: '2024-01-01', group_by: 'region', unconvertible_currencies: [] } })
    vi.mocked(analyticsApi.compaRatioAnalytics).mockResolvedValue({
      groups: [{ key: 'na', label: 'NA', headcount: 5, avg_compa_ratio: '0.95', below: 0, within: 4, above: 1, unresolved: 0 }],
      meta: { as_of: '2024-01-01', rate_date: '2024-01-01', group_by: 'region', unconvertible_currencies: [] },
    })
    renderPage()
    await userEvent.click(screen.getByRole('button', { name: /compa-ratio/i }))
    expect(await screen.findByText('0.95')).toBeInTheDocument()
  })

  it('switches to band coverage tab', async () => {
    vi.mocked(analyticsApi.payAnalytics).mockResolvedValue({ groups: [], meta: { as_of: '2024-01-01', rate_date: '2024-01-01', group_by: 'region', unconvertible_currencies: [] } })
    vi.mocked(analyticsApi.compaRatioAnalytics).mockResolvedValue({ groups: [], meta: { as_of: '2024-01-01', rate_date: '2024-01-01', group_by: 'region', unconvertible_currencies: [] } })
    vi.mocked(analyticsApi.bandCoverage).mockResolvedValue({
      uncovered: [{ job_title: 'Designer', job_level: 'L4', pay_zone_id: 1, pay_zone_name: 'NA' }],
    })
    renderPage()
    await userEvent.click(screen.getByRole('button', { name: /band coverage/i }))
    expect(await screen.findByText('Designer')).toBeInTheDocument()
    expect(screen.getByText('L4')).toBeInTheDocument()
  })

  it('shows all-covered message when band_coverage is empty', async () => {
    vi.mocked(analyticsApi.payAnalytics).mockResolvedValue({ groups: [], meta: { as_of: '2024-01-01', rate_date: '2024-01-01', group_by: 'region', unconvertible_currencies: [] } })
    vi.mocked(analyticsApi.compaRatioAnalytics).mockResolvedValue({ groups: [], meta: { as_of: '2024-01-01', rate_date: '2024-01-01', group_by: 'region', unconvertible_currencies: [] } })
    vi.mocked(analyticsApi.bandCoverage).mockResolvedValue({ uncovered: [] })
    renderPage()
    await userEvent.click(screen.getByRole('button', { name: /band coverage/i }))
    expect(await screen.findByText(/all title\/level\/zone combinations are covered/i)).toBeInTheDocument()
  })
})
