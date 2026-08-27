const BASE_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:3000'

// Standalone fetch for multipart CSV upload. Does not use the shared api/client
// request() helper because that always sets Content-Type: application/json,
// which conflicts with multipart/form-data (the browser must set that header
// with the boundary string).
export async function uploadEmployees(
  file: File,
  dryRun: boolean,
): Promise<{ status: number; body: unknown }> {
  const formData = new FormData()
  formData.append('file', file)
  formData.append('dry_run', String(dryRun))

  const token = localStorage.getItem('token')
  const res = await fetch(`${BASE_URL}/imports/employees`, {
    method: 'POST',
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: formData,
  })

  const body: unknown = await res.json()

  if (res.status >= 500) {
    throw new Error(`Server error (${res.status})`)
  }

  return { status: res.status, body }
}
