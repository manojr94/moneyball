const BASE_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:3000'

export async function signup({ name, email, password, token }) {
  const res = await fetch(`${BASE_URL}/registrations`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, email, password, token }),
  })
  const body = await res.json()
  return { status: res.status, body }
}
