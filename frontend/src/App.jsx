import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { AuthProvider } from './contexts/AuthContext'
import { Layout } from './components/Layout'
import { LoginPage } from './pages/LoginPage'
import { EmployeeListPage } from './pages/EmployeeListPage'
import { EmployeeDetailPage } from './pages/EmployeeDetailPage'
import { AnalyticsDashboard } from './pages/AnalyticsDashboard'
import { BandView } from './pages/BandView'
import { ImportPage } from './pages/ImportPage'
import { TooltipProvider } from './components/Tooltip'

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <TooltipProvider>
          <Routes>
            <Route path="/login" element={<LoginPage />} />
            <Route element={<Layout />}>
              <Route index element={<Navigate to="/employees" replace />} />
              <Route path="/employees" element={<EmployeeListPage />} />
              <Route path="/employees/:id" element={<EmployeeDetailPage />} />
              <Route path="/analytics" element={<AnalyticsDashboard />} />
              <Route path="/bands" element={<BandView />} />
              <Route path="/import" element={<ImportPage />} />
            </Route>
          </Routes>
        </TooltipProvider>
      </AuthProvider>
    </BrowserRouter>
  )
}
