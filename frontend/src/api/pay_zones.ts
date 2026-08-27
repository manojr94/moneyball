import { api } from './client'
import type { PayZone } from '../types'

export function listPayZones(): Promise<PayZone[]> {
  return api.get<PayZone[]>('/pay_zones')
}
