const BASE_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:3000'

interface SignupParams {
  name: string
  email: string
  password: string
  token: string
}

export async function signup(params: SignupParams): Promise<{ status: number; body: unknown }> {
  const res = await fetch(`${BASE_URL}/registrations`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  })
  const body: unknown = await res.json()
  return { status: res.status, body }
}
