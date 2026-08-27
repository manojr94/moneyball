import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { vi, describe, it, expect, beforeEach } from 'vitest'
import { EmployeeListPage } from '../pages/EmployeeListPage'
import { AuthContext } from '../contexts/AuthContext'
import type { AuthContextValue } from '../contexts/AuthContext'
import type { User, Employee } from '../types'
import * as employeesApi from '../api/employees'
import * as departmentsApi from '../api/departments'

vi.mock('../api/employees')
vi.mock('../api/departments')

const adminUser: User = { id: 1, name: 'Admin', role: 'hr_admin', email: 'admin@example.com' }

function makeCtx(user: User): AuthContextValue {
  return { user, loading: false, login: vi.fn(), loginWithToken: vi.fn(), logout: vi.fn() }
}

function renderPage(user = adminUser) {
  return render(
    <AuthContext.Provider value={makeCtx(user)}>
      <MemoryRouter initialEntries={['/employees']}>
        <Routes>
          <Route path="/employees" element={<EmployeeListPage />} />
          <Route path="/employees/:id" element={<div>Detail page</div>} />
        </Routes>
      </MemoryRouter>
    </AuthContext.Provider>,
  )
}

const sampleEmployee: Employee = {
  id: 1,
  employee_number: 'EMP001',
  first_name: 'Alice',
  last_name: 'Smith',
  email: 'alice@example.com',
  country_code: 'US',
  department_id: 1,
  department: { id: 1, name: 'Engineering', slug: 'engineering' },
  job_title: 'Engineer',
  job_level: 'L3',
  hire_date: '2022-01-01',
  status: 'active',
  terminated_on: null,
}

