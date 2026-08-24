class RecordSalaryChange
  class Error < StandardError; end

  def self.call(employee:, amount_minor_units:, currency:, effective_date:, reason:, created_by_id: nil)
    salary = employee.salaries.build(
      amount_minor_units: amount_minor_units,
      currency: currency,
      effective_date: effective_date,
      reason: reason,
      created_by_id: created_by_id
    )

    raise Error, salary.errors.full_messages.join(', ') unless salary.save

    salary
  end
end
