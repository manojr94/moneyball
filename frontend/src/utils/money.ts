const SUBUNIT_EXPONENTS: Record<string, number> = {
  JPY: 0,
  KWD: 3,
  BHD: 3,
  JOD: 3,
}

function subunitDivisor(currency: string): number {
  const exp = SUBUNIT_EXPONENTS[currency] ?? 2
  return Math.pow(10, exp)
}

export function formatMoney(minorUnits: number | null | undefined, currency: string | null | undefined): string {
  if (minorUnits == null || currency == null) return '—'
  const divisor = subunitDivisor(currency)
  const amount = Number(minorUnits) / divisor
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency,
    minimumFractionDigits: SUBUNIT_EXPONENTS[currency] === 0 ? 0 : 2,
  }).format(amount)
}

export function majorToMinor(amount: string | number, currency: string): number {
  const divisor = subunitDivisor(currency)
  return Math.round(Number(amount) * divisor)
}
