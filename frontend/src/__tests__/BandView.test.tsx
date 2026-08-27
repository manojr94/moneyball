import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { vi, describe, it, expect, beforeEach } from 'vitest'
import { BandView } from '../pages/BandView'
import { AuthContext } from '../contexts/AuthContext'
import type { AuthContextValue } from '../contexts/AuthContext'
import type { User, SalaryBand } from '../types'
import * as bandsApi from '../api/bands'
import * as payZonesApi from '../api/pay_zones'

vi.mock('../api/bands')
vi.mock('../api/pay_zones')

const adminUser: User = { id: 1, name: 'Admin', role: 'hr_admin', email: 'admin@example.com' }
const viewerUser: User = { id: 2, name: 'Viewer', role: 'viewer', email: 'viewer@example.com' }

function makeCtx(user: User): AuthContextValue {
  return { user, loading: false, login: vi.fn(), loginWithToken: vi.fn(), logout: vi.fn() }
}

function renderPage(user = adminUser) {
  return render(
    <AuthContext.Provider value={makeCtx(user)}>
      <MemoryRouter>
        <BandView />
      </MemoryRouter>
    </AuthContext.Provider>,
  )
}

const sampleBand: SalaryBand = {
  id: 1,
  pay_zone_name: 'NA',
  pay_zone_id: 1,
  job_title: 'Engineer',
  job_level: 'L3',
  currency: 'USD',
  min_minor_units: 7000000,
  mid_minor_units: 10000000,
  max_minor_units: 13000000,
  effective_from: '2024-01-01',
  effective_to: null,
}

describe('BandView', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    vi.mocked(payZonesApi.listPayZones).mockResolvedValue([])
  })

  it('shows loading spinner while fetching', () => {
    vi.mocked(bandsApi.listBands).mockReturnValue(new Promise<never>(() => {}))
    renderPage()
    expect(screen.getByRole('status')).toBeInTheDocument()
  })

  it('renders bands in a table', async () => {
    vi.mocked(bandsApi.listBands).mockResolvedValue([sampleBand])
    renderPage()
    expect(await screen.findByText('Engineer')).toBeInTheDocument()
    expect(screen.getByText('NA')).toBeInTheDocument()
    expect(screen.getByText('L3')).toBeInTheDocument()
    expect(screen.getByText('open')).toBeInTheDocument()
  })

  it('shows empty state when no bands', async () => {
    vi.mocked(bandsApi.listBands).mockResolvedValue([])
    renderPage()
    expect(await screen.findByText(/no salary bands for this date/i)).toBeInTheDocument()
  })

  it('shows error when API fails', async () => {
    vi.mocked(bandsApi.listBands).mockRejectedValue(new Error('Failed to load'))
    renderPage()
    expect(await screen.findByRole('alert')).toHaveTextContent('Failed to load')
  })

  it('formats money correctly', async () => {
    vi.mocked(bandsApi.listBands).mockResolvedValue([sampleBand])
    renderPage()
    await screen.findByText('Engineer')
    expect(screen.getByText('$70,000.00')).toBeInTheDocument()
    expect(screen.getByText('$100,000.00')).toBeInTheDocument()
    expect(screen.getByText('$130,000.00')).toBeInTheDocument()
  })

  it('admin sees New band button', async () => {
    vi.mocked(bandsApi.listBands).mockResolvedValue([])
    renderPage(adminUser)
    await screen.findByText(/no salary bands/i)
    expect(screen.getByRole('button', { name: /new band/i })).toBeInTheDocument()
  })

  it('viewer does not see New band button', async () => {
    vi.mocked(bandsApi.listBands).mockResolvedValue([])
    renderPage(viewerUser)
    await screen.findByText(/no salary bands/i)
    expect(screen.queryByRole('button', { name: /new band/i })).not.toBeInTheDocument()
  })

  it('refetches when effective date changes', async () => {
    vi.mocked(bandsApi.listBands).mockResolvedValue([])
    renderPage()
    await screen.findByText(/no salary bands/i)
    const input = screen.getByLabelText(/effective on/i)
    await userEvent.clear(input)
    await userEvent.type(input, '2023-01-01')
    expect(vi.mocked(bandsApi.listBands).mock.calls.length).toBeGreaterThan(1)
  })
})
