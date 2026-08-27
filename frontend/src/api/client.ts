const BASE_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:3000'

function getToken(): string | null {
  return localStorage.getItem('token')
}

async function request<T = unknown>(path: string, options: RequestInit = {}): Promise<T> {
  const token = getToken()
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    ...(options.headers as Record<string, string> | undefined),
  }

  const res = await fetch(`${BASE_URL}${path}`, { ...options, headers })

  if (res.status === 204) return null as T

  const body = await res.json() as Record<string, unknown>

  if (!res.ok) {
    if (res.status === 401 && localStorage.getItem('token')) {
      localStorage.removeItem('token')
      window.location.href = '/login'
      return null as T
    }
    const message =
      (body['error'] as string | undefined) ??
      (body['errors'] as string[] | undefined)?.join(', ') ??
      `HTTP ${res.status}`
    const err = Object.assign(new Error(message), { status: res.status, body })
    throw err
  }

  return body as T
}

export const api = {
  get: <T = unknown>(path: string, params?: Record<string, string | number | boolean | undefined>) => {
    const filteredParams = params
      ? Object.fromEntries(Object.entries(params).filter(([, v]) => v !== undefined))
      : undefined
    const qs = filteredParams && Object.keys(filteredParams).length > 0
      ? '?' + new URLSearchParams(filteredParams as Record<string, string>).toString()
      : ''
    return request<T>(`${path}${qs}`)
  },
  post: <T = unknown>(path: string, data: unknown) =>
    request<T>(path, { method: 'POST', body: JSON.stringify(data) }),
  patch: <T = unknown>(path: string, data: unknown) =>
    request<T>(path, { method: 'PATCH', body: JSON.stringify(data) }),
  delete: <T = unknown>(path: string) => request<T>(path, { method: 'DELETE' }),
}
