require 'csv'

# Bulk-imports employees (and optional initial salaries) from a CSV.
#
# Dry-run and commit share one code path: both wrap the row loop in a
# transaction and roll back on any error. Dry-run additionally rolls back on
# success. This is the "preview matches commit" guarantee — the same
# validations, uniqueness checks, and callback side-effects run in both modes.
#
# Streaming: rows are processed one at a time. The source can be a String or
# any IO-like object (e.g. a Rack tempfile). The header line is read first for
# validation; the IO is rewound and CSV iterates the rest lazily.
#
# Batch inserts: valid attributes are buffered in ImportState and flushed with
# insert_all! every BATCH_SIZE rows. insert_all! bypasses ActiveRecord callbacks
# by design — validations ran in RowValidator and no after_create hooks exist on
# Employee or Salary. Any future hook on those models must account for this path.
class ImportEmployees
  MAX_ROWS   = 10_000
  MAX_ERRORS = 100
  BATCH_SIZE = 100

  REQUIRED_HEADERS = %w[
    employee_number first_name last_name email country_code
    department_name job_title job_level hire_date
  ].freeze

  Result = Struct.new(
    :committed, :dry_run, :rows_total, :rows_valid, :rows_invalid,
    :employees_created, :salaries_created, :errors, :header_error,
    keyword_init: true
  ) do
    def success?
      header_error.nil? && rows_invalid.zero?
    end
  end

  RowError = Struct.new(:row, :employee_number, :messages, keyword_init: true)

  def self.call(csv_source, dry_run:, actor: nil)
    new(csv_source, dry_run: dry_run, actor: actor).call
  end

  def initialize(csv_source, dry_run:, actor: nil)
    @csv_source = csv_source
    @dry_run    = dry_run
    @actor      = actor
    @state      = ImportState.new
  end

  def call
    csv, header_error = Parser.open_and_validate_headers(@csv_source)
    return header_failure_result(header_error) if header_error

    within_transaction { process_rows(csv) }
    build_result
  end

  private

  def within_transaction
    ActiveRecord::Base.transaction do
      yield
      raise ActiveRecord::Rollback if @state.header_error || @dry_run || @state.errors.any?
    end
  end

  def process_rows(csv)
    Parser.each_row(csv) do |row, row_num|
      if @state.rows_total >= MAX_ROWS
        @state.header_error = "file exceeds #{MAX_ROWS}-row limit; max is #{MAX_ROWS}"
        raise ActiveRecord::Rollback
      end
      RowValidator.new(row_num: row_num, row: row, state: @state, actor: @actor).call
      BatchFlusher.flush(@state) if @state.pending_employees.size >= BATCH_SIZE
    end
    BatchFlusher.flush(@state) unless @state.header_error
  end

  def header_failure_result(header_error)
    Result.new(
      committed: false, dry_run: @dry_run,
      rows_total: 0, rows_valid: 0, rows_invalid: 0,
      employees_created: 0, salaries_created: 0,
      errors: [], header_error: header_error
    )
  end

  def build_result
    return header_failure_result(@state.header_error) if @state.header_error

    committed = !@dry_run && @state.errors.empty?
    Result.new(
      committed: committed, dry_run: @dry_run,
      rows_total: @state.rows_total, rows_valid: @state.rows_valid,
      rows_invalid: @state.rows_total - @state.rows_valid,
      employees_created: committed ? @state.employees_created : 0,
      salaries_created: committed ? @state.salaries_created : 0,
      errors: @state.errors, header_error: nil
    )
  end

  # Opens the CSV source, validates headers without consuming data rows,
  # and returns a positioned CSV object ready for row-by-row iteration.
  # Returns [csv, nil] on success or [nil, error_string] on failure.
  class Parser
    def self.open_and_validate_headers(source)
      io      = to_io(source)
      start   = io.pos # position after any BOM has been skipped
      headers = read_header_line(io)
      err     = validate_headers(headers)
      return [nil, err] if err

      io.seek(start) # return to content start, not raw start, so BOM stays skipped
      [CSV.new(io, headers: true, skip_blanks: true), nil]
    rescue CSV::MalformedCSVError => e
      [nil, "malformed CSV: #{e.message}"]
    end

    def self.each_row(csv)
      row_num = 1 # header is line 1; first data row is line 2
      csv.each do |row|
        row_num += 1
        yield row, row_num
      end
    end

    def self.to_io(source)
      if source.is_a?(String)
        StringIO.new(strip_bom(source))
      else
        # Advance past a UTF-8 BOM if present so the CSV parser never sees it.
        # We read 3 bytes; if they're not the BOM we seek back to 0.
        bom = source.read(3).to_s
        source.seek(bom.b.start_with?("\xEF\xBB\xBF".b) ? 3 : 0)
        source
      end
    end

    def self.read_header_line(io)
      line = io.gets
      return [] if line.nil?

      CSV.parse_line(strip_bom(line))&.map { |h| h&.to_s&.strip } || []
    end

    def self.strip_bom(text)
      text.to_s.sub(/\A\xEF\xBB\xBF/, '').sub(/\A\uFEFF/, '')
    end

    def self.validate_headers(headers)
      return 'file is empty or has no header row' if headers.nil? || headers.compact.empty?

      missing = REQUIRED_HEADERS - headers.compact.map { |h| h.to_s.strip }
      "missing required column(s): #{missing.join(', ')}" if missing.any?
    end
  end

  # Accumulates counts, seen-so-far maps, error list, and batch buffers.
  class ImportState
    attr_reader :errors, :seen_numbers, :seen_emails, :dept_cache, :country_cache,
                :pending_employees
    attr_accessor :rows_total, :rows_valid, :employees_created, :salaries_created,
                  :header_error

    def initialize
      @errors = []
      @seen_numbers = {}
      @seen_emails = {}
      @dept_cache = {}
      @country_cache = Set.new # country codes whose existence has already been confirmed/created
      @pending_employees = [] # [{emp_attrs:, salary_attrs:, row_num:}]
      @rows_total = @rows_valid = @employees_created = @salaries_created = 0
      @header_error = nil
    end

    def record_error(row_num, employee_number, messages)
      return if @errors.size >= MAX_ERRORS

      @errors << RowError.new(row: row_num, employee_number: employee_number, messages: Array(messages))
    end
  end

  # Validates a single CSV row and buffers valid attributes into ImportState.
  # Does not persist — persistence is delegated to BatchFlusher.
  # rubocop:disable Metrics/ClassLength -- bulk of length is private helpers, not logic
  class RowValidator
    SALARY_FIELDS = %w[salary_amount salary_currency salary_effective_date].freeze

    def initialize(row_num:, row:, state:, actor:)
      @row_num = row_num
      @row     = row
      @state   = state
      @actor   = actor
    end

    def call
      @state.rows_total += 1
      @attrs = RowAttrs.extract(@row)
      return if duplicate_in_file?

      validate_and_buffer
    rescue ActiveRecord::RecordNotUnique => e
      field = e.message[/employee_number|email/] || 'unique field'
      error("conflicts with an existing record (#{field})")
    end

    private

    def validate_and_buffer
      dept     = resolve_department(@attrs[:department_name])
      employee = build_employee(dept)
      unless employee.valid?(:import)
        return @state.record_error(@row_num, @attrs[:employee_number], employee.errors.full_messages)
      end

      salary_attrs = build_salary_attrs
      return if salary_attrs == :invalid

      buffer_row(employee, salary_attrs)
    end

    def buffer_row(employee, salary_attrs)
      @state.pending_employees << {
        emp_attrs: employee_db_attrs(employee),
        salary_attrs: salary_attrs,
        row_num: @row_num
      }
      @state.rows_valid += 1
    end

    def duplicate_in_file?
      dup = duplicate_seen
      return false unless dup

      field, prior = dup
      error("duplicate #{field} in this file (also on row #{prior})")
      true
    end

    def duplicate_seen
      if @attrs[:employee_number] && (prior = @state.seen_numbers[@attrs[:employee_number]])
        ['employee_number', prior]
      elsif @attrs[:email] && (prior = @state.seen_emails[@attrs[:email]])
        ['email', prior]
      else
        remember_row
        nil
      end
    end

    def remember_row
      @state.seen_numbers[@attrs[:employee_number]] = @row_num if @attrs[:employee_number]
      @state.seen_emails[@attrs[:email]] = @row_num if @attrs[:email]
    end

    def build_employee(dept)
      emp = Employee.new(
        @attrs.slice(:employee_number, :first_name, :last_name, :email, :country_code,
                     :job_title, :job_level, :hire_date, :status, :terminated_on)
              .merge(department: dept)
      )
      # Country existence is guaranteed by register_country; suppress the
      # per-row DB lookup that before_validation :ensure_country_exists would do.
      register_country(@attrs[:country_code])
      emp.skip_country_check = @state.country_cache.include?(@attrs[:country_code])
      emp
    end

    # Ensures the country exists in the DB and marks it in the cache. No-op after
    # first call for a given code; only one DB lookup per unique country per import.
    def register_country(code)
      return if code.blank? || @state.country_cache.include?(code)

      Country.find_or_create_unconfigured(code) unless Country.exists?(code: code)
      @state.country_cache.add(code)
    end

    def employee_db_attrs(employee)
      now = Time.current
      employee.attributes
              .slice(*%w[employee_number first_name last_name email country_code
                         department_id job_title job_level hire_date status terminated_on])
              .symbolize_keys
              .merge(created_at: now, updated_at: now)
    end

    def build_salary_attrs
      return nil if SALARY_FIELDS.none? { |f| @attrs[f.to_sym] }
      return :invalid unless salary_fields_present?

      amount_minor = parse_salary_amount
      return :invalid if amount_minor == :invalid

      salary_hash(amount_minor)
    end

    def parse_salary_amount
      to_minor_units(@attrs[:salary_amount], @attrs[:salary_currency])
    rescue ArgumentError, Money::Currency::UnknownCurrency => e
      error("salary: #{e.message}")
      :invalid
    end

    def salary_hash(amount_minor)
      now = Time.current
      {
        amount_minor_units: amount_minor,
        currency: @attrs[:salary_currency],
        effective_date: @attrs[:salary_effective_date] || @attrs[:hire_date],
        reason: 'new_hire',
        created_by_id: @actor&.id,
        created_at: now,
        updated_at: now
      }
    end

    def salary_fields_present?
      missing = [
        ('salary_amount' if @attrs[:salary_amount].blank?),
        ('salary_currency' if @attrs[:salary_currency].blank?)
      ].compact
      return true if missing.empty?

      error("salary: missing #{missing.join(', ')}")
      false
    end

    def resolve_department(name)
      return nil if name.blank?

      key = name.downcase
      @state.dept_cache[key] ||= Department.where('LOWER(name) = ?', key).first
    end

    def to_minor_units(amount_str, currency)
      cleaned = amount_str.to_s.delete(',').strip
      Money.from_amount(BigDecimal(cleaned), currency).fractional
    end

    def error(message)
      @state.record_error(@row_num, @attrs[:employee_number], [message])
    end
  end

  # rubocop:enable Metrics/ClassLength

  # Flushes the pending-employees buffer via insert_all! and inserts salary rows.
  # Called every BATCH_SIZE rows and once at end of file.
  # rubocop:disable Rails/SkipsModelValidations -- intentional; validations ran in RowValidator
  module BatchFlusher
    module_function

    def flush(state)
      pending = state.pending_employees
      return if pending.empty?

      # Savepoint so a unique-violation rolls back only this batch, not the
      # entire outer transaction. Without it, PG aborts the outer transaction on
      # the first constraint error and all subsequent queries raise
      # PG::InFailedSqlTransaction — breaking dry-run reports and early-error paths.
      ActiveRecord::Base.transaction(requires_new: true) do
        insert_employees(state, pending)
      end
    rescue ActiveRecord::RecordNotUnique => e
      handle_unique_violation(state, pending, e)
    end

    def insert_employees(state, pending)
      # rubocop:disable Rails/Pluck -- pending is a plain Ruby array, not an AR relation
      emp_attrs    = pending.map { |p| p[:emp_attrs] }
      has_salaries = pending.any? { |p| p[:salary_attrs] }
      # rubocop:enable Rails/Pluck

      insert_with_salaries(state, pending, emp_attrs) if has_salaries
      Employee.insert_all!(emp_attrs) unless has_salaries # skip RETURNING when unused

      state.employees_created += emp_attrs.size
      pending.clear
    end

    def insert_with_salaries(state, pending, emp_attrs)
      result = Employee.insert_all!(emp_attrs, returning: %w[id employee_number])
      id_map = result.to_h { |r| [r['employee_number'], r['id']] }
      insert_salaries(state, pending, id_map)
    end

    def insert_salaries(state, pending, id_map)
      salary_rows = salary_rows_for(pending, id_map)
      Salary.insert_all!(salary_rows) if salary_rows.any?
      state.salaries_created += salary_rows.size
    end

    def salary_rows_for(pending, id_map)
      pending.filter_map do |p|
        next unless p[:salary_attrs]

        emp_id = id_map[p[:emp_attrs][:employee_number]]
        next unless emp_id

        p[:salary_attrs].merge(employee_id: emp_id)
      end
    end

    def handle_unique_violation(state, pending, err)
      field = err.message[/employee_number|email/] || 'unique field'
      # insert_all! is atomic: one conflict rolls back the whole batch. All rows
      # in the batch are marked errored. Re-upload after removing the conflicting
      # row(s) to find out which ones were actually clean.
      pending.each do |p|
        state.rows_valid -= 1 # undo the increment from RowValidator#buffer_row
        state.record_error(p[:row_num], p[:emp_attrs][:employee_number],
                           ["batch rejected — a row in this batch conflicts on #{field}; " \
                            "re-upload after removing the conflict to identify which rows are clean"])
      end
      pending.clear
    end
  end
  # rubocop:enable Rails/SkipsModelValidations

  # Extracts, trims, and normalizes a CSV::Row into a symbol-keyed hash.
  module RowAttrs
    NORMALIZERS = {
      'employee_number' => :itself, 'first_name' => :itself, 'last_name' => :itself,
      'department_name' => :itself, 'job_title' => :itself, 'job_level' => :itself,
      'hire_date' => :itself, 'terminated_on' => :itself,
      'salary_amount' => :itself, 'salary_effective_date' => :itself,
      'country_code' => :upcase, 'salary_currency' => :upcase,
      'email' => :downcase
    }.freeze

    module_function

    def extract(row)
      attrs = { status: trim(row['status']) || 'active' }
      NORMALIZERS.each { |f, op| attrs[f.to_sym] = trim(row[f])&.public_send(op) }
      attrs
    end

    def trim(value)
      return nil if value.nil?

      trimmed = value.to_s.strip
      trimmed.empty? ? nil : trimmed
    end
  end
end
