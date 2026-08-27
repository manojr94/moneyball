import { api } from './client'
import type { Department } from '../types'

export function listDepartments(): Promise<Department[]> {
  return api.get<Department[]>('/departments')
}
