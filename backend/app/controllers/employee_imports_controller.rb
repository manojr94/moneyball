class EmployeeImportsController < ApplicationController
  def create
    authorize!(:write)

    csv = read_csv
    return render_missing_csv if csv.nil?

    result = ImportEmployees.call(csv, dry_run: dry_run?, actor: current_user)
    render json: serialize(result), status: response_status(result)
  end

  private

  # Accepts either a multipart file under :file, or a raw CSV string under :csv
  # (JSON body). Multipart is the default from a browser or curl -F; the string
  # form is a convenience for scripts and tests.
  # Multipart uploads pass the Rack tempfile (an IO) so the service can stream
  # rows without materializing the entire file as a string. The :csv string
  # form (scripts/tests) is accepted as-is.
  def read_csv
    file = params[:file]
    return file.tempfile if file.respond_to?(:tempfile)
    return file.read if file.respond_to?(:read)

    params[:csv] if params[:csv].is_a?(String) && params[:csv].present?
  end

  # Dry-run defaults to true — a missing or unrecognised flag never commits.
  # Only the explicit string "false" flips to commit mode.
  def dry_run?
    params[:dry_run].to_s != 'false'
  end

  def response_status(result)
    return :unprocessable_content if result.header_error
    return :created if result.committed
    return :unprocessable_content if !result.dry_run && result.errors.any?

    :ok
  end

  def render_missing_csv
    render json: { error: 'file is required (multipart :file or JSON :csv)' },
           status: :unprocessable_content
  end

  def serialize(result)
    {
      committed: result.committed,
      dry_run: result.dry_run,
      header_error: result.header_error,
      summary: summary_of(result),
      errors: result.errors.map { |e| { row: e.row, employee_number: e.employee_number, messages: e.messages } }
    }
  end

  def summary_of(result)
    {
      rows_total: result.rows_total,
      rows_valid: result.rows_valid,
      rows_invalid: result.rows_invalid,
      employees_created: result.employees_created,
      salaries_created: result.salaries_created,
      errors_reported: result.errors.size,
      errors_capped_at: ImportEmployees::MAX_ERRORS
    }
  end
end
