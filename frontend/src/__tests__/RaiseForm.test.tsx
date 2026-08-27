import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { vi, describe, it, expect, beforeEach } from 'vitest'
import { RaiseForm } from '../components/RaiseForm'
import { AuthContext } from '../contexts/AuthContext'
import type { AuthContextValue } from '../contexts/AuthContext'
import type { User } from '../types'
import * as employeesApi from '../api/employees'
import * as currenciesApi from '../api/currencies'

vi.mock('../api/employees')
vi.mock('../api/currencies')

const adminUser: User = { id: 1, name: 'Admin', role: 'hr_admin', email: 'admin@example.com' }
const viewerUser: User = { id: 2, name: 'Viewer', role: 'viewer', email: 'viewer@example.com' }

function makeCtx(overrides: Partial<AuthContextValue> = {}): AuthContextValue {
  return {
    user: adminUser,
    loading: false,
    login: vi.fn(),
    loginWithToken: vi.fn(),
    logout: vi.fn(),
    ...overrides,
  }
}

function renderForm({ user = adminUser, onSuccess = vi.fn(), onCancel = vi.fn() } = {}) {
  return render(
    <AuthContext.Provider value={makeCtx({ user })}>
      <RaiseForm employeeId="1" onSuccess={onSuccess} onCancel={onCancel} />
    </AuthContext.Provider>,
  )
}

describe('RaiseForm', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    vi.mocked(currenciesApi.listCurrencies).mockResolvedValue(['EUR', 'JPY', 'USD'])
  })

  it('renders the form fields for admin', async () => {
    renderForm()
    expect(screen.getByRole('dialog')).toBeInTheDocument()
    expect(screen.getByLabelText(/amount/i)).toBeInTheDocument()
    expect(await screen.findByLabelText(/currency/i)).toBeInTheDocument()
    expect(screen.getByLabelText(/effective date/i)).toBeInTheDocument()
    expect(screen.getByLabelText(/reason/i)).toBeInTheDocument()
  })

  it('does not render for viewer', () => {
    renderForm({ user: viewerUser })
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('calls createSalary with correct payload and invokes onSuccess', async () => {
    vi.mocked(employeesApi.createSalary).mockResolvedValue({
      id: 99, employee_id: 1, amount_minor_units: 8000000, currency: 'USD',
      effective_date: '2024-01-01', reason: 'merit', created_by_id: null,
    })
    const onSuccess = vi.fn()
    renderForm({ onSuccess })
    await userEvent.type(screen.getByLabelText(/amount/i), '80000')
    await screen.findByLabelText(/currency/i)
    await userEvent.selectOptions(screen.getByLabelText(/currency/i), 'USD')
    await userEvent.click(screen.getByRole('button', { name: /save/i }))
    await waitFor(() => expect(onSuccess).toHaveBeenCalled())
    expect(employeesApi.createSalary).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({ amount_minor_units: 8000000, currency: 'USD' }),
    )
  })

  it('shows error when createSalary fails', async () => {
    vi.mocked(employeesApi.createSalary).mockRejectedValue(new Error('Validation failed'))
    renderForm()
    await userEvent.type(screen.getByLabelText(/amount/i), '1000')
    await userEvent.click(screen.getByRole('button', { name: /save/i }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Validation failed')
  })

  it('calls onCancel when Cancel is clicked', async () => {
    const onCancel = vi.fn()
    renderForm({ onCancel })
    await userEvent.click(screen.getByRole('button', { name: /cancel/i }))
    expect(onCancel).toHaveBeenCalled()
  })

  it('disables save button while submitting', async () => {
    vi.mocked(employeesApi.createSalary).mockReturnValue(new Promise<never>(() => {}))
    renderForm()
    await userEvent.type(screen.getByLabelText(/amount/i), '1000')
    await userEvent.click(screen.getByRole('button', { name: /save/i }))
    expect(screen.getByRole('button', { name: /saving/i })).toBeDisabled()
  })
})
