class SalariesController < ApplicationController
  before_action :set_employee

  def index
    authorize!(:read, policy_class: EmployeePolicy)
    salaries = @employee.salaries.order(effective_date: :desc, id: :desc).limit(200)
    render json: salaries.map { |s| serialize(s) }
  end

  def create
    authorize!(:write, policy_class: EmployeePolicy)
    salary = RecordSalaryChange.call(
      employee: @employee,
      **salary_params.to_h.symbolize_keys.merge(created_by_id: current_user.id)
    )
    render json: serialize(salary), status: :created
  rescue RecordSalaryChange::Error => e
    render json: { errors: [e.message] }, status: :unprocessable_content
  end

  private

  def set_employee
    @employee = Employee.find(params[:employee_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'not found' }, status: :not_found
  end

  def salary_params
    params.require(:salary).permit(:amount_minor_units, :currency, :effective_date, :reason)
  end

  def serialize(salary)
    { id: salary.id,
      employee_id: salary.employee_id,
      amount_minor_units: salary.amount_minor_units,
      currency: salary.currency,
      effective_date: salary.effective_date,
      reason: salary.reason,
      created_by_id: salary.created_by_id,
      created_at: salary.created_at }
  end
end
