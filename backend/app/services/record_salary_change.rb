class RecordSalaryChange
  class Error < StandardError; end

  def self.call(employee:, **salary_attrs)
    salary = employee.salaries.build(**salary_attrs)
    raise Error, salary.errors.full_messages.join(', ') unless salary.save

    salary
  end
end
