import { useState, useRef, useEffect } from 'react'
import { Navigate, useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { uploadEmployees } from '../api/imports'
import type { ImportResult, ImportSummary } from '../types'

interface PreviewState {
  result: ImportResult
  confirmed: boolean
}

export function ImportPage() {
  const { user } = useAuth()
  const navigate = useNavigate()
  const [file, setFile] = useState<File | null>(null)
  const [preview, setPreview] = useState<PreviewState | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [phase, setPhase] = useState<'preview' | 'import' | null>(null)
  const [error, setError] = useState<string | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  if (user?.role !== 'hr_admin') return <Navigate to="/employees" replace />

  function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    setFile(e.target.files?.[0] ?? null)
    setPreview(null)
    setError(null)
  }

  function handleDrop(e: React.DragEvent<HTMLDivElement>) {
    e.preventDefault()
    const dropped = e.dataTransfer.files[0]
    if (dropped?.name.endsWith('.csv')) {
      setFile(dropped)
      setPreview(null)
      setError(null)
    }
  }

  async function handlePreview(e: React.FormEvent) {
    e.preventDefault()
    if (!file) return
    setSubmitting(true)
    setPhase('preview')
    setError(null)
    try {
      const { body } = await uploadEmployees(file, true)
      setPreview({ result: body as ImportResult, confirmed: false })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error')
    } finally {
      setSubmitting(false)
    }
  }

  async function handleConfirm() {
    if (!file) return
    setSubmitting(true)
    setPhase('import')
    setError(null)
    try {
      const { body } = await uploadEmployees(file, false)
      const result = body as ImportResult
      setPreview({ result, confirmed: true })
      navigate('/employees', { state: { importSuccess: result.summary.employees_created } })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error')
    } finally {
      setSubmitting(false)
    }
  }

  function handleReset() {
    setFile(null)
    setPreview(null)
    setError(null)
    if (inputRef.current) inputRef.current.value = ''
  }

  const result = preview?.result
  const confirmed = preview?.confirmed

  return (
    <div className="p-6 max-w-2xl mx-auto">
      <h1 className="text-xl font-semibold text-slate-900 mb-1">Import Employees</h1>
      <p className="text-sm text-slate-500 mb-6">
        Upload a CSV file to add or update employees in bulk. Preview first to check for errors
        before committing.
      </p>

      {!confirmed && (
        <form onSubmit={handlePreview} className="mb-6">
          <input
            id="csv-file"
            data-testid="csv-input"
            ref={inputRef}
            type="file"
            accept=".csv"
            onChange={handleFileChange}
            className="sr-only"
          />
          <div
            onDrop={submitting ? undefined : handleDrop}
            onDragOver={(e) => e.preventDefault()}
            onClick={() => !submitting && inputRef.current?.click()}
            className={`mb-4 flex flex-col items-center justify-center gap-2 rounded-lg border-2
                       border-dashed px-6 py-10 text-center transition-colors
                       ${submitting
                         ? 'border-slate-200 bg-slate-50 cursor-not-allowed opacity-50'
                         : 'border-slate-300 bg-slate-50 cursor-pointer hover:border-indigo-400 hover:bg-indigo-50'}`}
          >
            {file ? (
              <>
                <svg xmlns="http://www.w3.org/2000/svg" className="h-8 w-8 text-indigo-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
                <p className="text-sm font-medium text-slate-800">{file.name}</p>
                <p className="text-xs text-slate-400">{(file.size / 1024).toFixed(0)} KB · click to change</p>
              </>
            ) : (
              <>
                <svg xmlns="http://www.w3.org/2000/svg" className="h-8 w-8 text-slate-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5m-13.5-9L12 3m0 0l4.5 4.5M12 3v13.5" />
                </svg>
                <p className="text-sm font-medium text-slate-700">Drop a CSV here or <span className="text-indigo-600">browse</span></p>
                <p className="text-xs text-slate-400">Only .csv files are accepted</p>
              </>
            )}
          </div>
          <button
            type="submit"
            disabled={!file || submitting}
            className="px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded
                       hover:bg-indigo-700 disabled:opacity-50 disabled:cursor-not-allowed
                       transition-colors"
          >
            {submitting ? 'Checking…' : 'Preview'}
          </button>
        </form>
      )}

      {submitting && <ImportProgress importing={phase === 'import'} />}

      {error && (
        <p className="text-sm text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2 mb-4">
          {error}
        </p>
      )}

      {result && <ImportResultPanel result={result} confirmed={confirmed ?? false} />}

      {result && !confirmed && result.summary?.rows_invalid === 0 && !result.header_error && (
        <div className="flex gap-3 mt-4">
          <button
            type="button"
            onClick={handleConfirm}
            disabled={submitting}
            className="px-4 py-2 bg-green-600 text-white text-sm font-medium rounded
                       hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed
                       transition-colors"
          >
            {submitting ? 'Importing…' : `Confirm import (${result.summary.rows_valid} employees)`}
          </button>
          <button
            type="button"
            onClick={handleReset}
            className="px-4 py-2 bg-white text-slate-700 text-sm font-medium rounded
                       border border-slate-300 hover:bg-slate-50 transition-colors"
          >
            Cancel
          </button>
        </div>
      )}

      {confirmed && (
        <button
          type="button"
          onClick={handleReset}
          className="mt-4 px-4 py-2 bg-white text-slate-700 text-sm font-medium rounded
                     border border-slate-300 hover:bg-slate-50 transition-colors"
        >
          Import another file
        </button>
      )}
    </div>
  )
}

