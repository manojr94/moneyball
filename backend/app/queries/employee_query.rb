class EmployeeQuery
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  SORT_COLUMNS = {
    'employee_number' => 'employees.employee_number',
    'last_name' => 'employees.last_name',
    'hire_date' => 'employees.hire_date'
  }.freeze

  attr_reader :per_page, :error

  # rubocop:disable Metrics/AbcSize
  def initialize(params = {})
    @status        = params[:status].presence
    @department_id = params[:department_id].presence
    @country_code  = params[:country_code].presence
    @job_title     = params[:job_title].presence
    @job_level     = params[:job_level].presence
    @sort_key      = resolve_sort(params[:sort])
    @sort_col      = SORT_COLUMNS[@sort_key]
    @per_page      = clamp_per_page(params[:per_page])
    @cursor        = decode_cursor(params[:cursor])
    @error         = validate_filters(params)
  end
  # rubocop:enable Metrics/AbcSize

  def valid?
    @error.nil?
  end

  def call
    rel = Employee.includes(:department, :country)
    rel = apply_filters(rel)
    rel = apply_cursor(rel)
    rel.order("#{@sort_col} ASC, employees.id ASC").limit(@per_page + 1)
  end

  def next_cursor(employees)
    return nil unless employees.size > @per_page

    last = employees[@per_page - 1]
    encode_cursor(sort_value_for(last), last.id)
  end

  private

  def validate_filters(params)
    return unless params[:status].present? && Employee::STATUSES.exclude?(params[:status])

    "status must be one of: #{Employee::STATUSES.join(', ')}"
  end

  def apply_filters(rel)
    rel = rel.where(status: @status) if @status
    rel = rel.where(department_id: @department_id) if @department_id
    rel = rel.where(country_code: @country_code) if @country_code
    rel = rel.where(job_title: @job_title) if @job_title
    rel = rel.where(job_level: @job_level) if @job_level
    rel
  end

  # Uses the "OR-expanded" form rather than Postgres row-value comparison syntax
  # so the query is portable and readable in EXPLAIN output.
  def apply_cursor(rel)
    return rel unless @cursor

    sort_val, cursor_id = @cursor
    rel.where(
      "#{@sort_col} > ? OR (#{@sort_col} = ? AND employees.id > ?)",
      sort_val, sort_val, cursor_id
    )
  end

  def sort_value_for(employee)
    case @sort_key
    when 'employee_number' then employee.employee_number
    when 'last_name'       then employee.last_name
    when 'hire_date'       then employee.hire_date.to_s
    else raise ArgumentError, "unhandled sort key: #{@sort_key}"
    end
  end

  def encode_cursor(sort_val, id)
    Base64.strict_encode64(JSON.generate([sort_val.to_s, id]))
  end

  def decode_cursor(str)
    return nil if str.blank?

    parsed = JSON.parse(Base64.strict_decode64(str))
    raise ArgumentError unless parsed.is_a?(Array) && parsed.size == 2

    [parsed[0], Integer(parsed[1])]
  rescue StandardError
    nil
  end

  def resolve_sort(sort)
    SORT_COLUMNS.key?(sort) ? sort : 'employee_number'
  end

  def clamp_per_page(raw)
    (raw.to_i.nonzero? || DEFAULT_PER_PAGE).clamp(1, MAX_PER_PAGE)
  end
end
