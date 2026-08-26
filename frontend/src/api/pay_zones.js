import { api } from './client'

export function listPayZones() {
  return api.get('/pay_zones')
}
