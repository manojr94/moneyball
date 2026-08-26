import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { vi, describe, it, expect, beforeEach } from 'vitest'
import { ImportPage } from '../pages/ImportPage'
import { AuthContext } from '../contexts/AuthContext'
import * as importsApi from '../api/imports'

vi.mock('../api/imports')

const adminUser = { id: 1, name: 'Admin', role: 'hr_admin' }
const viewerUser = { id: 2, name: 'Viewer', role: 'viewer' }

function renderPage(user = adminUser) {
  return render(
    <AuthContext.Provider value={{ user, loading: false, login: vi.fn(), logout: vi.fn() }}>
      <MemoryRouter>
        <ImportPage />
      </MemoryRouter>
    </AuthContext.Provider>,
  )
}

const successPreview = {
  status: 200,
  body: {
    committed: false,
    dry_run: true,
    header_error: null,
    summary: {
      rows_total: 2,
      rows_valid: 2,
      rows_invalid: 0,
      employees_created: 0,
      salaries_created: 0,
      errors_reported: 0,
      errors_capped_at: 100,
    },
    errors: [],
  },
}

const errorPreview = {
  status: 200,
  body: {
    committed: false,
    dry_run: true,
    header_error: null,
    summary: {
      rows_total: 3,
      rows_valid: 2,
      rows_invalid: 1,
      employees_created: 0,
      salaries_created: 0,
      errors_reported: 1,
      errors_capped_at: 100,
    },
    errors: [{ row: 3, employee_number: 'EMP003', messages: ['Email has already been taken'] }],
  },
}

const committedResult = {
  status: 201,
  body: {
    committed: true,
    dry_run: false,
    header_error: null,
    summary: {
      rows_total: 2,
      rows_valid: 2,
      rows_invalid: 0,
      employees_created: 2,
      salaries_created: 0,
      errors_reported: 0,
      errors_capped_at: 100,
    },
    errors: [],
  },
}

function makeFile(name = 'employees.csv') {
  return new File(['employee_number,first_name\nEMP001,Alice'], name, { type: 'text/csv' })
}

describe('ImportPage', () => {
  beforeEach(() => vi.clearAllMocks())

  it('renders the file picker and preview button', () => {
    renderPage()
    expect(screen.getByLabelText(/csv file/i)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /preview/i })).toBeInTheDocument()
  })

  it('preview button is disabled until a file is chosen', () => {
    renderPage()
    expect(screen.getByRole('button', { name: /preview/i })).toBeDisabled()
  })

  it('shows preview summary after a successful dry-run', async () => {
    importsApi.uploadEmployees.mockResolvedValue(successPreview)
    renderPage()

    await userEvent.upload(screen.getByLabelText(/csv file/i), makeFile())
    await userEvent.click(screen.getByRole('button', { name: /preview/i }))

    await waitFor(() => expect(screen.getByText(/2 of 2 rows valid/i)).toBeInTheDocument())
  })

  it('shows a confirm button when preview has no errors', async () => {
    importsApi.uploadEmployees.mockResolvedValue(successPreview)
    renderPage()

    await userEvent.upload(screen.getByLabelText(/csv file/i), makeFile())
    await userEvent.click(screen.getByRole('button', { name: /preview/i }))

    await waitFor(() =>
      expect(screen.getByRole('button', { name: /confirm import/i })).toBeInTheDocument(),
    )
  })

  it('shows row errors when preview finds invalid rows', async () => {
    importsApi.uploadEmployees.mockResolvedValue(errorPreview)
    renderPage()

    await userEvent.upload(screen.getByLabelText(/csv file/i), makeFile())
    await userEvent.click(screen.getByRole('button', { name: /preview/i }))

    await waitFor(() => expect(screen.getByText(/email has already been taken/i)).toBeInTheDocument())
  })

  it('does not show confirm button when preview has errors', async () => {
    importsApi.uploadEmployees.mockResolvedValue(errorPreview)
    renderPage()

    await userEvent.upload(screen.getByLabelText(/csv file/i), makeFile())
    await userEvent.click(screen.getByRole('button', { name: /preview/i }))

    await waitFor(() => screen.getByText(/email has already been taken/i))
    expect(screen.queryByRole('button', { name: /confirm import/i })).not.toBeInTheDocument()
  })

  it('shows success message after confirmed import', async () => {
    importsApi.uploadEmployees
      .mockResolvedValueOnce(successPreview)
      .mockResolvedValueOnce(committedResult)
    renderPage()

    await userEvent.upload(screen.getByLabelText(/csv file/i), makeFile())
    await userEvent.click(screen.getByRole('button', { name: /preview/i }))
    await waitFor(() => screen.getByRole('button', { name: /confirm import/i }))
    await userEvent.click(screen.getByRole('button', { name: /confirm import/i }))

    await waitFor(() =>
      expect(screen.getByText(/import complete.*2 employees added/i)).toBeInTheDocument(),
    )
  })

  it('shows header_error when the file is rejected outright', async () => {
    importsApi.uploadEmployees.mockResolvedValue({
      status: 422,
      body: { header_error: 'missing required column(s): email', committed: false, errors: [] },
    })
    renderPage()

    await userEvent.upload(screen.getByLabelText(/csv file/i), makeFile())
    await userEvent.click(screen.getByRole('button', { name: /preview/i }))

    await waitFor(() =>
      expect(screen.getByText(/missing required column/i)).toBeInTheDocument(),
    )
  })

  it('shows an error message on network failure', async () => {
    importsApi.uploadEmployees.mockRejectedValue(new Error('Server error (500)'))
    renderPage()

    await userEvent.upload(screen.getByLabelText(/csv file/i), makeFile())
    await userEvent.click(screen.getByRole('button', { name: /preview/i }))

    await waitFor(() => expect(screen.getByText(/server error/i)).toBeInTheDocument())
  })

  it('resets to file picker after clicking Import another file', async () => {
    importsApi.uploadEmployees
      .mockResolvedValueOnce(successPreview)
      .mockResolvedValueOnce(committedResult)
    renderPage()

    await userEvent.upload(screen.getByLabelText(/csv file/i), makeFile())
    await userEvent.click(screen.getByRole('button', { name: /preview/i }))
    await waitFor(() => screen.getByRole('button', { name: /confirm import/i }))
    await userEvent.click(screen.getByRole('button', { name: /confirm import/i }))
    await waitFor(() => screen.getByText(/import complete/i))
    await userEvent.click(screen.getByRole('button', { name: /import another file/i }))

    expect(screen.getByRole('button', { name: /preview/i })).toBeInTheDocument()
  })
})

describe('ImportPage authorization', () => {
  it('redirects viewers away from the import page', () => {
    renderPage(viewerUser)
    expect(screen.queryByText(/import employees/i)).not.toBeInTheDocument()
  })
})
