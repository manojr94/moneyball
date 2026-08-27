import { api } from './client'
import type { SalaryBand } from '../types'

export function listBands(params?: Record<string, string>): Promise<SalaryBand[]> {
  return api.get<SalaryBand[]>('/salary_bands', params)
}

export function createBand(data: Partial<SalaryBand>): Promise<SalaryBand> {
  return api.post<SalaryBand>('/salary_bands', { salary_band: data })
}
