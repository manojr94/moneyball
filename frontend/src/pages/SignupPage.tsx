import { useState } from 'react'
import { useSearchParams, useNavigate, Link } from 'react-router-dom'
import { signup } from '../api/registrations'
import { useAuth } from '../contexts/AuthContext'
import type { AuthResponse } from '../types'

export function SignupPage() {
  const { loginWithToken } = useAuth()
  const [searchParams] = useSearchParams()
  const token = searchParams.get('token')
  const navigate = useNavigate()

  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  if (!token) {
    return (
      <div className="min-h-screen bg-slate-50 flex items-center justify-center px-4">
        <div className="w-full max-w-sm bg-white rounded-xl shadow-sm border border-slate-200 p-8 text-center">
          <h1 className="text-2xl font-bold text-slate-900 mb-2">Sign up</h1>
          <p className="text-sm text-slate-600">
            You need an invitation link to sign up. Contact the admin to request one.
          </p>
          <Link to="/login" className="mt-4 inline-block text-sm text-indigo-600 hover:underline">
            Back to login
          </Link>
        </div>
      </div>
    )
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setSubmitting(true)
    try {
      const { status, body } = await signup({ name, email, password, token: token! })
      if (status === 201) {
        const data = body as AuthResponse
        loginWithToken(data.token, data.user)
        navigate('/import', { replace: true })
      } else {
        const err = body as Record<string, unknown>
        setError((err['error'] as string | undefined) ?? (err['errors'] as string[] | undefined)?.join(', ') ?? 'Signup failed.')
      }
    } catch {
      setError('Network error. Please try again.')
    } finally {
      setSubmitting(false)
    }
  }

  const fieldCls =
    'w-full rounded-md border border-slate-300 px-3 py-2 text-sm text-slate-900 shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500'

  return (
    <div className="min-h-screen bg-slate-50 flex items-center justify-center px-4">
      <div className="w-full max-w-sm bg-white rounded-xl shadow-sm border border-slate-200 p-8">
        <p className="text-sm font-semibold tracking-wide text-indigo-600 mb-1">Moneyball</p>
        <h1 className="text-2xl font-bold text-slate-900 mb-6">Create your account</h1>

        {error && (
          <div
            className="mb-4 rounded-md bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-800"
            role="alert"
          >
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label htmlFor="name" className="block text-sm font-medium text-slate-700 mb-1">
              Name
            </label>
            <input
              id="name"
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              required
              autoFocus
              className={fieldCls}
            />
          </div>
          <div>
            <label htmlFor="email" className="block text-sm font-medium text-slate-700 mb-1">
              Email
            </label>
            <input
              id="email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              className={fieldCls}
            />
          </div>
          <div>
            <label htmlFor="password" className="block text-sm font-medium text-slate-700 mb-1">
              Password
            </label>
            <input
              id="password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={8}
              className={fieldCls}
            />
          </div>
          <button
            type="submit"
            disabled={submitting}
            className="w-full rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            {submitting ? 'Creating account…' : 'Create account'}
          </button>
        </form>
      </div>
    </div>
  )
}
