import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { vi, describe, it, expect, beforeEach } from 'vitest'
import { EmployeeDetailPage } from '../pages/EmployeeDetailPage'
import { AuthContext } from '../contexts/AuthContext'
import * as employeesApi from '../api/employees'

vi.mock('../api/employees')

const adminUser = { id: 1, name: 'Admin', role: 'hr_admin' }
const viewerUser = { id: 2, name: 'Viewer', role: 'viewer' }

function renderPage(user = adminUser, employeeId = '1') {
  return render(
    <AuthContext.Provider value={{ user, loading: false, login: vi.fn(), logout: vi.fn() }}>
      <MemoryRouter initialEntries={[`/employees/${employeeId}`]}>
        <Routes>
          <Route path="/employees/:id" element={<EmployeeDetailPage />} />
          <Route path="/employees" element={<div>List page</div>} />
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
  email: 'alice@example.com',
  department: { id: 1, name: 'Engineering' },
  job_title: 'Engineer',
  job_level: 'L3',
  country_code: 'US',
  hire_date: '2020-01-15',
  status: 'active',
}

const sampleSalary = {
  id: 10,
  employee_id: 1,
  amount_minor_units: 8000000,
  currency: 'USD',
  effective_date: '2023-01-01',
  reason: 'merit',
}

describe('EmployeeDetailPage', () => {
  beforeEach(() => {
    vi.resetAllMocks()
  })

  it('shows a loading spinner while fetching', () => {
    employeesApi.getEmployee.mockReturnValue(new Promise(() => {}))
    employeesApi.listSalaries.mockReturnValue(new Promise(() => {}))
    renderPage()
    expect(screen.getByRole('status')).toBeInTheDocument()
  })

  it('renders employee details', async () => {
    employeesApi.getEmployee.mockResolvedValue(sampleEmployee)
    employeesApi.listSalaries.mockResolvedValue([])
    renderPage()
    expect(await screen.findByText('Alice Smith')).toBeInTheDocument()
    expect(screen.getByText('alice@example.com')).toBeInTheDocument()
    expect(screen.getByText('Engineering')).toBeInTheDocument()
  })

  it('renders salary timeline', async () => {
    employeesApi.getEmployee.mockResolvedValue(sampleEmployee)
    employeesApi.listSalaries.mockResolvedValue([sampleSalary])
    renderPage()
    expect(await screen.findByText('2023-01-01')).toBeInTheDocument()
    expect(screen.getByText('merit')).toBeInTheDocument()
  })

  it('shows empty state when no salaries', async () => {
    employeesApi.getEmployee.mockResolvedValue(sampleEmployee)
    employeesApi.listSalaries.mockResolvedValue([])
    renderPage()
    await screen.findByText('Alice Smith')
    expect(await screen.findByText(/no salary records/i)).toBeInTheDocument()
  })

  it('shows Record salary change button for admin', async () => {
    employeesApi.getEmployee.mockResolvedValue(sampleEmployee)
    employeesApi.listSalaries.mockResolvedValue([])
    renderPage(adminUser)
    await screen.findByText('Alice Smith')
    expect(screen.getByRole('button', { name: /record salary change/i })).toBeInTheDocument()
  })

  it('hides Record salary change button for viewer', async () => {
    employeesApi.getEmployee.mockResolvedValue(sampleEmployee)
    employeesApi.listSalaries.mockResolvedValue([])
    renderPage(viewerUser)
    await screen.findByText('Alice Smith')
    expect(screen.queryByRole('button', { name: /record salary change/i })).not.toBeInTheDocument()
  })

  it('opens raise form when button clicked', async () => {
    employeesApi.getEmployee.mockResolvedValue(sampleEmployee)
    employeesApi.listSalaries.mockResolvedValue([])
    renderPage(adminUser)
    await screen.findByText('Alice Smith')
    await userEvent.click(screen.getByRole('button', { name: /record salary change/i }))
    expect(screen.getByRole('dialog')).toBeInTheDocument()
  })

  it('shows error when employee fetch fails', async () => {
    employeesApi.getEmployee.mockRejectedValue(new Error('not found'))
    employeesApi.listSalaries.mockResolvedValue([])
    renderPage()
    expect(await screen.findByRole('alert')).toHaveTextContent('not found')
  })
})
