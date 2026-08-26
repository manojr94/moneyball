import { api } from './client'

export function listDepartments() {
  return api.get('/departments')
}
