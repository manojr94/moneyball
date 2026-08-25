class EmployeePolicy < ApplicationPolicy
  # read?  → any authenticated user  (inherited)
  # write? → hr_admin only           (inherited)
end
