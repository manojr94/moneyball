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
  hire_date: '2022-01-01',
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

  describe('sortable column headers', () => {
    beforeEach(() => {
      employeesApi.listEmployees.mockResolvedValue({
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
      // default sort is last_name — Name header should have the visible chevron
      const nameHeader = screen.getByRole('columnheader', { name: /name/i })
      const chevron = nameHeader.querySelector('svg')
      expect(chevron).toHaveClass('opacity-100')
      expect(chevron).toHaveClass('text-indigo-600')
      // Number header chevron is hidden by default
      const numberHeader = screen.getByRole('columnheader', { name: /number/i })
      expect(numberHeader.querySelector('svg')).toHaveClass('opacity-0')
    })

    it('changing sort resets to page 1', async () => {
      renderPage()
      await screen.findByText('EMP001')
      const callsBefore = employeesApi.listEmployees.mock.calls.length
      await userEvent.click(screen.getByRole('columnheader', { name: /hire date/i }))
      await waitFor(() =>
        expect(employeesApi.listEmployees.mock.calls.length).toBeGreaterThan(callsBefore),
      )
      // cursor must be reset — no cursor param on the new call
      const lastCall = employeesApi.listEmployees.mock.calls.at(-1)[0]
      expect(lastCall.cursor).toBeUndefined()
    })
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
