import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { vi, describe, it, expect, beforeEach } from 'vitest'
import { SignupPage } from '../pages/SignupPage'
import * as registrationsApi from '../api/registrations'

function renderSignupPage(search = '') {
  return render(
    <MemoryRouter initialEntries={[`/signup${search}`]}>
      <Routes>
        <Route path="/signup" element={<SignupPage />} />
        <Route path="/employees" element={<div>Employees page</div>} />
      </Routes>
    </MemoryRouter>,
  )
}

describe('SignupPage', () => {
  describe('no token in URL', () => {
    it('shows the no-invitation message and no form', () => {
      renderSignupPage()
      expect(screen.getByText(/invitation link/i)).toBeInTheDocument()
      expect(screen.queryByLabelText(/name/i)).not.toBeInTheDocument()
    })
  })

  describe('with a token in URL', () => {
    beforeEach(() => {
      vi.spyOn(registrationsApi, 'signup')
    })

    it('shows the signup form', () => {
      renderSignupPage('?token=abc123')
      expect(screen.getByLabelText('Name')).toBeInTheDocument()
      expect(screen.getByLabelText('Email')).toBeInTheDocument()
      expect(screen.getByLabelText('Password')).toBeInTheDocument()
      expect(screen.getByRole('button', { name: /create account/i })).toBeInTheDocument()
    })

    it('redirects to /employees on successful signup', async () => {
      registrationsApi.signup.mockResolvedValue({
        status: 201,
        body: { token: 'jwt-token', user: { id: 1, name: 'Jane', email: 'jane@x.com', role: 'hr_admin' } },
      })
      renderSignupPage('?token=abc123')
      await userEvent.type(screen.getByLabelText('Name'), 'Jane Doe')
      await userEvent.type(screen.getByLabelText('Email'), 'jane@x.com')
      await userEvent.type(screen.getByLabelText('Password'), 'password123')
      await userEvent.click(screen.getByRole('button', { name: /create account/i }))
      await waitFor(() => expect(screen.getByText('Employees page')).toBeInTheDocument())
    })

    it('shows error message on 422', async () => {
      registrationsApi.signup.mockResolvedValue({
        status: 422,
        body: { error: 'This invitation link is invalid or has already been used.' },
      })
      renderSignupPage('?token=used-token')
      await userEvent.type(screen.getByLabelText('Name'), 'Jane')
      await userEvent.type(screen.getByLabelText('Email'), 'jane@x.com')
      await userEvent.type(screen.getByLabelText('Password'), 'pw')
      await userEvent.click(screen.getByRole('button', { name: /create account/i }))
      expect(await screen.findByRole('alert')).toHaveTextContent('invalid or has already been used')
    })
  })
})