describe('EmployeeListPage', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    vi.mocked(departmentsApi.listDepartments).mockResolvedValue([
      { id: 1, name: 'Engineering', slug: 'engineering' },
    ])
  })

  it('shows a loading spinner while fetching', () => {
    vi.mocked(employeesApi.listEmployees).mockReturnValue(new Promise<never>(() => {}))
    renderPage()
    expect(screen.getByRole('status')).toBeInTheDocument()
  })

  it('renders a table of employees', async () => {
    vi.mocked(employeesApi.listEmployees).mockResolvedValue({
      data: [sampleEmployee],
      meta: { next_cursor: null },
    })
    renderPage()
    expect(await screen.findByText('EMP001')).toBeInTheDocument()
    expect(screen.getByText('Smith, Alice')).toBeInTheDocument()
    expect(screen.getByText('Engineering')).toBeInTheDocument()
  })

  it('shows empty state when no employees match', async () => {
    vi.mocked(employeesApi.listEmployees).mockResolvedValue({ data: [], meta: { next_cursor: null } })
    renderPage()
    expect(await screen.findByText(/no employees match/i)).toBeInTheDocument()
  })

  it('shows error message on API failure', async () => {
    vi.mocked(employeesApi.listEmployees).mockRejectedValue(new Error('Server error'))
    renderPage()
    expect(await screen.findByRole('alert')).toHaveTextContent('Server error')
  })

  it('disables previous button on first page', async () => {
    vi.mocked(employeesApi.listEmployees).mockResolvedValue({
      data: [sampleEmployee],
      meta: { next_cursor: null },
    })
    renderPage()
    await screen.findByText('EMP001')
    expect(screen.getByRole('button', { name: /previous/i })).toBeDisabled()
  })

  it('enables next button when next_cursor is present', async () => {
    vi.mocked(employeesApi.listEmployees).mockResolvedValue({
      data: [sampleEmployee],
      meta: { next_cursor: 'abc123' },
    })
    renderPage()
    await screen.findByText('EMP001')
    expect(screen.getByRole('button', { name: /next/i })).not.toBeDisabled()
  })

  describe('filter panel', () => {
    beforeEach(() => {
      vi.mocked(employeesApi.listEmployees).mockResolvedValue({ data: [], meta: { next_cursor: null } })
    })

    it('panel is closed by default; opens on Filters button click', async () => {
      renderPage()
      await screen.findByText(/no employees/i)
      expect(screen.queryByRole('combobox', { name: /status filter/i })).not.toBeInTheDocument()
      await userEvent.click(screen.getByRole('button', { name: /filters/i }))
      expect(screen.getByRole('combobox', { name: /status filter/i })).toBeInTheDocument()
    })

    it('refetches when status filter changes', async () => {
      renderPage()
      await screen.findByText(/no employees/i)
      await userEvent.click(screen.getByRole('button', { name: /filters/i }))
      await userEvent.selectOptions(screen.getByRole('combobox', { name: /status filter/i }), 'inactive')
      await waitFor(() => expect(employeesApi.listEmployees).toHaveBeenCalledTimes(2))
    })

    it('shows active filter count on the button', async () => {
      renderPage()
      await screen.findByText(/no employees/i)
      await userEvent.click(screen.getByRole('button', { name: /filters/i }))
      await userEvent.selectOptions(screen.getByRole('combobox', { name: /status filter/i }), 'active')
      await waitFor(() =>
        expect(screen.getByRole('button', { name: /filters \(1\)/i })).toBeInTheDocument(),
      )
    })

    it('Clear all resets all filters', async () => {
      renderPage()
      await screen.findByText(/no employees/i)
      await userEvent.click(screen.getByRole('button', { name: /filters/i }))
      await userEvent.selectOptions(screen.getByRole('combobox', { name: /status filter/i }), 'active')
      await waitFor(() => screen.getByRole('button', { name: /clear all/i }))
      await userEvent.click(screen.getByRole('button', { name: /clear all/i }))
      await waitFor(() =>
        expect(screen.queryByRole('button', { name: /filters \(/i })).not.toBeInTheDocument(),
      )
    })
  })

  describe('sortable column headers', () => {
    beforeEach(() => {
      vi.mocked(employeesApi.listEmployees).mockResolvedValue({
        data: [sampleEmployee],
        meta: { next_cursor: null },
      })
    })

    it('clicking Name header re-fetches with sort: last_name', async () => {
      renderPage()
      await screen.findByText('EMP001')
      await userEvent.click(screen.getByRole('columnheader', { name: /name/i }))
      await waitFor(() =>
        expect(employeesApi.listEmployees).toHaveBeenLastCalledWith(
          expect.objectContaining({ sort: 'last_name' }),
        ),
      )
    })

    it('clicking Name header twice switches to descending', async () => {
      renderPage()
      await screen.findByText('EMP001')
      await userEvent.click(screen.getByRole('columnheader', { name: /^name$/i }))
      await waitFor(() =>
        expect(employeesApi.listEmployees).toHaveBeenLastCalledWith(
          expect.objectContaining({ sort: 'last_name', sort_dir: 'asc' }),
        ),
      )
      await userEvent.click(screen.getByRole('columnheader', { name: /^name$/i }))
      await waitFor(() =>
        expect(employeesApi.listEmployees).toHaveBeenLastCalledWith(
          expect.objectContaining({ sort: 'last_name', sort_dir: 'desc' }),
        ),
      )
    })

    it('clicking Hire date header re-fetches with sort: hire_date', async () => {
      renderPage()
      await screen.findByText('EMP001')
      await userEvent.click(screen.getByRole('columnheader', { name: /hire date/i }))
      await waitFor(() =>
        expect(employeesApi.listEmployees).toHaveBeenLastCalledWith(
          expect.objectContaining({ sort: 'hire_date' }),
        ),
      )
    })

    it('clicking Number header re-fetches with sort: employee_number', async () => {
      renderPage()
      await screen.findByText('EMP001')
      await userEvent.click(screen.getByRole('columnheader', { name: /number/i }))
      await waitFor(() =>
        expect(employeesApi.listEmployees).toHaveBeenLastCalledWith(
          expect.objectContaining({ sort: 'employee_number' }),
        ),
      )
    })

    it('active sort column header has indigo chevron; others do not', async () => {
      renderPage()
      await screen.findByText('EMP001')
      const numberHeader = screen.getByRole('columnheader', { name: /number/i })
      const chevron = numberHeader.querySelector('svg')
      expect(chevron).toHaveClass('text-indigo-600')
      const nameHeader = screen.getByRole('columnheader', { name: /^name$/i })
      expect(nameHeader.querySelector('svg')).toHaveClass('opacity-0')
    })

    it('changing sort resets to page 1', async () => {
      renderPage()
      await screen.findByText('EMP001')
      const callsBefore = vi.mocked(employeesApi.listEmployees).mock.calls.length
      await userEvent.click(screen.getByRole('columnheader', { name: /hire date/i }))
      await waitFor(() =>
        expect(vi.mocked(employeesApi.listEmployees).mock.calls.length).toBeGreaterThan(callsBefore),
      )
      const lastCall = vi.mocked(employeesApi.listEmployees).mock.calls.at(-1)?.[0]
      expect(lastCall?.['cursor']).toBeUndefined()
    })
  })

  it('shows status badges', async () => {
    vi.mocked(employeesApi.listEmployees).mockResolvedValue({
      data: [sampleEmployee],
      meta: { next_cursor: null },
    })
    renderPage()
    await screen.findByText('EMP001')
    const badge = screen.getAllByText('active').find((el) => el.classList.contains('status-badge'))
    expect(badge).toHaveClass('status-active')
  })
})
