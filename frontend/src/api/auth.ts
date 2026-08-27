import { api } from './client'
import type { AuthResponse, User } from '../types'

export function login(email: string, password: string): Promise<AuthResponse> {
  return api.post<AuthResponse>('/session', { email, password })
}

export function logout(): Promise<null> {
  return api.delete<null>('/session')
}

export function me(): Promise<User> {
  return api.get<User>('/me')
}
