import { api } from './client'

export function listBands(params) {
  return api.get('/salary_bands', params)
}

export function createBand(data) {
  return api.post('/salary_bands', { salary_band: data })
}
