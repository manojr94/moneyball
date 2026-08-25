import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { vi, describe, it, expect, beforeEach } from 'vitest'
import { EmployeeListPage } from '../pages/EmployeeListPage'
import { AuthContext } from '../contexts/AuthContext'
import * as employeesApi from '../api/employees'

vi.mock('../api/employees')

const adminUser = { id: 1, name: 'Admin', role: 'hr_admin' }

function renderPage(user = adminUser) {
  return render(
    <AuthContext.Provider value={{ user, loading: false, login: vi.fn(), logout: vi.fn() }}>
      <MemoryRouter initialEntries={['/employees']}>
        <Routes>
          <Route path="/employees" element={<EmployeeListPage />} />
          <Route path="/employees/:id" element={<div>Detail page</div>} />
        </Routes>
      </MemoryRouter>
    </AuthContext.Provider>,
  )
}

const sampleEmployee = {
  id: 1,
  employee_number: 'EMP001',
  first_name: 'Alice',
  last_name: 'Smith',
  department: { id: 1, name: 'Engineering' },
  job_title: 'Engineer',
  job_level: 'L3',
  country_code: 'US',
  status: 'active',
}

describe('EmployeeListPage', () => {
  beforeEach(() => {
    vi.resetAllMocks()
  })

  it('shows a loading spinner while fetching', () => {
    employeesApi.listEmployees.mockReturnValue(new Promise(() => {}))
    renderPage()
    expect(screen.getByRole('status')).toBeInTheDocument()
  })

  it('renders a table of employees', async () => {
    employeesApi.listEmployees.mockResolvedValue({
      data: [sampleEmployee],
      meta: { next_cursor: null },
    })
    renderPage()
    expect(await screen.findByText('EMP001')).toBeInTheDocument()
    expect(screen.getByText('Smith, Alice')).toBeInTheDocument()
    expect(screen.getByText('Engineering')).toBeInTheDocument()
  })

  it('shows empty state when no employees match', async () => {
    employeesApi.listEmployees.mockResolvedValue({ data: [], meta: { next_cursor: null } })
    renderPage()
    expect(await screen.findByText(/no employees match/i)).toBeInTheDocument()
  })

  it('shows error message on API failure', async () => {
    employeesApi.listEmployees.mockRejectedValue(new Error('Server error'))
    renderPage()
    expect(await screen.findByRole('alert')).toHaveTextContent('Server error')
  })

  it('disables previous button on first page', async () => {
    employeesApi.listEmployees.mockResolvedValue({
      data: [sampleEmployee],
      meta: { next_cursor: null },
    })
    renderPage()
    await screen.findByText('EMP001')
    expect(screen.getByRole('button', { name: /previous/i })).toBeDisabled()
  })

  it('enables next button when next_cursor is present', async () => {
    employeesApi.listEmployees.mockResolvedValue({
      data: [sampleEmployee],
      meta: { next_cursor: 'abc123' },
    })
    renderPage()
    await screen.findByText('EMP001')
    expect(screen.getByRole('button', { name: /next/i })).not.toBeDisabled()
  })

  it('refetches when status filter changes', async () => {
    employeesApi.listEmployees.mockResolvedValue({ data: [], meta: { next_cursor: null } })
    renderPage()
    await screen.findByText(/no employees/i)
    await userEvent.selectOptions(screen.getByRole('combobox', { name: /status filter/i }), 'inactive')
    await waitFor(() => expect(employeesApi.listEmployees).toHaveBeenCalledTimes(2))
  })

  it('shows status badges', async () => {
    employeesApi.listEmployees.mockResolvedValue({
      data: [sampleEmployee],
      meta: { next_cursor: null },
    })
    renderPage()
    await screen.findByText('EMP001')
    const badge = screen.getAllByText('active').find((el) => el.classList.contains('status-badge'))
    expect(badge).toHaveClass('status-active')
  })
})
