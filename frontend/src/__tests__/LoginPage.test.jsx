import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { vi, describe, it, expect } from 'vitest'
import { LoginPage } from '../pages/LoginPage'
import { AuthContext } from '../contexts/AuthContext'

function renderLoginPage({ user = null, login = vi.fn() } = {}) {
  return render(
    <AuthContext.Provider value={{ user, loading: false, login, logout: vi.fn() }}>
      <MemoryRouter initialEntries={['/login']}>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/employees" element={<div>Employees page</div>} />
        </Routes>
      </MemoryRouter>
    </AuthContext.Provider>,
  )
}

describe('LoginPage', () => {
  it('renders the login form', () => {
    renderLoginPage()
    expect(screen.getByLabelText('Email')).toBeInTheDocument()
    expect(screen.getByLabelText('Password')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /sign in/i })).toBeInTheDocument()
  })

  it('redirects to /employees when already authenticated', () => {
    renderLoginPage({ user: { id: 1, name: 'Admin', role: 'hr_admin' } })
    expect(screen.getByText('Employees page')).toBeInTheDocument()
  })

  it('calls login with email and password on submit', async () => {
    const login = vi.fn().mockResolvedValue({ id: 1, name: 'Admin', role: 'hr_admin' })
    renderLoginPage({ login })
    await userEvent.type(screen.getByLabelText('Email'), 'admin@example.com')
    await userEvent.type(screen.getByLabelText('Password'), 'password')
    await userEvent.click(screen.getByRole('button', { name: /sign in/i }))
    await waitFor(() => expect(login).toHaveBeenCalledWith('admin@example.com', 'password'))
  })

  it('shows an error message when login fails', async () => {
    const login = vi.fn().mockRejectedValue(new Error('invalid credentials'))
    renderLoginPage({ login })
    await userEvent.type(screen.getByLabelText('Email'), 'bad@example.com')
    await userEvent.type(screen.getByLabelText('Password'), 'wrong')
    await userEvent.click(screen.getByRole('button', { name: /sign in/i }))
    expect(await screen.findByRole('alert')).toHaveTextContent('invalid credentials')
  })

  it('disables submit button while submitting', async () => {
    const login = vi.fn(() => new Promise(() => {})) // never resolves
    renderLoginPage({ login })
    await userEvent.type(screen.getByLabelText('Email'), 'admin@example.com')
    await userEvent.type(screen.getByLabelText('Password'), 'password')
    await userEvent.click(screen.getByRole('button', { name: /sign in/i }))
    expect(screen.getByRole('button', { name: /signing in/i })).toBeDisabled()
  })
})
