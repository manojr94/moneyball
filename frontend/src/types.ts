export type UserRole = 'hr_admin' | 'viewer'

export interface User {
  id: number
  name: string
  email: string
  role: UserRole
}

export interface Department {
  id: number
  name: string
  slug: string
}

export interface PayZone {
  id: number
  name: string
  slug: string
}

export type EmployeeStatus = 'active' | 'inactive' | 'terminated'

export interface Employee {
  id: number
  employee_number: string
  first_name: string
  last_name: string
  email: string
  country_code: string
  department_id: number
  department?: Department
  job_title: string
  job_level: string
  hire_date: string
  status: EmployeeStatus
  terminated_on: string | null
}

export type SalaryReason = 'merit' | 'promotion' | 'correction' | 'role_change' | 'new_hire'

export interface Salary {
  id: number
  employee_id: number
  amount_minor_units: number
  currency: string
  effective_date: string
  reason: SalaryReason
  created_by_id: number | null
}

export interface SalaryBand {
  id: number
  job_title: string
  job_level: string
  pay_zone_id: number
  pay_zone_name?: string
  currency: string
  min_minor_units: number
  mid_minor_units: number
  max_minor_units: number
  effective_from: string
  effective_to: string | null
}

export interface PayGroup {
  key: string
  label: string
  headcount: number
  min_usd_minor_units: number
  median_usd_minor_units: number
  avg_usd_minor_units: number
  max_usd_minor_units: number
  total_spend_usd_minor_units: number
}

export interface CompaGroup {
  key: string
  label: string
  headcount: number
  avg_compa_ratio: string | null
  below: number
  within: number
  above: number
  unresolved: number
}

export interface BandCoverageRow {
  job_title: string
  job_level: string
  pay_zone_id: number
  pay_zone_name?: string
}

export interface AnalyticsMeta {
  as_of: string
  rate_date: string
  group_by: string
  unconvertible_currencies: string[]
}

export interface PayAnalyticsResponse {
  groups: PayGroup[]
  meta: AnalyticsMeta
}

export interface CompaRatioResponse {
  groups: CompaGroup[]
  meta: AnalyticsMeta
}

export interface BandCoverageResponse {
  uncovered: BandCoverageRow[]
}

export interface ImportRowError {
  row: number
  employee_number?: string
  messages: string[]
}

export interface ImportSummary {
  rows_total: number
  rows_valid: number
  rows_invalid: number
  employees_created: number
  salaries_created: number
  errors_reported: number
  errors_capped_at: number
}

export interface ImportResult {
  header_error?: string
  summary: ImportSummary
  errors: ImportRowError[]
}

export interface EmployeeListResponse {
  data: Employee[]
  meta: { next_cursor: string | null }
}

export interface AuthResponse {
  token: string
  user: User
}
