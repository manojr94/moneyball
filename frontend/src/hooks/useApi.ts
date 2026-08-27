import { useState, useEffect, useCallback } from 'react'

interface UseApiResult<T> {
  data: T | null
  loading: boolean
  error: string | null
  refresh: () => void
}

interface UseApiOptions {
  enabled?: boolean
}

export function useApi<T>(
  fn: () => Promise<T>,
  deps: unknown[] = [],
  { enabled = true }: UseApiOptions = {},
): UseApiResult<T> {
  const [data, setData] = useState<T | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // eslint-disable-next-line react-hooks/exhaustive-deps
  const stableFn = useCallback(fn, deps)

  const run = useCallback(() => {
    setLoading(true)
    setError(null)
    stableFn()
      .then(setData)
      .catch((e: unknown) => {
        const msg = e instanceof Error ? (e.message || 'Unknown error') : 'Unknown error'
        setError(msg)
      })
      .finally(() => setLoading(false))
  }, [stableFn])

  useEffect(() => {
    if (enabled) run()
  }, [run, enabled])

  return { data, loading, error, refresh: run }
}
