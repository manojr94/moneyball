import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { vi, describe, it, expect, beforeEach } from 'vitest'
import { AnalyticsDashboard } from '../pages/AnalyticsDashboard'
import { AuthContext } from '../contexts/AuthContext'
import * as analyticsApi from '../api/analytics'

vi.mock('../api/analytics')

const adminUser = { id: 1, name: 'Admin', role: 'hr_admin' }

function renderPage(user = adminUser) {
  return render(
    <AuthContext.Provider value={{ user, loading: false, login: vi.fn(), logout: vi.fn() }}>
      <MemoryRouter>
        <AnalyticsDashboard />
      </MemoryRouter>
    </AuthContext.Provider>,
  )
}

const sampleGroups = [
  {
    key: 'na',
    label: 'NA',
    headcount: 10,
    total_spend: 1000000,
    min: 50000,
    median: 100000,
    avg: 100000,
    max: 150000,
  },
]

describe('AnalyticsDashboard', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    analyticsApi.bandCoverage.mockResolvedValue({ uncovered: [] })
  })

  it('shows loading spinner initially', () => {
    analyticsApi.payAnalytics.mockReturnValue(new Promise(() => {}))
    analyticsApi.compaRatioAnalytics.mockReturnValue(new Promise(() => {}))
    renderPage()
    expect(screen.getAllByRole('status').length).toBeGreaterThan(0)
  })

  it('renders pay groups in a table', async () => {
    analyticsApi.payAnalytics.mockResolvedValue({ groups: sampleGroups, meta: {} })
    analyticsApi.compaRatioAnalytics.mockResolvedValue({ groups: [] })
    renderPage()
    expect(await screen.findByText('NA')).toBeInTheDocument()
    expect(screen.getByText('10')).toBeInTheDocument()
  })

  it('shows empty state when no groups', async () => {
    analyticsApi.payAnalytics.mockResolvedValue({ groups: [], meta: {} })
    analyticsApi.compaRatioAnalytics.mockResolvedValue({ groups: [] })
    renderPage()
    expect(await screen.findByText(/no data for current filters/i)).toBeInTheDocument()
  })

  it('shows error when pay API fails', async () => {
    analyticsApi.payAnalytics.mockRejectedValue(new Error('API failure'))
    analyticsApi.compaRatioAnalytics.mockResolvedValue({ groups: [] })
    renderPage()
    expect(await screen.findByRole('alert')).toHaveTextContent('API failure')
  })

  it('switches to compa-ratio tab', async () => {
    analyticsApi.payAnalytics.mockResolvedValue({ groups: [], meta: {} })
    analyticsApi.compaRatioAnalytics.mockResolvedValue({
      groups: [{ key: 'na', label: 'NA', headcount: 5, median_compa_ratio: '0.95' }],
    })
    renderPage()
    await userEvent.click(screen.getByRole('button', { name: /compa-ratio/i }))
    expect(await screen.findByText('0.95')).toBeInTheDocument()
  })

  it('switches to band coverage tab', async () => {
    analyticsApi.payAnalytics.mockResolvedValue({ groups: [], meta: {} })
    analyticsApi.compaRatioAnalytics.mockResolvedValue({ groups: [] })
    analyticsApi.bandCoverage.mockResolvedValue({
      uncovered: [{ job_title: 'Designer', job_level: 'L4', pay_zone_name: 'NA' }],
    })
    renderPage()
    await userEvent.click(screen.getByRole('button', { name: /band coverage/i }))
    expect(await screen.findByText('Designer')).toBeInTheDocument()
    expect(screen.getByText('L4')).toBeInTheDocument()
  })

  it('shows all-covered message when band_coverage is empty', async () => {
    analyticsApi.payAnalytics.mockResolvedValue({ groups: [], meta: {} })
    analyticsApi.compaRatioAnalytics.mockResolvedValue({ groups: [] })
    analyticsApi.bandCoverage.mockResolvedValue({ uncovered: [] })
    renderPage()
    await userEvent.click(screen.getByRole('button', { name: /band coverage/i }))
    expect(await screen.findByText(/all title\/level\/zone combinations are covered/i)).toBeInTheDocument()
  })
})
