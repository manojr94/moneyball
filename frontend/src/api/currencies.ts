import { api } from './client'

export function listCurrencies(): Promise<string[]> {
  return api.get<string[]>('/currencies')
}
