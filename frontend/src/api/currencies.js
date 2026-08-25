import { api } from './client'

export function listCurrencies() {
  return api.get('/currencies')
}
