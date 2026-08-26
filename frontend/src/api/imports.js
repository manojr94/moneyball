const BASE_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:3000'

// Standalone fetch for multipart CSV upload. Does not use the shared api/client
// request() helper because that always sets Content-Type: application/json,
// which conflicts with multipart/form-data (the browser must set that header
// with the boundary string). Import responses are structured JSON on all defined
// status codes (200 dry-run, 201 committed, 422 row errors), so we parse the
// body regardless and return { status, body } for the caller to interpret.
export async function uploadEmployees(file, dryRun) {
  const formData = new FormData()
  formData.append('file', file)
  formData.append('dry_run', String(dryRun))

  const token = localStorage.getItem('token')
  const res = await fetch(`${BASE_URL}/imports/employees`, {
    method: 'POST',
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: formData,
  })

  const body = await res.json()

  if (res.status >= 500) {
    throw new Error(`Server error (${res.status})`)
  }

  return { status: res.status, body }
}
