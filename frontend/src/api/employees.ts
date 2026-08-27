import { api } from './client'
import type { Employee, EmployeeListResponse, Salary } from '../types'

export function listEmployees(params?: Record<string, string | number | boolean | undefined>): Promise<EmployeeListResponse> {
  return api.get<EmployeeListResponse>('/employees', params)
}

export function getEmployee(id: string | undefined): Promise<Employee> {
  return api.get<Employee>(`/employees/${id}`)
}

export function createEmployee(data: Partial<Employee>): Promise<Employee> {
  return api.post<Employee>('/employees', { employee: data })
}

export function updateEmployee(id: number, data: Partial<Employee>): Promise<Employee> {
  return api.patch<Employee>(`/employees/${id}`, { employee: data })
}

export function listSalaries(employeeId: string | undefined): Promise<Salary[]> {
  return api.get<Salary[]>(`/employees/${employeeId}/salaries`)
}

export function createSalary(employeeId: string | number, data: Partial<Salary>): Promise<Salary> {
  return api.post<Salary>(`/employees/${employeeId}/salaries`, { salary: data })
}