function ImportResultPanel({ result, confirmed }: { result: ImportResult; confirmed: boolean }) {
  if (result.header_error) {
    return (
      <div className="rounded border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
        <strong>File rejected:</strong> {result.header_error}
      </div>
    )
  }

  const s: ImportSummary = result.summary
  const hasErrors = s.rows_invalid > 0

  return (
    <div className={`rounded border px-4 py-3 text-sm ${confirmed && !hasErrors ? 'border-green-200 bg-green-50' : hasErrors ? 'border-amber-200 bg-amber-50' : 'border-slate-200 bg-slate-50'}`}>
      <p className="font-medium text-slate-800 mb-2">
        {confirmed && !hasErrors
          ? `✓ Import complete — ${s.employees_created} employee${s.employees_created === 1 ? '' : 's'} added`
          : `Preview: ${s.rows_valid} of ${s.rows_total} rows valid`}
        {s.salaries_created > 0 && `, ${s.salaries_created} salaries recorded`}
      </p>

      <div className="flex gap-4 text-slate-600 mb-3">
        <span>Total rows: <strong>{s.rows_total}</strong></span>
        <span>Valid: <strong className="text-green-700">{s.rows_valid}</strong></span>
        {hasErrors && <span>Invalid: <strong className="text-red-700">{s.rows_invalid}</strong></span>}
        {s.errors_reported < s.rows_invalid && (
          <span className="text-slate-500">(first {s.errors_capped_at} errors shown)</span>
        )}
      </div>

      {result.errors?.length > 0 && (
        <ul className="space-y-1 max-h-64 overflow-y-auto">
          {result.errors.map((e, i) => (
            <li key={i} className="text-red-700">
              <span className="font-mono text-xs bg-red-100 px-1 rounded mr-2">row {e.row}</span>
              {e.employee_number && <span className="text-slate-600 mr-1">{e.employee_number}:</span>}
              {e.messages.join('; ')}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

function ImportProgress({ importing }: { importing: boolean }) {
  const [elapsed, setElapsed] = useState(0)
  useEffect(() => {
    const t = setInterval(() => setElapsed((s) => s + 1), 1000)
    return () => clearInterval(t)
  }, [])

  const label = importing ? 'Importing employees…' : 'Validating rows…'
  const hint =
    elapsed < 5
      ? 'This may take a moment for large files.'
      : `Still working… (${elapsed}s)`

  return (
    <div className="flex items-center gap-3 my-4 rounded-lg border border-slate-200 bg-slate-50 px-4 py-3">
      <svg
        className="animate-spin h-5 w-5 text-indigo-600 shrink-0"
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
      >
        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
      </svg>
      <div>
        <p className="text-sm font-medium text-slate-800">{label}</p>
        <p className="text-xs text-slate-500">{hint}</p>
      </div>
    </div>
  )
}
