import { api } from './client'

export function payAnalytics(params) {
  return api.get('/analytics/pay', params)
}

export function compaRatioAnalytics(params) {
  return api.get('/analytics/compa_ratio', params)
}

export function bandCoverage() {
  return api.get('/analytics/band_coverage')
}
