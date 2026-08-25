class SalaryBandPolicy < ApplicationPolicy
  # Inherits read? (any authenticated user) and write? (hr_admin only).
end
