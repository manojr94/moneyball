import { api } from './client'

export function login(email, password) {
  return api.post('/session', { email, password })
}

export function logout() {
  return api.delete('/session')
}

export function me() {
  return api.get('/me')
}
