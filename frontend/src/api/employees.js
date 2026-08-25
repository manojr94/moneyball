import { api } from './client'

export function listEmployees(params) {
  return api.get('/employees', params)
}

export function getEmployee(id) {
  return api.get(`/employees/${id}`)
}

export function createEmployee(data) {
  return api.post('/employees', { employee: data })
}

export function updateEmployee(id, data) {
  return api.patch(`/employees/${id}`, { employee: data })
}

export function listSalaries(employeeId) {
  return api.get(`/employees/${employeeId}/salaries`)
}

export function createSalary(employeeId, data) {
  return api.post(`/employees/${employeeId}/salaries`, { salary: data })
}
