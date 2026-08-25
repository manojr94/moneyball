import { useState, useEffect, useCallback } from 'react'

export function useApi(fn, deps = [], { enabled = true } = {}) {
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  // Memoize fn with the caller's deps. Callers must pass a stable fn (via useCallback).
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const stableFn = useCallback(fn, deps)

  const run = useCallback(() => {
    setLoading(true)
    setError(null)
    stableFn()
      .then(setData)
      .catch((e) => setError(e.message ?? 'Unknown error'))
      .finally(() => setLoading(false))
  }, [stableFn])

  useEffect(() => {
    if (enabled) run()
  }, [run, enabled])

  return { data, loading, error, refresh: run }
}
