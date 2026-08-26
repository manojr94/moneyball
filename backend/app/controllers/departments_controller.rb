class DepartmentsController < ApplicationController
  def index
    authorize!(:read)
    departments = Department.order(:name)
    render json: departments.map { |d| { id: d.id, name: d.name, slug: d.slug } }
  end
end
