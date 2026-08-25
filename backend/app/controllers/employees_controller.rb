class EmployeesController < ApplicationController
  before_action :set_employee, only: %i[show update]

  def index
    authorize!(:read, policy_class: EmployeePolicy)
    query = EmployeeQuery.new(query_params)
    return render json: { error: query.error }, status: :unprocessable_content unless query.valid?

    employees = query.call
    render json: {
      data: employees.map { |e| EmployeeSerializer.render(e) },
      meta: { next_cursor: query.next_cursor(employees), per_page: query.per_page }
    }
  end

  def show
    authorize!(:read, policy_class: EmployeePolicy)
    render json: EmployeeSerializer.render(@employee)
  end

  def create
    authorize!(:write, policy_class: EmployeePolicy)
    employee = Employee.new(employee_params)
    if employee.save
      render json: EmployeeSerializer.render(employee), status: :created
    else
      render json: { errors: employee.errors.full_messages }, status: :unprocessable_content
    end
  end

  def update
    authorize!(:write, policy_class: EmployeePolicy)
    if @employee.update(employee_params)
      render json: EmployeeSerializer.render(@employee)
    else
      render json: { errors: @employee.errors.full_messages }, status: :unprocessable_content
    end
  end

  private

  def set_employee
    @employee = Employee.includes(:department, :country).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'not found' }, status: :not_found
  end

  def query_params
    params.permit(:status, :department_id, :country_code, :sort, :cursor, :per_page)
  end

  def employee_params
    params.require(:employee).permit(
      :employee_number, :first_name, :last_name, :email,
      :country_code, :department_id, :job_title, :job_level,
      :hire_date, :status, :terminated_on
    )
  end
end
