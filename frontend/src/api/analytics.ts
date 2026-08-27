import { api } from './client'
import type { PayAnalyticsResponse, CompaRatioResponse, BandCoverageResponse } from '../types'

export function payAnalytics(params?: Record<string, string>): Promise<PayAnalyticsResponse> {
  return api.get<PayAnalyticsResponse>('/analytics/pay', params)
}

export function compaRatioAnalytics(params?: Record<string, string>): Promise<CompaRatioResponse> {
  return api.get<CompaRatioResponse>('/analytics/compa_ratio', params)
}

export function bandCoverage(): Promise<BandCoverageResponse> {
  return api.get<BandCoverageResponse>('/analytics/band_coverage')
}
