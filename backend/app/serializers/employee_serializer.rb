module EmployeeSerializer
  FIELDS = %i[id employee_number first_name last_name email country_code
              job_title job_level hire_date status terminated_on].freeze

  def self.render(employee)
    employee.as_json(only: FIELDS)
            .merge('department' => employee.department.as_json(only: %i[id name]))
  end
end
