import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { vi, describe, it, expect, beforeEach } from 'vitest'
import { BandView } from '../pages/BandView'
import { AuthContext } from '../contexts/AuthContext'
import * as bandsApi from '../api/bands'

vi.mock('../api/bands')

const adminUser = { id: 1, name: 'Admin', role: 'hr_admin' }

function renderPage(user = adminUser) {
  return render(
    <AuthContext.Provider value={{ user, loading: false, login: vi.fn(), logout: vi.fn() }}>
      <MemoryRouter>
        <BandView />
      </MemoryRouter>
    </AuthContext.Provider>,
  )
}

const sampleBand = {
  id: 1,
  pay_zone_name: 'NA',
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
  })

  it('shows loading spinner while fetching', () => {
    bandsApi.listBands.mockReturnValue(new Promise(() => {}))
    renderPage()
    expect(screen.getByRole('status')).toBeInTheDocument()
  })

  it('renders bands in a table', async () => {
    bandsApi.listBands.mockResolvedValue([sampleBand])
    renderPage()
    expect(await screen.findByText('Engineer')).toBeInTheDocument()
    expect(screen.getByText('NA')).toBeInTheDocument()
    expect(screen.getByText('L3')).toBeInTheDocument()
    expect(screen.getByText('open')).toBeInTheDocument()
  })

  it('shows empty state when no bands', async () => {
    bandsApi.listBands.mockResolvedValue([])
    renderPage()
    expect(await screen.findByText(/no salary bands found/i)).toBeInTheDocument()
  })

  it('shows error when API fails', async () => {
    bandsApi.listBands.mockRejectedValue(new Error('Failed to load'))
    renderPage()
    expect(await screen.findByRole('alert')).toHaveTextContent('Failed to load')
  })

  it('formats money correctly', async () => {
    bandsApi.listBands.mockResolvedValue([sampleBand])
    renderPage()
    await screen.findByText('Engineer')
    expect(screen.getByText('$70,000.00')).toBeInTheDocument()
    expect(screen.getByText('$100,000.00')).toBeInTheDocument()
    expect(screen.getByText('$130,000.00')).toBeInTheDocument()
  })

  it('refetches when effective date changes', async () => {
    bandsApi.listBands.mockResolvedValue([])
    renderPage()
    await screen.findByText(/no salary bands/i)
    const input = screen.getByLabelText(/effective on/i)
    await userEvent.clear(input)
    await userEvent.type(input, '2023-01-01')
    // Each character triggers a re-render; at minimum a second fetch is issued
    expect(bandsApi.listBands.mock.calls.length).toBeGreaterThan(1)
  })
})
