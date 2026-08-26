import { useState, useRef } from 'react'
import PropTypes from 'prop-types'
import { Navigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { uploadEmployees } from '../api/imports'

export function ImportPage() {
  const { user } = useAuth()
  const [file, setFile] = useState(null)
  const [preview, setPreview] = useState(null)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState(null)
  const inputRef = useRef(null)

  if (user?.role !== 'hr_admin') return <Navigate to="/employees" replace />

  function handleFileChange(e) {
    setFile(e.target.files[0] ?? null)
    setPreview(null)
    setError(null)
  }

  async function handlePreview(e) {
    e.preventDefault()
    if (!file) return
    setSubmitting(true)
    setError(null)
    try {
      const { body } = await uploadEmployees(file, true)
      setPreview({ result: body, confirmed: false })
    } catch (err) {
      setError(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  async function handleConfirm() {
    if (!file) return
    setSubmitting(true)
    setError(null)
    try {
      const { body } = await uploadEmployees(file, false)
      setPreview({ result: body, confirmed: true })
    } catch (err) {
      setError(err.message)
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
          <label className="block text-sm font-medium text-slate-700 mb-1" htmlFor="csv-file">
            CSV file
          </label>
          <input
            id="csv-file"
            ref={inputRef}
            type="file"
            accept=".csv"
            onChange={handleFileChange}
            className="block w-full text-sm text-slate-500 file:mr-3 file:py-1.5 file:px-3
                       file:rounded file:border-0 file:text-sm file:font-medium
                       file:bg-indigo-50 file:text-indigo-700 hover:file:bg-indigo-100
                       cursor-pointer mb-4"
          />
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

      {error && (
        <p className="text-sm text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2 mb-4">
          {error}
        </p>
      )}

      {result && <ImportResult result={result} confirmed={confirmed} />}

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

function ImportResult({ result, confirmed }) {
  if (result.header_error) {
    return (
      <div className="rounded border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
        <strong>File rejected:</strong> {result.header_error}
      </div>
    )
  }

  const s = result.summary
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

ImportResult.propTypes = {
  result: PropTypes.shape({
    header_error: PropTypes.string,
    summary: PropTypes.shape({
      rows_total: PropTypes.number,
      rows_valid: PropTypes.number,
      rows_invalid: PropTypes.number,
      employees_created: PropTypes.number,
      salaries_created: PropTypes.number,
      errors_reported: PropTypes.number,
      errors_capped_at: PropTypes.number,
    }),
    errors: PropTypes.arrayOf(
      PropTypes.shape({
        row: PropTypes.number,
        employee_number: PropTypes.string,
        messages: PropTypes.arrayOf(PropTypes.string),
      })
    ),
  }).isRequired,
  confirmed: PropTypes.bool.isRequired,
}
